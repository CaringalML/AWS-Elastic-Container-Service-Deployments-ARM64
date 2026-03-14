/**
 * M5Stack Core 2 — AWS Kinesis Data Stream Publisher
 *
 * Required libraries (Arduino Library Manager):
 *   - M5Unified  (by M5Stack)
 *   - ArduinoJson (by Benoit Blanchon) >= 6.x
 */

#include <M5Unified.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "mbedtls/md.h"

// ============================================================================
// CONFIG — fill these in before flashing
// ============================================================================

const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

const char* AWS_ACCESS_KEY_ID     = "YOUR_ACCESS_KEY_ID";
const char* AWS_SECRET_ACCESS_KEY = "YOUR_SECRET_ACCESS_KEY";

const char* AWS_REGION     = "ap-southeast-2";
const char* KINESIS_STREAM = "caringal-web-app-iot-events";

const char* DEVICE_ID = "m5stack-core2-001";

// ============================================================================
// Constants & Globals
// ============================================================================

#define SHA256_DIGEST_SIZE 32

char kinesisHost[64];
bool wifiConnected = false;
uint32_t lastSendMs = 0;
uint16_t eventCount = 0;

// ============================================================================
// Crypto helpers
// ============================================================================

void sha256Raw(const uint8_t* input, size_t len, uint8_t* output) {
    mbedtls_md_context_t ctx;
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, 0);
    mbedtls_md_starts(&ctx);
    mbedtls_md_update(&ctx, input, len);
    mbedtls_md_finish(&ctx, output);
    mbedtls_md_free(&ctx);
}

void hmacSha256Raw(const uint8_t* key, size_t keyLen,
                   const uint8_t* data, size_t dataLen,
                   uint8_t* output) {
    mbedtls_md_context_t ctx;
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, 1);
    mbedtls_md_hmac_starts(&ctx, key, keyLen);
    mbedtls_md_hmac_update(&ctx, data, dataLen);
    mbedtls_md_hmac_finish(&ctx, output);
    mbedtls_md_free(&ctx);
}

String toHex(const uint8_t* data, size_t len) {
    String result;
    result.reserve(len * 2);
    for (size_t i = 0; i < len; i++) {
        char buf[3];
        snprintf(buf, sizeof(buf), "%02x", data[i]);
        result += buf;
    }
    return result;
}

String sha256Hex(const String& s) {
    uint8_t hash[SHA256_DIGEST_SIZE];
    sha256Raw((const uint8_t*)s.c_str(), s.length(), hash);
    return toHex(hash, SHA256_DIGEST_SIZE);
}

void deriveSigningKey(const char* secretKey, const char* datestamp,
                      const char* region, const char* service,
                      uint8_t* signingKey) {
    String kSecret = String("AWS4") + secretKey;
    uint8_t kDate[SHA256_DIGEST_SIZE];
    hmacSha256Raw((const uint8_t*)kSecret.c_str(), kSecret.length(),
                  (const uint8_t*)datestamp, strlen(datestamp), kDate);

    uint8_t kRegion[SHA256_DIGEST_SIZE];
    hmacSha256Raw(kDate, SHA256_DIGEST_SIZE,
                  (const uint8_t*)region, strlen(region), kRegion);

    uint8_t kService[SHA256_DIGEST_SIZE];
    hmacSha256Raw(kRegion, SHA256_DIGEST_SIZE,
                  (const uint8_t*)service, strlen(service), kService);

    const char* terminator = "aws4_request";
    hmacSha256Raw(kService, SHA256_DIGEST_SIZE,
                  (const uint8_t*)terminator, strlen(terminator), signingKey);
}

// ============================================================================
// Base64 encoder
// ============================================================================

const char B64_CHARS[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

String base64Encode(const String& input) {
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
        result += (i + 2 < len) ? B64_CHARS[b2 & 0x3F] : '=';
    }
    return result;
}

// ============================================================================
// AWS SigV4
// ============================================================================

