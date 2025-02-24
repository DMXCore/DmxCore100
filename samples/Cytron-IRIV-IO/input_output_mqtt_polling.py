import os
import board
import busio
import digitalio
import time
import adafruit_connection_manager
from adafruit_wiznet5k.adafruit_wiznet5k import WIZNET5K
import adafruit_minimqtt.adafruit_minimqtt as MQTT
from digitalio import DigitalInOut

# Add settings.toml to your filesystem. Add your MQTT broker, username and key as well.
# DO NOT share that file or commit it into Git or other source control.

cs = DigitalInOut(board.W5500_CS)
spi_bus = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)

# Initialize ethernet interface
eth = WIZNET5K(spi_bus, cs)

# Verify Ethernet connection
ip = eth.pretty_ip(eth.ip_address)
print("IP Address:", ip)
if not ip:
    raise RuntimeError("Failed to get an IP address. Check Ethernet connection.")

# Set up the inputs on GP0 and GP1
input0 = digitalio.DigitalInOut(board.GP0)
input0.direction = digitalio.Direction.INPUT
input0.pull = digitalio.Pull.UP  # Enable internal pull-up resistor

input1 = digitalio.DigitalInOut(board.GP1)
input1.direction = digitalio.Direction.INPUT
input1.pull = digitalio.Pull.UP  # Enable internal pull-up resistor

# Set up the outputs on GP12 and GP13
output0 = digitalio.DigitalInOut(board.GP12)
output0.direction = digitalio.Direction.OUTPUT

output1 = digitalio.DigitalInOut(board.GP13)
output1.direction = digitalio.Direction.OUTPUT

### Topic Setup ###
mqtt_topic_input_base = "test/input"
mqtt_topic_output_base = "test/output"

### Code ###

# Define callback methods which are called when events occur
def connect(client, userdata, flags, rc):
    print("Connected to MQTT Broker!")

def disconnect(client, userdata, rc):
    print("Disconnected from MQTT Broker!")

def subscribe(client, userdata, topic, granted_qos):
    print(f"Subscribed to {topic} with QOS level {granted_qos}")

def unsubscribe(client, userdata, topic, pid):
    print(f"Unsubscribed from {topic} with PID {pid}")

def publish(client, userdata, topic, pid):
    print(f"Published to {topic} with PID {pid}")

def message(client, topic, message):
    print(f"New message on topic {topic}: {message}")
    if topic == f"{mqtt_topic_output_base}/output0":
        output0.value = message == "True"
    elif topic == f"{mqtt_topic_output_base}/output1":
        output1.value = message == "True"

pool = adafruit_connection_manager.get_radio_socketpool(eth)
ssl_context = adafruit_connection_manager.get_radio_ssl_context(eth)

# Set up a MiniMQTT Client
client = MQTT.MQTT(
    broker=os.getenv("mqtt_server"),
    username=os.getenv("mqtt_username"),
    password=os.getenv("mqtt_password"),
    is_ssl=False,
    socket_pool=pool,
    ssl_context=ssl_context,
    socket_timeout=0.05
)

# Connect callback handlers to client
client.on_connect = connect
client.on_disconnect = disconnect
client.on_subscribe = subscribe
client.on_unsubscribe = unsubscribe
client.on_publish = publish
client.on_message = message

print("Attempting to connect to %s" % client.broker)
client.connect()

print("Subscribing to output topics")
client.subscribe(f"{mqtt_topic_output_base}/output0")
client.subscribe(f"{mqtt_topic_output_base}/output1")

# Variables to track the last state of the inputs
last_input0_state = input0.value
last_input1_state = input1.value

# Main loop to maintain connection and check for messages
while True:
    try:
        # Check input0 state
        current_input0_state = input0.value
        if current_input0_state != last_input0_state:
            client.publish(f"{mqtt_topic_input_base}/input0", str(current_input0_state))
            last_input0_state = current_input0_state

        # Check input1 state
        current_input1_state = input1.value
        if current_input1_state != last_input1_state:
            client.publish(f"{mqtt_topic_input_base}/input1", str(current_input1_state))
            last_input1_state = current_input1_state

        # Maintain MQTT connection and handle messages
        client.loop(0.05)
    except Exception as e:
        print(f"Error in main loop: {e}")
        time.sleep(5)

