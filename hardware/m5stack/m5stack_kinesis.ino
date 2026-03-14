/**
 * M5Stack Core 2 — AWS Kinesis Data Stream Publisher
 *
 * Sends a JSON event to AWS Kinesis whenever a touchscreen button is pressed.
 * Uses AWS Signature Version 4 (HMAC-SHA256) for authentication.
 *
 * Hardware: M5Stack Core 2 (ESP32, 320x240 touchscreen, 3 virtual buttons)
 *
 * Required libraries (install via Arduino Library Manager):
 *   - M5Core2  (by M5Stack)
 *   - ArduinoJson (by Benoit Blanchon) >= 6.x
 *
 * Built-in ESP32 libraries used:
 *   - WiFi.h
 *   - WiFiClientSecure.h
 *   - HTTPClient.h
 *   - mbedtls/md.h  (HMAC-SHA256, SHA256 — included with ESP32 Arduino core)
 *   - time.h        (NTP sync)
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * SETUP STEPS:
 *   1. Run `terraform apply` in terraform-aws/ to create the Kinesis stream and
 *      IAM user (aws_iam_user.m5stack).
 *   2. In the AWS Console → IAM → Users → <project>-m5stack-device
 *      → Security credentials → Create access key → Application running outside AWS
 *      Copy the Access Key ID and Secret Access Key.
 *   3. Fill in the CONFIG section below.
 *   4. Flash to your M5Stack Core 2.
 * ─────────────────────────────────────────────────────────────────────────────
 */

#include <M5Core2.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "mbedtls/md.h"

// ============================================================================
// CONFIG — fill these in before flashing
// ============================================================================

// WiFi credentials
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// AWS credentials for the m5stack IAM user (from AWS Console)
const char* AWS_ACCESS_KEY_ID     = "YOUR_ACCESS_KEY_ID";
const char* AWS_SECRET_ACCESS_KEY = "YOUR_SECRET_ACCESS_KEY";

// AWS region and Kinesis stream name (from terraform output)
const char* AWS_REGION      = "ap-southeast-2";
const char* KINESIS_STREAM  = "caringal-web-app-iot-events";  // <project_name>-iot-events

// Device identity — change per device if you have multiple M5Stacks
const char* DEVICE_ID = "m5stack-core2-001";

// ============================================================================
// Constants
// ============================================================================

#define KINESIS_HOST_TEMPLATE "kinesis.%s.amazonaws.com"
#define SHA256_DIGEST_SIZE    32
#define STATUS_OK_COLOR       GREEN
#define STATUS_ERR_COLOR      RED
#define STATUS_INFO_COLOR     WHITE

// ============================================================================
// Globals
// ============================================================================

static char kinesisHost[64];
static bool wifiConnected = false;
static uint32_t lastSendMs = 0;
static uint16_t eventCount = 0;

// ============================================================================
// Crypto helpers (mbedtls wrappers)
// ============================================================================

/**
 * Compute SHA-256 of `input` and write 32 raw bytes into `output`.
 */
static void sha256Raw(const uint8_t* input, size_t len, uint8_t output[SHA256_DIGEST_SIZE]) {
    mbedtls_md_context_t ctx;
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, 0);
    mbedtls_md_starts(&ctx);
    mbedtls_md_update(&ctx, input, len);
    mbedtls_md_finish(&ctx, output);
    mbedtls_md_free(&ctx);
}

/**
 * Compute HMAC-SHA256 of `data` using `key` and write 32 raw bytes into `output`.
 */
static void hmacSha256Raw(const uint8_t* key, size_t keyLen,
                          const uint8_t* data, size_t dataLen,
                          uint8_t output[SHA256_DIGEST_SIZE]) {
    mbedtls_md_context_t ctx;
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, 1);  // 1 = HMAC mode
    mbedtls_md_hmac_starts(&ctx, key, keyLen);
    mbedtls_md_hmac_update(&ctx, data, dataLen);
    mbedtls_md_hmac_finish(&ctx, output);
    mbedtls_md_free(&ctx);
}

/**
 * Convert raw bytes to lowercase hex string.
 */
static String toHex(const uint8_t* data, size_t len) {
    String result;
    result.reserve(len * 2);
    for (size_t i = 0; i < len; i++) {
        char buf[3];
        snprintf(buf, sizeof(buf), "%02x", data[i]);
        result += buf;
    }
    return result;
}

/**
 * SHA-256 of a string, returned as a lowercase hex string.
 */
static String sha256Hex(const String& s) {
    uint8_t hash[SHA256_DIGEST_SIZE];
    sha256Raw((const uint8_t*)s.c_str(), s.length(), hash);
    return toHex(hash, SHA256_DIGEST_SIZE);
}