// outAuth and outAmzDate are filled by this function
void buildAuthHeader(const String& payload, const char* target,
                     String& outAuth, String& outAmzDate) {
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        Serial.println("[SigV4] Time not synced");
    }

    char datestamp[9];
    char amzDate[17];
    strftime(datestamp, sizeof(datestamp), "%Y%m%d",         &timeinfo);
    strftime(amzDate,   sizeof(amzDate),   "%Y%m%dT%H%M%SZ", &timeinfo);

    String payloadHash = sha256Hex(payload);

    String canonicalHeaders =
        String("content-type:application/x-amz-json-1.1\n") +
        "host:" + kinesisHost + "\n" +
        "x-amz-date:" + amzDate + "\n" +
        "x-amz-target:" + target + "\n";

    String signedHeaders = "content-type;host;x-amz-date;x-amz-target";

    String canonicalRequest =
        String("POST\n/\n\n") +
        canonicalHeaders + "\n" +
        signedHeaders + "\n" +
        payloadHash;

    String credentialScope = String(datestamp) + "/" + AWS_REGION + "/kinesis/aws4_request";

    String stringToSign =
        String("AWS4-HMAC-SHA256\n") +
        amzDate + "\n" +
        credentialScope + "\n" +
        sha256Hex(canonicalRequest);

    uint8_t signingKey[SHA256_DIGEST_SIZE];
    deriveSigningKey(AWS_SECRET_ACCESS_KEY, datestamp, AWS_REGION, "kinesis", signingKey);

    uint8_t sigBytes[SHA256_DIGEST_SIZE];
    hmacSha256Raw(signingKey, SHA256_DIGEST_SIZE,
                  (const uint8_t*)stringToSign.c_str(), stringToSign.length(), sigBytes);

    outAuth =
        String("AWS4-HMAC-SHA256 Credential=") +
        AWS_ACCESS_KEY_ID + "/" + credentialScope +
        ", SignedHeaders=" + signedHeaders +
        ", Signature=" + toHex(sigBytes, SHA256_DIGEST_SIZE);

    outAmzDate = String(amzDate);
}

// ============================================================================
// Kinesis PutRecord
// ============================================================================

int putKinesisRecord(const char* button, const char* message) {
    int battery = M5.Power.getBatteryLevel();

    JsonDocument doc;
    doc["device_id"]   = DEVICE_ID;
    doc["event_type"]  = "button_press";
    doc["button"]      = button;
    doc["message"]     = message;
    doc["battery_pct"] = battery;

    String eventJson;
    serializeJson(doc, eventJson);

    JsonDocument req;
    req["StreamName"]   = KINESIS_STREAM;
    req["Data"]         = base64Encode(eventJson);
    req["PartitionKey"] = DEVICE_ID;

    String body;
    serializeJson(req, body);

    const char* target = "Kinesis_20131202.PutRecord";
    String sigAuth, sigDate;
    buildAuthHeader(body, target, sigAuth, sigDate);

    WiFiClientSecure client;
    client.setInsecure();

    HTTPClient http;
    String url = String("https://") + kinesisHost + "/";
    if (!http.begin(client, url)) {
        Serial.println("[Kinesis] http.begin() failed");
        return -1;
    }

    http.addHeader("Content-Type",  "application/x-amz-json-1.1");
    http.addHeader("X-Amz-Target",  target);
    http.addHeader("X-Amz-Date",    sigDate);
    http.addHeader("Authorization", sigAuth);
    http.addHeader("Host",          kinesisHost);

    int code = http.POST(body);
    if (code > 0) {
        Serial.printf("[Kinesis] HTTP %d\n", code);
        if (code != 200) Serial.println(http.getString());
    } else {
        Serial.printf("[Kinesis] Error: %s\n", http.errorToString(code).c_str());
    }
    http.end();
    return code;
}

// ============================================================================
// Display helpers
// ============================================================================

