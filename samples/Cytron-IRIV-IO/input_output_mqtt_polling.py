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

# ════════════════════════════════════════════════════════════════════════
# settings.toml reference – use these exact lowercase keys

# mqtt_server     = "192.168.123.200"
# mqtt_username   = "client"
# mqtt_password   = "123456"
# topic_base      = "dmxcore100"
# eth_use_dhcp    = false
# eth_ip          = "192.168.123.202"
# eth_subnet      = "255.255.255.0"
# eth_gateway     = "192.168.123.1"
# eth_dns         = "8.8.8.8"

# ════════════════════════════════════════════════════════════════════════
# Helpers

def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ("true", "1", "yes", "on", "t", "y")


def str_to_tuple(s, default=(0, 0, 0, 0)):
    if s is None:
        print(f"Warning: IP setting missing → using default {default}")
        return default
    s = s.strip()
    if not s:
        print(f"Warning: Empty IP string → using default {default}")
        return default
    try:
        parts = [int(x.strip()) for x in s.split(".") if x.strip()]
        if len(parts) != 4 or not all(0 <= p <= 255 for p in parts):
            raise ValueError(f"Invalid IP format: '{s}'")
        return tuple(parts)
    except Exception as e:
        print(f"Warning: Cannot parse IP '{s}' → {e} → using default {default}")
        return default


# ════════════════════════════════════════════════════════════════════════
# Read settings

USE_DHCP = env_bool("eth_use_dhcp", False)

ip_str      = (os.getenv("eth_ip")      or "192.168.123.202").strip()
subnet_str  = (os.getenv("eth_subnet")  or "255.255.255.0").strip()
gateway_str = (os.getenv("eth_gateway") or "192.168.123.1").strip()
dns_str     = (os.getenv("eth_dns")     or "8.8.8.8").strip()

IP_ADDRESS  = str_to_tuple(ip_str)
SUBNET_MASK = str_to_tuple(subnet_str)
GATEWAY     = str_to_tuple(gateway_str)
DNS_SERVER  = str_to_tuple(dns_str)

# ════════════════════════════════════════════════════════════════════════
# Ethernet

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

# ════════════════════════════════════════════════════════════════════════
# GPIO

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

# ════════════════════════════════════════════════════════════════════════
# MQTT topics

topic_base = os.getenv("topic_base", "dmxcore100")
mqtt_topic_input_base  = topic_base + "/i"
mqtt_topic_output_base = topic_base + "/o"

# ════════════════════════════════════════════════════════════════════════
# MQTT config

MQTT_RECONNECT_BASE_DELAY = 5
MQTT_RECONNECT_MAX_DELAY  = 300
MQTT_KEEPALIVE            = 60
LOOP_TIMEOUT              = 0.2
SOCKET_TIMEOUT            = 0.2

pool = adafruit_connection_manager.get_radio_socketpool(eth)
ssl_context = adafruit_connection_manager.get_radio_ssl_context(eth)

client = MQTT.MQTT(
    broker=os.getenv("mqtt_server"),
    username=os.getenv("mqtt_username"),
    password=os.getenv("mqtt_password"),
    is_ssl=False,
    socket_pool=pool,
    ssl_context=ssl_context,
    socket_timeout=SOCKET_TIMEOUT,
    keep_alive=MQTT_KEEPALIVE
)

# ════════════════════════════════════════════════════════════════════════
# Callbacks

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
    msg = str(message).strip().lower()
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

# ════════════════════════════════════════════════════════════════════════
# Reconnect helper

def safe_mqtt_reconnect():
    if client.is_connected():
        try:
            client.disconnect()
        except:
            pass
    print("MQTT reconnect attempt...", end="")
    try:
        rc = client.reconnect()  # auto-resubscribes
        print(f" success (rc={rc})")
        client.publish(f"{mqtt_topic_input_base}/status", "reconnected")
        return True
    except Exception as e:
        print(f" failed: {e}")
        return False

# ════════════════════════════════════════════════════════════════════════
# Initial connect

print(f"Connecting to MQTT broker: {client.broker}")
delay = MQTT_RECONNECT_BASE_DELAY
while True:
    if safe_mqtt_reconnect():
        break
    print(f"Connect failed → retry in {delay} seconds")
    time.sleep(delay)
    delay = min(delay * 2, MQTT_RECONNECT_MAX_DELAY)

client.publish(f"{mqtt_topic_input_base}/status", "connected")

# ════════════════════════════════════════════════════════════════════════
# Input state tracking

last_input0_state = input0.value
last_input1_state = input1.value
last_input2_state = input2.value
last_input3_state = input3.value

# Periodic status
last_status_time = time.monotonic()
STATUS_INTERVAL = 300  # 5 minutes

# ════════════════════════════════════════════════════════════════════════
# Main loop

while True:
    now = time.monotonic()

    # Process inputs – single place, no duplication
    for pin, last_var_name, suffix in [
        (input0, 'last_input0_state', "0"),
        (input1, 'last_input1_state', "1"),
        (input2, 'last_input2_state', "2"),
        (input3, 'last_input3_state', "3"),
    ]:
        current = pin.value
        last = locals()[last_var_name]
        if current != last:
            locals()[last_var_name] = current
            # With Pull.UP: pressed = low (False) → publish 1 when pressed
            payload = str(int(current))
            try:
                client.publish(f"{mqtt_topic_input_base}/{suffix}", payload)
                print(f"Published {mqtt_topic_input_base}/{suffix} → {payload}")
            except Exception:
                pass  # retry after reconnect

    # MQTT maintenance
    if client.is_connected():
        try:
            client.loop(timeout=LOOP_TIMEOUT)

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

    # Reconnect if needed
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
            if attempt % 10 == 0 and attempt > 0:
                print("Long failure → refreshing Ethernet")
                try:
                    eth.pretty_ip(eth.ip_address)
                except:
                    pass

    time.sleep(0.02)  # avoid busy loop