/**
 * Derive the AWS4 signing key.
 * kSigning = HMAC(HMAC(HMAC(HMAC("AWS4" + secret, date), region), service), "aws4_request")
 */
static void deriveSigningKey(const char* secretKey,
                             const char* datestamp,   // YYYYMMDD
                             const char* region,
                             const char* service,
                             uint8_t signingKey[SHA256_DIGEST_SIZE]) {
    // kDate = HMAC("AWS4" + secret, datestamp)
    String kSecret = String("AWS4") + secretKey;
    uint8_t kDate[SHA256_DIGEST_SIZE];
    hmacSha256Raw((const uint8_t*)kSecret.c_str(), kSecret.length(),
                  (const uint8_t*)datestamp, strlen(datestamp), kDate);

    // kRegion = HMAC(kDate, region)
    uint8_t kRegion[SHA256_DIGEST_SIZE];
    hmacSha256Raw(kDate, SHA256_DIGEST_SIZE,
                  (const uint8_t*)region, strlen(region), kRegion);

    // kService = HMAC(kRegion, service)
    uint8_t kService[SHA256_DIGEST_SIZE];
    hmacSha256Raw(kRegion, SHA256_DIGEST_SIZE,
                  (const uint8_t*)service, strlen(service), kService);

    // kSigning = HMAC(kService, "aws4_request")
    const char* terminator = "aws4_request";
    hmacSha256Raw(kService, SHA256_DIGEST_SIZE,
                  (const uint8_t*)terminator, strlen(terminator), signingKey);
}

// ============================================================================
// Base64 encoder (needed for Kinesis Data field)
// ============================================================================

static const char B64_CHARS[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static String base64Encode(const String& input) {
    String result;
    const uint8_t* data = (const uint8_t*)input.c_str();
    size_t len = input.length();
    result.reserve(((len + 2) / 3) * 4);

    for (size_t i = 0; i < len; i += 3) {
        uint8_t b0 = data[i];
        uint8_t b1 = (i + 1 < len) ? data[i + 1] : 0;
        uint8_t b2 = (i + 2 < len) ? data[i + 2] : 0;

        result += B64_CHARS[b0 >> 2];
        result += B64_CHARS[((b0 & 0x03) << 4) | (b1 >> 4)];
        result += (i + 1 < len) ? B64_CHARS[((b1 & 0x0F) << 2) | (b2 >> 6)] : '=';
        result += (i + 2 < len) ? B64_CHARS[b2 & 0x3F]                       : '=';
    }
    return result;
}

// ============================================================================
// AWS SigV4 — build Authorization header
// ============================================================================

struct SigV4Result {
    String authorization;
    String amzDate;       // ISO8601 UTC: YYYYMMDDTHHmmSSZ
    String datestamp;     // YYYYMMDD
};

/**
 * Build a signed Authorization header for a Kinesis PutRecord call.
 *
 * @param payload  The raw JSON body string (will be SHA-256 hashed).
 * @param target   X-Amz-Target value, e.g. "Kinesis_20131202.PutRecord"
 */
static SigV4Result buildAuthHeader(const String& payload, const char* target) {
    // ── 1. Get current UTC time ──────────────────────────────────────────────
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        Serial.println("[SigV4] Time not synced — NTP failed?");
    }

    char datestamp[9];   // YYYYMMDD
    char amzDate[17];    // YYYYMMDDTHHmmSSZ
    strftime(datestamp, sizeof(datestamp), "%Y%m%d",         &timeinfo);
    strftime(amzDate,   sizeof(amzDate),   "%Y%m%dT%H%M%SZ", &timeinfo);

    // ── 2. Hash of payload ───────────────────────────────────────────────────
    String payloadHash = sha256Hex(payload);

    // ── 3. Canonical request ─────────────────────────────────────────────────
    // Headers must be sorted alphabetically by header name (lowercase).
    // Signed headers: content-type, host, x-amz-date, x-amz-target
    String canonicalHeaders =
        String("content-type:application/x-amz-json-1.1\n") +
        "host:" + kinesisHost + "\n" +
        "x-amz-date:" + amzDate + "\n" +
        "x-amz-target:" + target + "\n";

    String signedHeaders = "content-type;host;x-amz-date;x-amz-target";

    String canonicalRequest =
        String("POST\n")         // HTTP method
        + "/\n"                   // canonical URI
        + "\n"                    // canonical query string (empty)
        + canonicalHeaders + "\n"
        + signedHeaders + "\n"
        + payloadHash;

    // ── 4. String to sign ────────────────────────────────────────────────────
    String credentialScope = String(datestamp) + "/" + AWS_REGION + "/kinesis/aws4_request";

    String stringToSign =
        String("AWS4-HMAC-SHA256\n")
        + amzDate + "\n"
        + credentialScope + "\n"
        + sha256Hex(canonicalRequest);

    // ── 5. Signing key ───────────────────────────────────────────────────────
    uint8_t signingKey[SHA256_DIGEST_SIZE];
    deriveSigningKey(AWS_SECRET_ACCESS_KEY, datestamp, AWS_REGION, "kinesis", signingKey);

    // ── 6. Signature ─────────────────────────────────────────────────────────
    uint8_t sigBytes[SHA256_DIGEST_SIZE];
    hmacSha256Raw(signingKey, SHA256_DIGEST_SIZE,
                  (const uint8_t*)stringToSign.c_str(), stringToSign.length(),
                  sigBytes);
    String signature = toHex(sigBytes, SHA256_DIGEST_SIZE);

    // ── 7. Authorization header ──────────────────────────────────────────────
    String authorization =
        String("AWS4-HMAC-SHA256 Credential=") +
        AWS_ACCESS_KEY_ID + "/" + credentialScope +
        ", SignedHeaders=" + signedHeaders +
        ", Signature=" + signature;

    return { authorization, String(amzDate), String(datestamp) };
}

