#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Initialize variables
COMPUTE_MODULE="Unknown"
BASE_BOARD="v1"

# Determine Compute Module type
if [ -f /proc/device-tree/model ] && cat /proc/device-tree/model | grep -q "Compute Module 5"; then
  echo "Compute Module 5 detected"
  COMPUTE_MODULE="CM5"
elif [ -f /proc/device-tree/model ] && cat /proc/device-tree/model | grep -q "Compute Module 4"; then
  echo "Compute Module 4 detected"
  COMPUTE_MODULE="CM4"
else
  echo "Unknown module"
  exit 1
fi

# Check if I2C bus 0 exists
FOUND_MCP23008=false
if [ ! -d "/sys/bus/i2c/devices/i2c-0" ]; then
  echo ""
  echo "*WARNING*: Unable to detect correct I2C buses, most likely this installation is missing the 'dtoverlay=dmxcore100' setting which will load the overlay for the necessary I2C bus configuration. You should run this script again after reboot."
  echo ""
  BASE_BOARD="v1"
else
  # Step 1: Check for loaded MCP23008 driver in /sys/bus/i2c/devices
  for bus in /dev/i2c-*; do
    # Extract bus number from /dev/i2c-<number>
    bus_number=$(basename "$bus" | sed 's/i2c-//')
    DEVICE_PATH="/sys/bus/i2c/devices/$bus_number-0020/name"
    if [ -f "$DEVICE_PATH" ]; then
      DEVICE_NAME=$(cat "$DEVICE_PATH" 2>/dev/null)
      if [ $? -eq 0 ] && [ "$DEVICE_NAME" = "mcp23008" ]; then
        echo "MCP23008 driver detected on bus $bus_number at address 0x20 - Hardware v2 confirmed"
        BASE_BOARD="v2"
        FOUND_MCP23008=true
        break
      fi
    fi
  done

  # Step 2: If no driver found, fall back to i2ctransfer
  if [ "$FOUND_MCP23008" = false ]; then
    echo "No MCP23008 driver found, attempting i2ctransfer probe..."
    for bus in /dev/i2c-*; do
      # Extract bus number from /dev/i2c-<number>
      bus_number=$(basename "$bus" | sed 's/i2c-//')
      # Attempt to read 1 byte from IODIR register (0x00) at address 0x20
      if i2ctransfer -y "$bus_number" w1@0x20 0x00 r1 >/dev/null 2>&1; then
        echo "MCP23008 detected on bus $bus_number at address 0x20 via i2ctransfer - Hardware v2 confirmed"
        BASE_BOARD="v2"
        FOUND_MCP23008=true
        break
      fi
    done
  fi
fi

echo "Base board version: $BASE_BOARD"

# Append video configuration to cmdline.txt if not already present
CMDLINE_FILE="/mnt/boot/cmdline.txt"
VIDEO_CONFIG=" video=HDMI-A-1:800x480M-32@60D"

# Verify cmdline.txt exists and is writable
if [ ! -f "$CMDLINE_FILE" ]; then
  echo "Error: $CMDLINE_FILE not found or not mounted"
  exit 1
fi

if grep -q "$VIDEO_CONFIG" "$CMDLINE_FILE"; then
  echo "Video configuration already exists in $CMDLINE_FILE"
else
  # Append to the same line (ensure no trailing newline issues)
  echo -n "$VIDEO_CONFIG" >> "$CMDLINE_FILE"
  if [ $? -eq 0 ]; then
    echo "Appended video configuration to $CMDLINE_FILE"
  else
    echo "Error appending video configuration to $CMDLINE_FILE"
    exit 1
  fi
fi

# Download dmxcore100.dtbo and overwrite existing file
OVERLAY_DIR="/mnt/boot/overlays"

# Verify overlay directory exists
if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: $OVERLAY_DIR not found or not mounted"
  exit 1
fi

# Set download URL based on Compute Module
OVERLAY_FILE=""
if [ "$COMPUTE_MODULE" = "CM5" ]; then
  OVERLAY_FILE="dmxcore100-pi5-$BASE_BOARD.dtbo"
elif [ "$COMPUTE_MODULE" = "CM4" ]; then
  OVERLAY_FILE="dmxcore100-$BASE_BOARD.dtbo"
else
  echo "Error: Unknown module"
  exit 1
fi

DOWNLOAD_URL="https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/overlays/$OVERLAY_FILE"
DEST_FILE="$OVERLAY_DIR/dmxcore100.dtbo"

# Download the overlay
if curl -s -L --fail "$DOWNLOAD_URL" -o "$DEST_FILE"; then
  echo "Successfully downloaded $OVERLAY_FILE to $DEST_FILE"
else
  echo "Failed to download dmxcore100.dtbo from $DOWNLOAD_URL"
  exit 1
fi

exit 0