void drawStatus(const String& text, uint32_t color) {
    M5.Lcd.fillRect(0, 80, 320, 24, TFT_BLACK);
    M5.Lcd.setTextColor(color, TFT_BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(8, 84);
    M5.Lcd.print(text);
}

void drawHeader() {
    M5.Lcd.fillScreen(TFT_BLACK);
    M5.Lcd.setTextColor(TFT_WHITE, TFT_BLACK);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(8, 8);
    M5.Lcd.print("M5Stack -> Kinesis");
    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(TFT_LIGHTGREY, TFT_BLACK);
    M5.Lcd.setCursor(8, 32);
    M5.Lcd.printf("Device: %s", DEVICE_ID);
    M5.Lcd.setCursor(8, 44);
    M5.Lcd.printf("Stream: %s", KINESIS_STREAM);

    M5.Lcd.fillRect(0, 200, 320, 40, TFT_DARKGREY);
    M5.Lcd.setTextColor(TFT_WHITE, TFT_DARKGREY);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(18,  210); M5.Lcd.print("BTN A");
    M5.Lcd.setCursor(128, 210); M5.Lcd.print("BTN B");
    M5.Lcd.setCursor(238, 210); M5.Lcd.print("BTN C");
}

void drawEventCount() {
    M5.Lcd.fillRect(0, 110, 320, 20, TFT_BLACK);
    M5.Lcd.setTextColor(TFT_CYAN, TFT_BLACK);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 114);
    M5.Lcd.printf("Events sent: %u", eventCount);
}

void drawBattery() {
    int level = M5.Power.getBatteryLevel();
    uint32_t col = (level < 20) ? TFT_RED : (level < 50 ? TFT_YELLOW : TFT_GREEN);
    M5.Lcd.fillRect(0, 130, 320, 16, TFT_BLACK);
    M5.Lcd.setTextColor(col, TFT_BLACK);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setCursor(8, 132);
    M5.Lcd.printf("Battery: %d%%", level);
}

// ============================================================================
// WiFi + NTP
// ============================================================================

void connectWiFi() {
    drawStatus("Connecting WiFi...", TFT_WHITE);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    uint8_t attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        wifiConnected = true;
        Serial.printf("\n[WiFi] Connected: %s\n", WiFi.localIP().toString().c_str());
        drawStatus("WiFi OK " + WiFi.localIP().toString(), TFT_GREEN);
    } else {
        wifiConnected = false;
        drawStatus("WiFi FAILED", TFT_RED);
    }
}

void syncTime() {
    drawStatus("Syncing time...", TFT_WHITE);
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    struct tm timeinfo;
    uint8_t attempts = 0;
    while (!getLocalTime(&timeinfo) && attempts < 20) {
        delay(500);
        attempts++;
    }
    if (attempts < 20) {
        char buf[32];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M UTC", &timeinfo);
        Serial.printf("[NTP] %s\n", buf);
        drawStatus(buf, TFT_GREEN);
    } else {
        drawStatus("NTP FAILED", TFT_RED);
    }
    delay(800);
}

// ============================================================================
// Send event
// ============================================================================

void sendEvent(const char* button, const char* message) {
    if (millis() - lastSendMs < 2000) return;
    lastSendMs = millis();

    Serial.printf("[Send] Button %s\n", button);
    drawStatus(String("Sending ") + button + "...", TFT_YELLOW);

    if (WiFi.status() != WL_CONNECTED) {
        connectWiFi();
        syncTime();
        if (!wifiConnected) { drawStatus("No WiFi", TFT_RED); return; }
    }

    int code = putKinesisRecord(button, message);
    eventCount++;

    if (code == 200) {
        drawStatus(String("OK [") + button + "] #" + eventCount, TFT_GREEN);
    } else {
        drawStatus(String("ERR ") + code + " [" + button + "]", TFT_RED);
    }
    drawEventCount();
    drawBattery();
}

// ============================================================================
// Arduino entry points
// ============================================================================

void setup() {
    auto cfg = M5.config();
    M5.begin(cfg);
    Serial.begin(115200);

    snprintf(kinesisHost, sizeof(kinesisHost), "kinesis.%s.amazonaws.com", AWS_REGION);

    drawHeader();
    delay(300);
    connectWiFi();
    delay(300);
    syncTime();

    drawHeader();
    drawStatus("Ready - press a button", TFT_GREEN);
    drawBattery();
}

void loop() {
    M5.update();

    static uint32_t lastNtpSync = 0;
    if (millis() - lastNtpSync > 3600000UL) {
        lastNtpSync = millis();
        syncTime();
        drawHeader();
        drawStatus("Ready - press a button", TFT_GREEN);
        drawEventCount();
        drawBattery();
    }

    if (M5.BtnA.wasPressed()) sendEvent("A", "Button A pressed");
    if (M5.BtnB.wasPressed()) sendEvent("B", "Button B pressed");
    if (M5.BtnC.wasPressed()) sendEvent("C", "Button C pressed");

    delay(10);
}