// ============================================================================
// Kinesis PutRecord
// ============================================================================

/**
 * Send one event to Kinesis.
 *
 * @param button   "A", "B", or "C"
 * @param message  Human-readable description
 * @return HTTP status code, or -1 on connection failure
 */
static int putKinesisRecord(const char* button, const char* message) {
    // ── Build payload JSON ────────────────────────────────────────────────────
    // M5.Power.getBatteryLevel() returns 0-100
    float battery = (float)M5.Power.getBatteryLevel();

    StaticJsonDocument<256> doc;
    doc["device_id"]   = DEVICE_ID;
    doc["event_type"]  = "button_press";
    doc["button"]      = button;
    doc["message"]     = message;
    doc["battery_pct"] = battery;

    String eventJson;
    serializeJson(doc, eventJson);

    // Kinesis Data field must be base64-encoded
    String encodedData = base64Encode(eventJson);

    // Kinesis PutRecord request body
    StaticJsonDocument<512> req;
    req["StreamName"]   = KINESIS_STREAM;
    req["Data"]         = encodedData;
    req["PartitionKey"] = DEVICE_ID;

    String body;
    serializeJson(req, body);

    // ── Sign the request ──────────────────────────────────────────────────────
    const char* target = "Kinesis_20131202.PutRecord";
    SigV4Result sig = buildAuthHeader(body, target);

    // ── Send HTTPS request ────────────────────────────────────────────────────
    WiFiClientSecure client;
    client.setInsecure();  // Skip cert verification — acceptable for IoT dev
                           // For production, set the AWS root CA with client.setCACert()

    HTTPClient http;
    String url = String("https://") + kinesisHost + "/";
    if (!http.begin(client, url)) {
        Serial.println("[Kinesis] http.begin() failed");
        return -1;
    }

    http.addHeader("Content-Type",   "application/x-amz-json-1.1");
    http.addHeader("X-Amz-Target",   target);
    http.addHeader("X-Amz-Date",     sig.amzDate);
    http.addHeader("Authorization",  sig.authorization);
    http.addHeader("Host",           kinesisHost);

    int code = http.POST(body);
    if (code > 0) {
        Serial.printf("[Kinesis] HTTP %d\n", code);
        if (code != 200) {
            Serial.println(http.getString());
        }
    } else {
        Serial.printf("[Kinesis] Error: %s\n", http.errorToString(code).c_str());
    }
    http.end();
    return code;
}

// ============================================================================
// Display helpers
// ============================================================================

static void drawStatus(const String& text, uint16_t color) {
    M5.Lcd.fillRect(0, 80, 320, 24, BLACK);
    M5.Lcd.setTextColor(color, BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(8, 84);
    M5.Lcd.print(text);
}

static void drawHeader() {
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(8, 8);
    M5.Lcd.printf("M5Stack -> Kinesis");
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 32);
    M5.Lcd.setTextColor(TFT_LIGHTGREY, BLACK);
    M5.Lcd.printf("Device: %s", DEVICE_ID);
    M5.Lcd.setCursor(8, 44);
    M5.Lcd.printf("Stream: %s", KINESIS_STREAM);

    // Draw button labels at the bottom of the screen
    M5.Lcd.fillRect(0, 200, 320, 40, TFT_DARKGREY);
    M5.Lcd.setTextColor(WHITE, TFT_DARKGREY);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(18,  210); M5.Lcd.print("BTN A");
    M5.Lcd.setCursor(128, 210); M5.Lcd.print("BTN B");
    M5.Lcd.setCursor(238, 210); M5.Lcd.print("BTN C");
}

