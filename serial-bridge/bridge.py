# serial talks to the USB port, mqtt talks to Mosquitto, os lets us read environment variables so the port name isn't hardcoded
import serial
import paho.mqtt.client as mqtt
import os

# Config — override any of these with environment variables before running:
# e.g. SERIAL_PORT=/dev/tty.SLAB_USBtoUART python3 bridge.py
SERIAL_PORT = os.getenv("SERIAL_PORT", "/dev/tty.usbserial-0001")
BAUD_RATE   = int(os.getenv("BAUD_RATE", "38400"))
MQTT_HOST   = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT   = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC  = "car_telemetry"

# Connect to Mosquitto broker running in Docker
client = mqtt.Client()
client.connect(MQTT_HOST, MQTT_PORT)
client.loop_start()

# Open the serial port where the ESP32 receiver is plugged in
ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
print(f"Listening on {SERIAL_PORT} @ {BAUD_RATE} baud")

# Read lines forever and forward each one to MQTT
while True:
    line = ser.readline().decode("utf-8", errors="replace").strip()
    if line:
        print(f"→ {line}")
        client.publish(MQTT_TOPIC, line)