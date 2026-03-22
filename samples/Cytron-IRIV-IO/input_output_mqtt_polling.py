import os
import board
import busio
import digitalio
import time
import adafruit_connection_manager
from adafruit_wiznet5k.adafruit_wiznet5k import WIZNET5K
import adafruit_minimqtt.adafruit_minimqtt as MQTT
from adafruit_minimqtt.adafruit_minimqtt import MMQTTException
from digitalio import DigitalInOut

# ═════════════════════════════════════════════════════════════════
# Add these to your settings.toml file (all keys lowercase + underscores)

# mqtt_server     = "192.168.240.94"
# mqtt_username   = "client"
# mqtt_password   = "123456"
# topic_base      = "cytron-iriv"
# eth_use_dhcp    = false          # or true / "true" / "false" / "1" / "0"
# eth_ip          = "192.168.1.177"
# eth_subnet      = "255.255.255.0"
# eth_gateway     = "192.168.1.1"
# eth_dns         = "8.8.8.8"

# DO NOT commit settings.toml to version control!

# ═════════════════════════════════════════════════════════════════
# Read settings from settings.toml

def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    val = value.strip().lower()
    return val in ("true", "1", "yes", "on")

USE_DHCP = env_bool("eth_use_dhcp", False)

ip_str      = os.getenv("eth_ip",       "192.168.1.177")
subnet_str  = os.getenv("eth_subnet",   "255.255.255.0")
gateway_str = os.getenv("eth_gateway",  "192.168.1.1")
dns_str     = os.getenv("eth_dns",      "8.8.8.8")

def str_to_tuple(s):
    return tuple(int(x) for x in s.split("."))

IP_ADDRESS  = str_to_tuple(ip_str)
SUBNET_MASK = str_to_tuple(subnet_str)
GATEWAY     = str_to_tuple(gateway_str)
DNS_SERVER  = str_to_tuple(dns_str)

# ═════════════════════════════════════════════════════════════════
# Ethernet setup

cs = DigitalInOut(board.W5500_CS)
spi_bus = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)

eth = WIZNET5K(spi_bus, cs)

if USE_DHCP:
    print("Ethernet mode: DHCP")
else:
    print("Ethernet mode: Static")
    eth.ifconfig = (IP_ADDRESS, SUBNET_MASK, GATEWAY, DNS_SERVER)

ip = eth.pretty_ip(eth.ip_address)
print("IP Address:", ip)
if not ip or ip == "0.0.0.0":
    raise RuntimeError("Failed to obtain valid IP address. Check Ethernet connection.")

# ═════════════════════════════════════════════════════════════════
# GPIO setup

input0 = digitalio.DigitalInOut(board.GP0)
input0.direction = digitalio.Direction.INPUT
input0.pull = digitalio.Pull.UP

input1 = digitalio.DigitalInOut(board.GP1)
input1.direction = digitalio.Direction.INPUT
input1.pull = digitalio.Pull.UP

input2 = digitalio.DigitalInOut(board.GP2)
input2.direction = digitalio.Direction.INPUT
input2.pull = digitalio.Pull.UP

input3 = digitalio.DigitalInOut(board.GP3)
input3.direction = digitalio.Direction.INPUT
input3.pull = digitalio.Pull.UP

output0 = digitalio.DigitalInOut(board.GP12)
output0.direction = digitalio.Direction.OUTPUT

output1 = digitalio.DigitalInOut(board.GP13)
output1.direction = digitalio.Direction.OUTPUT

output2 = digitalio.DigitalInOut(board.GP14)
output2.direction = digitalio.Direction.OUTPUT

output3 = digitalio.DigitalInOut(board.GP15)
output3.direction = digitalio.Direction.OUTPUT

led = digitalio.DigitalInOut(board.GP29)
led.direction = digitalio.Direction.OUTPUT

# ═════════════════════════════════════════════════════════════════
# MQTT topics

topic_base = os.getenv("topic_base", "cytron-iriv")
mqtt_topic_input_base  = topic_base + "/i"
mqtt_topic_output_base = topic_base + "/o"

# ═════════════════════════════════════════════════════════════════
# MQTT configuration

MQTT_RECONNECT_BASE_DELAY = 5
MQTT_RECONNECT_MAX_DELAY  = 300    # 5 minutes max backoff
MQTT_KEEPALIVE            = 60

pool = adafruit_connection_manager.get_radio_socketpool(eth)
ssl_context = adafruit_connection_manager.get_radio_ssl_context(eth)

client = MQTT.MQTT(
    broker=os.getenv("mqtt_server"),
    username=os.getenv("mqtt_username"),
    password=os.getenv("mqtt_password"),
    is_ssl=False,
    socket_pool=pool,
    ssl_context=ssl_context,
    socket_timeout=0.1,
    keep_alive=MQTT_KEEPALIVE
)