static void drawEventCount() {
    M5.Lcd.fillRect(0, 110, 320, 20, BLACK);
    M5.Lcd.setTextColor(TFT_CYAN, BLACK);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 114);
    M5.Lcd.printf("Events sent: %u", eventCount);
}

static void drawBattery() {
    int level = M5.Power.getBatteryLevel();
    uint16_t col = (level < 20) ? RED : (level < 50 ? YELLOW : GREEN);
    M5.Lcd.fillRect(0, 130, 320, 16, BLACK);
    M5.Lcd.setTextColor(col, BLACK);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 132);
    M5.Lcd.printf("Battery: %d%%", level);
}

// ============================================================================
// WiFi connection
// ============================================================================

static void connectWiFi() {
    drawStatus("Connecting WiFi...", STATUS_INFO_COLOR);
    Serial.printf("[WiFi] Connecting to %s\n", WIFI_SSID);

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    uint8_t attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        wifiConnected = true;
        Serial.printf("\n[WiFi] Connected, IP: %s\n", WiFi.localIP().toString().c_str());
        drawStatus("WiFi OK  " + WiFi.localIP().toString(), STATUS_OK_COLOR);
    } else {
        wifiConnected = false;
        Serial.println("\n[WiFi] Connection failed");
        drawStatus("WiFi FAILED", STATUS_ERR_COLOR);
    }
}

// ============================================================================
// NTP time sync
// ============================================================================

static void syncTime() {
    drawStatus("Syncing time (NTP)...", STATUS_INFO_COLOR);
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");

    struct tm timeinfo;
    uint8_t attempts = 0;
    while (!getLocalTime(&timeinfo) && attempts < 20) {
        delay(500);
        attempts++;
    }

    if (attempts < 20) {
        char buf[32];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S UTC", &timeinfo);
        Serial.printf("[NTP] Time: %s\n", buf);
        drawStatus(String("Time: ") + buf, STATUS_OK_COLOR);
    } else {
        Serial.println("[NTP] Time sync failed — signatures will be wrong");
        drawStatus("NTP FAILED", STATUS_ERR_COLOR);
    }
    delay(800);
}

// ============================================================================
// Send event with UI feedback
// ============================================================================

static void sendEvent(const char* button, const char* message) {
    // Debounce: ignore repeated presses within 2 seconds
    if (millis() - lastSendMs < 2000) return;
    lastSendMs = millis();

    Serial.printf("[Send] Button %s — %s\n", button, message);
    drawStatus(String("Sending ") + button + "...", TFT_YELLOW);

    // Reconnect WiFi if dropped
    if (WiFi.status() != WL_CONNECTED) {
        connectWiFi();
        syncTime();
        if (!wifiConnected) {
            drawStatus("No WiFi — not sent", STATUS_ERR_COLOR);
            return;
        }
    }

    int code = putKinesisRecord(button, message);
    eventCount++;

    if (code == 200) {
        M5.Lcd.fillRect(0, 60, 320, 16, BLACK);
        M5.Lcd.setTextColor(GREEN, BLACK);
        M5.Lcd.setTextSize(1);
        M5.Lcd.setCursor(8, 62);
        M5.Lcd.printf("Sent at %lu ms", millis());
        drawStatus(String("OK [") + button + "] #" + eventCount, STATUS_OK_COLOR);
    } else {
        drawStatus(String("ERR ") + code + " [" + button + "]", STATUS_ERR_COLOR);
    }

    drawEventCount();
    drawBattery();
}

// ============================================================================
// Arduino entry points
// ============================================================================

void setup() {
    M5.begin();
    Serial.begin(115200);

    snprintf(kinesisHost, sizeof(kinesisHost), KINESIS_HOST_TEMPLATE, AWS_REGION);

    drawHeader();
    delay(300);

    connectWiFi();
    delay(500);
    syncTime();

    drawHeader();
    drawStatus("Ready — press a button", STATUS_OK_COLOR);
    drawBattery();
    Serial.println("[Setup] Ready");
}

void loop() {
    M5.update();

    // Refresh NTP every hour (drift correction)
    static uint32_t lastNtpSync = 0;
    if (millis() - lastNtpSync > 3600000UL) {
        lastNtpSync = millis();
        syncTime();
        drawHeader();
        drawStatus("Ready — press a button", STATUS_OK_COLOR);
        drawEventCount();
        drawBattery();
    }

    // Virtual touchscreen buttons (bottom strip of the M5Core2 screen)
    if (M5.BtnA.wasPressed()) sendEvent("A", "Button A pressed");
    if (M5.BtnB.wasPressed()) sendEvent("B", "Button B pressed");
    if (M5.BtnC.wasPressed()) sendEvent("C", "Button C pressed");

    delay(10);
}
