"""
Serial → MQTT bridge for the car telemetry platform.

Reads telemetry lines coming off the USB serial port (the LoRa receiver),
optionally stamps each one with the time it arrived, and republishes it to the
Mosquitto MQTT broker so Node-RED can pick it up.

    USB serial port  →  this script  →  Mosquitto (topic: car_telemetry)  →  Node-RED

Everything is configurable with environment variables, so you never have to edit
this file. For example:

    SERIAL_PORT=/dev/cu.usbserial-0001 python3 bridge.py

"""

import os
import sys
import time
import signal
import logging
from datetime import datetime, timezone

import serial                          # pyserial — talks to the USB serial port
import paho.mqtt.client as mqtt        # paho-mqtt — talks to Mosquitto


# ─────────────────────────────────────────────────────────────────────────────
# Configuration (override any of these with environment variables before running)
# ─────────────────────────────────────────────────────────────────────────────
SERIAL_PORT       = os.getenv("SERIAL_PORT", "/dev/tty.usbserial-0001")
BAUD_RATE         = int(os.getenv("BAUD_RATE", "38400"))
MQTT_HOST         = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT         = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC        = os.getenv("MQTT_TOPIC", "car_telemetry")
MQTT_QOS          = int(os.getenv("MQTT_QOS", "2"))          # matches the Node-RED subscriber
RECONNECT_DELAY   = float(os.getenv("RECONNECT_DELAY", "3")) # seconds between retries
SERIAL_TIMEOUT    = float(os.getenv("SERIAL_TIMEOUT", "2"))  # seconds for a blocking read

# Prepend an ISO-8601 timestamp as the first field of every line.
# The Node-RED "Strip Timestamp" node expects each frame to start with one.
# Set PREPEND_TIMESTAMP=false if the sender already includes its own timestamp.
PREPEND_TIMESTAMP = os.getenv("PREPEND_TIMESTAMP", "true").lower() in ("1", "true", "yes", "on")


# ─────────────────────────────────────────────────────────────────────────────
# Logging — timestamped console output instead of bare print()
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("bridge")


# ─────────────────────────────────────────────────────────────────────────────
# MQTT setup
# ─────────────────────────────────────────────────────────────────────────────
def build_mqtt_client():
    """Create an MQTT client that works on both paho-mqtt 2.x and 1.x."""
    if hasattr(mqtt, "CallbackAPIVersion"):
        # paho-mqtt 2.x requires you to pick a callback API version.
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="serial-bridge")
    # paho-mqtt 1.x — the old constructor.
    return mqtt.Client(client_id="serial-bridge")


# Callbacks use *args so the same function works across paho versions,
# whose callback signatures differ slightly.
def on_connect(client, userdata, *args):
    log.info("Connected to MQTT broker at %s:%s", MQTT_HOST, MQTT_PORT)


def on_disconnect(client, userdata, *args):
    log.warning("Lost connection to MQTT broker — will keep retrying in the background.")


def connect_mqtt():
    """Connect to Mosquitto, retrying until it's reachable. Returns a live client."""
    client = build_mqtt_client()
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    # Tell paho to automatically reconnect with a backoff if the link drops.
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    while True:
        try:
            client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
            break
        except Exception as exc:  # broker not up yet, DNS, refused, etc.
            log.warning("Can't reach MQTT broker (%s). Retrying in %.0fs…", exc, RECONNECT_DELAY)
            time.sleep(RECONNECT_DELAY)

    # loop_start() runs the network loop on a background thread and handles
    # reconnects for us, so the main loop below can focus on the serial port.
    client.loop_start()
    return client


# ─────────────────────────────────────────────────────────────────────────────
# Serial setup
# ─────────────────────────────────────────────────────────────────────────────
def open_serial():
    """Open the serial port, retrying until the device is present."""
    while True:
        try:
            ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=SERIAL_TIMEOUT)
            log.info("Listening on %s @ %d baud", SERIAL_PORT, BAUD_RATE)
            return ser
        except serial.SerialException as exc:
            log.warning("Can't open serial port %s (%s). Retrying in %.0fs…",
                        SERIAL_PORT, exc, RECONNECT_DELAY)
            time.sleep(RECONNECT_DELAY)


# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────
running = True


def shutdown(signum, frame):
    """Stop cleanly on Ctrl+C / kill."""
    global running
    running = False
    log.info("Shutting down…")


def main():
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    client = connect_mqtt()
    ser = open_serial()

    while running:
        try:
            raw = ser.readline()                       # waits up to SERIAL_TIMEOUT
        except serial.SerialException as exc:
            # The device was probably unplugged. Re-open and keep going.
            log.warning("Serial read failed (%s). Reconnecting…", exc)
            try:
                ser.close()
            except Exception:
                pass
            ser = open_serial()
            continue

        line = raw.decode("utf-8", errors="replace").strip()
        if not line:
            continue                                   # ignore blank/keep-alive lines

        # Stamp the frame with its arrival time so Node-RED's Strip Timestamp
        # node receives the leading timestamp field it expects.
        if PREPEND_TIMESTAMP:
            line = datetime.now(timezone.utc).isoformat() + "," + line

        result = client.publish(MQTT_TOPIC, line, qos=MQTT_QOS)
        if result.rc != mqtt.MQTT_ERR_SUCCESS:
            # Couldn't hand it to the broker right now (e.g. mid-reconnect).
            log.warning("Publish failed (rc=%s); frame not sent.", result.rc)
        else:
            log.info("→ %s", line)

    # Clean shutdown
    try:
        ser.close()
    except Exception:
        pass
    client.loop_stop()
    client.disconnect()
    log.info("Bye.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log.error("Fatal error: %s", exc)
        sys.exit(1)