#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Use sudo."
  exit 1
fi

# Append video configuration to cmdline.txt if not already present
CMDLINE_FILE="/mnt/boot/cmdline.txt"
VIDEO_CONFIG=" video=HDMI-A-1:800x480M-32@60D"

if grep -q "$VIDEO_CONFIG" "$CMDLINE_FILE"; then
  echo "Video configuration already exists in $CMDLINE_FILE"
else
  echo -n "$VIDEO_CONFIG" >> "$CMDLINE_FILE"
  echo "Appended video configuration to $CMDLINE_FILE"
fi

# Create overlays directory if it doesn't exist
OVERLAY_DIR="/mnt/boot/overlays"
mkdir -p "$OVERLAY_DIR"

# Download dmxcore100.dtbo and overwrite existing file
if cat /proc/device-tree/model | grep -q "Compute Module 5"; then
	DOWNLOAD_URL="https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/overlays/dmxcore100-pi5.dtbo"
elif cat /proc/device-tree/model | grep -q "Compute Module 4"; then
	DOWNLOAD_URL="https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/overlays/dmxcore100.dtbo"
else
	echo "Unknown module"
fi

DEST_FILE="$OVERLAY_DIR/dmxcore100.dtbo"

if curl -L --fail "$DOWNLOAD_URL" -o "$DEST_FILE"; then
  echo "Successfully downloaded dmxcore100.dtbo to $DEST_FILE"
else
  echo "Failed to download dmxcore100.dtbo"
  exit 1
fi
