#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

echo "Starting HostOS update..."

# Function to download a file to /tmp
download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -s -L "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        echo "Error: Neither curl nor wget is available to download files."
        exit 1
    fi
    if [ $? -ne 0 ] || [ ! -f "$output" ]; then
        echo "Error: Failed to download $url"
        exit 1
    fi
}

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
      # Attempts to read 1 byte from IODIR register (0x00) at address 0x20
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

# Append video configuration to cmdline.txt for v1 only
CMDLINE_FILE="/mnt/boot/cmdline.txt"
VIDEO_CONFIG="video=HDMI-A-1:800x480M-32@60D"

if [ "$BASE_BOARD" = "v1" ]; then
  # Verify cmdline.txt exists and is writable
  if [ ! -f "$CMDLINE_FILE" ]; then
    echo "Error: $CMDLINE_FILE not found or not mounted"
    exit 1
  fi

  # Read the first (and only) line of cmdline.txt
  CMDLINE_CONTENT=$(head -n 1 "$CMDLINE_FILE")

  if echo "$CMDLINE_CONTENT" | grep -q "$VIDEO_CONFIG"; then
    echo "Video configuration already exists in $CMDLINE_FILE"
  else
    # Append video config to the first line and overwrite the file
    echo -n "${CMDLINE_CONTENT} $VIDEO_CONFIG" > "$CMDLINE_FILE"
    if [ $? -eq 0 ]; then
      echo "Appended video configuration to $CMDLINE_FILE"
    else
      echo "Error appending video configuration to $CMDLINE_FILE"
      exit 1
    fi
  fi
else
  echo "Base board v2 detected, skipping video configuration append to $CMDLINE_FILE"
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

# Download dmxcore-logo.png to /tmp and copy to splash directories
SPLASH_DIR="/mnt/boot/splash"
LOGO_FILE="/tmp/dmxcore-logo.png"
LOGO_URL="https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/dmxcore-logo.png"

# Verify splash directory exists
if [ ! -d "$SPLASH_DIR" ]; then
  echo "Error: $SPLASH_DIR not found or not mounted"
  exit 1
fi

# Download the logo
download_file "$LOGO_URL" "$LOGO_FILE"

# Copy to both destinations
cp "$LOGO_FILE" "$SPLASH_DIR/balena-logo.png"
if [ $? -ne 0 ]; then
  echo "Error: Failed to copy dmxcore-logo.png to $SPLASH_DIR/balena-logo.png"
  rm -f "$LOGO_FILE"
  exit 1
fi
cp "$LOGO_FILE" "$SPLASH_DIR/balena-logo-default.png"
if [ $? -ne 0 ]; then
  echo "Error: Failed to copy dmxcore-logo.png to $SPLASH_DIR/balena-logo-default.png"
  rm -f "$LOGO_FILE"
  exit 1
fi
echo "Successfully copied dmxcore-logo.png to $SPLASH_DIR/balena-logo.png and $SPLASH_DIR/balena-logo-default.png"

# Clean up
rm -f "$LOGO_FILE"

# Perform EEPROM update for v2 only
if [ "$BASE_BOARD" = "v2" ]; then
  # Download display_edid.bin to /tmp
  EDID_FILE="/tmp/display_edid.bin"
  download_file "https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/display_edid.bin" "$EDID_FILE"

  # Verify the downloaded file is exactly 128 bytes
  FILE_SIZE=$(stat -f%z "$EDID_FILE" 2>/dev/null || stat -c%s "$EDID_FILE")
  if [ "$FILE_SIZE" -ne 128 ]; then
      echo "Error: Downloaded display_edid.bin is $FILE_SIZE bytes, expected 128 bytes."
      rm -f "$EDID_FILE"
      exit 1
  fi

  # Download update-edid-eeprom.sh to /tmp
  SCRIPT_FILE="/tmp/update-edid-eeprom.sh"
  download_file "https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/update-edid-eeprom.sh" "$SCRIPT_FILE"

  # Make the script executable
  chmod +x "$SCRIPT_FILE"

  # Execute the EEPROM update script with the downloaded binary
  "$SCRIPT_FILE" "$EDID_FILE"
  if [ $? -ne 0 ]; then
      echo "Error: Failed to execute update-edid-eeprom.sh"
      rm -f "$EDID_FILE" "$SCRIPT_FILE"
      exit 1
  fi

  # Clean up
  rm -f "$EDID_FILE" "$SCRIPT_FILE"
else
  echo "Base board v1 detected, skipping EEPROM update (no EEPROM present)."
fi

echo "HostOS update completed."

exit 0
