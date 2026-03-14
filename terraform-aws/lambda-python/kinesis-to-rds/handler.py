"""
Kinesis → RDS PostgreSQL consumer.

Triggered by the Kinesis event source mapping on the IoT stream.
Decodes each Kinesis record, validates the JSON payload, and inserts
a row into the `iot_events` table.

Expected record payload (JSON):
{
    "device_id":   "m5stack-core2-001",
    "event_type":  "button_press",
    "button":      "A",              # optional
    "message":     "Button A pressed",
    "battery_pct": 87.5,             # optional, float
    "metadata":    {}                # optional, any JSON object
}

The DB connection is reused across warm invocations (module-level singleton).
If the connection is broken (e.g. RDS failover) it is transparently re-created.
"""

import base64
import json
import logging
import os

import boto3
import pg8000.native

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Module-level singletons — survive across warm Lambda invocations
_secrets_client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION_NAME", "ap-southeast-2"))
_conn = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_db_credentials() -> dict:
    secret_arn = os.environ["DB_SECRET_ARN"]
    response = _secrets_client.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])


def _connect() -> pg8000.native.Connection:
    creds = _get_db_credentials()
    return pg8000.native.Connection(
        host=creds["host"],
        port=int(creds["port"]),
        database=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        ssl_context=True,  # RDS requires SSL
        timeout=10,
    )


def _get_conn() -> pg8000.native.Connection:
    """Return a live DB connection, reconnecting if necessary."""
    global _conn
    if _conn is None:
        _conn = _connect()
        logger.info("Opened new database connection")
    return _conn


def _insert_event(conn: pg8000.native.Connection, data: dict) -> None:
    conn.run(
        """
        INSERT INTO iot_events (device_id, event_type, button, message, battery_pct, metadata)
        VALUES (:device_id, :event_type, :button, :message, :battery_pct, :metadata::jsonb)
        """,
        device_id=str(data.get("device_id", "unknown"))[:64],
        event_type=str(data.get("event_type", "unknown"))[:64],
        button=str(data["button"])[:32] if data.get("button") else None,
        message=str(data["message"]) if data.get("message") else None,
        battery_pct=float(data["battery_pct"]) if data.get("battery_pct") is not None else None,
        metadata=json.dumps(data.get("metadata") or {}),
    )


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------

def lambda_handler(event, context):
    records = event.get("Records", [])
    logger.info("Processing %d Kinesis record(s)", len(records))

    inserted = 0
    errors = 0

    for record in records:
        # Decode base64-encoded Kinesis data
        try:
            raw = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
            data = json.loads(raw)
        except Exception as exc:
            logger.error("Failed to decode record: %s — raw: %s", exc, record["kinesis"].get("data", ""))
            errors += 1
            continue

        # Insert with reconnect-on-failure
        for attempt in range(2):
            try:
                conn = _get_conn()
                _insert_event(conn, data)
                inserted += 1
                break
            except pg8000.native.DatabaseError as exc:
                logger.error("DB error on attempt %d: %s", attempt + 1, exc)
                global _conn
                _conn = None  # force reconnect next attempt
                if attempt == 1:
                    errors += 1
            except Exception as exc:
                logger.error("Unexpected error inserting record: %s", exc)
                errors += 1
                break

    logger.info("Done — inserted: %d, errors: %d", inserted, errors)

    if errors > 0:
        # Raise to let Lambda/Kinesis ESM retry the batch
        raise RuntimeError(f"{errors} record(s) failed to insert — retrying batch")

    return {"inserted": inserted}