# ═════════════════════════════════════════════════════════════════
# MQTT callbacks

def connect(client, userdata, flags, rc):
    print("Connected to MQTT Broker!")

def disconnect(client, userdata, rc):
    print("Disconnected from MQTT Broker!")

def subscribe(client, userdata, topic, granted_qos):
    print(f"Subscribed to {topic} with QOS {granted_qos}")

def unsubscribe(client, userdata, topic, pid):
    print(f"Unsubscribed from {topic} with PID {pid}")

def publish(client, userdata, topic, pid):
    print(f"Published to {topic} with PID {pid}")

def message(client, topic, message):
    print(f"Message on {topic}: {message}")
    msg = message.strip().lower()
    val = msg in ("true", "1", "on", "yes", "high")
    if topic == f"{mqtt_topic_output_base}/0":
        output0.value = val
    elif topic == f"{mqtt_topic_output_base}/1":
        output1.value = val
    elif topic == f"{mqtt_topic_output_base}/2":
        output2.value = val
    elif topic == f"{mqtt_topic_output_base}/3":
        output3.value = val
    elif topic == f"{mqtt_topic_output_base}/led":
        led.value = val

client.on_connect    = connect
client.on_disconnect = disconnect
client.on_subscribe  = subscribe
client.on_unsubscribe = unsubscribe
client.on_publish    = publish
client.on_message    = message

# ═════════════════════════════════════════════════════════════════
# Reconnect helper

def safe_mqtt_reconnect():
    if client.is_connected():
        try:
            client.disconnect()
        except:
            pass

    print("MQTT reconnect attempt...", end="")
    try:
        rc = client.reconnect()  # auto-resubscribes by default
        print(f" success (rc={rc})")
        client.publish(f"{mqtt_topic_input_base}/status", "reconnected")
        return True
    except Exception as e:
        print(f" failed: {e}")
        return False

# ═════════════════════════════════════════════════════════════════
# Initial connection - retry forever until success

print(f"Connecting to MQTT broker: {client.broker}")
delay = MQTT_RECONNECT_BASE_DELAY
while True:
    if safe_mqtt_reconnect():
        break
    print(f"Connect failed → retry in {delay} seconds")
    time.sleep(delay)
    delay = min(delay * 2, MQTT_RECONNECT_MAX_DELAY)

client.publish(f"{mqtt_topic_input_base}/status", "connected")

# ═════════════════════════════════════════════════════════════════
# Input state tracking

last_input0_state = input0.value
last_input1_state = input1.value
last_input2_state = input2.value
last_input3_state = input3.value

# Periodic status
last_status_time = time.monotonic()
STATUS_INTERVAL = 300  # 5 minutes

# ═════════════════════════════════════════════════════════════════
# Main loop - designed to never exit

while True:
    now = time.monotonic()

    # Process inputs unconditionally
    for pin, last_var_name, topic_suffix in [
        (input0, 'last_input0_state', "0"),
        (input1, 'last_input1_state', "1"),
        (input2, 'last_input2_state', "2"),
        (input3, 'last_input3_state', "3"),
    ]:
        current = pin.value
        last_state = locals()[last_var_name]
        if current != last_state:
            locals()[last_var_name] = current
            try:
                client.publish(f"{mqtt_topic_input_base}/{topic_suffix}", str(int(current)))
            except:
                pass  # will retry after reconnect

    # MQTT when connected
    if client.is_connected():
        try:
            client.loop(timeout=0.05)

            if now - last_status_time >= STATUS_INTERVAL:
                try:
                    client.publish(f"{mqtt_topic_input_base}/status", "alive")
                    last_status_time = now
                except:
                    pass

        except (MMQTTException, OSError, RuntimeError) as e:
            print(f"MQTT loop error: {e}")
            try:
                client.disconnect()
            except:
                pass

    # Reconnect if disconnected - loops until success
    if not client.is_connected():
        print("MQTT disconnected → reconnecting...")
        delay = MQTT_RECONNECT_BASE_DELAY
        attempt = 0
        while not client.is_connected():
            attempt += 1
            if safe_mqtt_reconnect():
                break
            sleep_time = min(delay * (2 ** (attempt - 1)), MQTT_RECONNECT_MAX_DELAY)
            print(f"Attempt {attempt} failed → wait {sleep_time:.0f}s")
            time.sleep(sleep_time)

            # Optional Ethernet refresh after many failures
            if attempt % 10 == 0 and attempt > 0:
                print("Long failure → refreshing Ethernet")
                try:
                    eth.pretty_ip(eth.ip_address)
                except:
                    pass

    time.sleep(0.02)  # prevent tight loop
