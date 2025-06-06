#!/bin/bash

# Check if input file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File $INPUT_FILE not found."
    exit 1
fi

# Check if file size is exactly 128 bytes
FILE_SIZE=$(stat -f%z "$INPUT_FILE" 2>/dev/null || stat -c%s "$INPUT_FILE")
if [ "$FILE_SIZE" -ne 128 ]; then
    echo "Error: File must be exactly 128 bytes, got $FILE_SIZE bytes."
    exit 1
fi

# Create temporary files in /tmp
EEPROM_TEMP=$(mktemp /tmp/eeprom_temp.XXXXXX)
EEPROM_TEMP_BIN=$(mktemp /tmp/eeprom_temp_bin.XXXXXX)
INPUT_TEMP=$(mktemp /tmp/input_temp.XXXXXX)

# Read 128 bytes from EEPROM in 8-byte chunks
for ((i=0; i<128; i+=8)); do
    # Read 8 bytes at a time (address + read command)
    i2ctransfer -y 20 w1@0x50 $i r8@0x50 >> "$EEPROM_TEMP" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to read EEPROM at address $i."
        rm "$EEPROM_TEMP" "$EEPROM_TEMP_BIN" "$INPUT_TEMP"
        exit 1
    fi
done

# Convert EEPROM data (space-separated hex, e.g., 0x00) to binary
while read -r line; do
    for hex in $line; do
        # Remove 0x prefix and convert hex to binary
        hex_clean=${hex#0x}
        printf "$(printf '\\x%s' "$hex_clean")" >> "$EEPROM_TEMP_BIN"
    done
done < "$EEPROM_TEMP"
rm "$EEPROM_TEMP"

# Copy input file to temp binary file
cp "$INPUT_FILE" "$INPUT_TEMP"

# Compare EEPROM data with input file
if cmp -s "$EEPROM_TEMP_BIN" "$INPUT_TEMP"; then
    echo "EEPROM contents match the input file. No write needed."
    rm "$EEPROM_TEMP_BIN" "$INPUT_TEMP"
    exit 0
fi
rm "$EEPROM_TEMP_BIN" "$INPUT_TEMP"

echo "EEPROM contents do not match input file. Writing to EEPROM..."

# Convert input file to hex array using od
DATA=($(od -An -tx1 -v -w1 "$INPUT_FILE"))

# Write 128 bytes in 8-byte pages (24LC02 has 8-byte page write limit)
for ((i=0; i<128; i+=8)); do
    ADDR=$i
    PAGE_DATA=()
    for ((j=0; j<8; j++)); do
        PAGE_DATA+=("0x${DATA[$((i+j))]}")
    done
    i2ctransfer -y 20 w9@0x50 $ADDR "${PAGE_DATA[@]}" >/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to write page starting at address $ADDR."
        exit 1
    fi
    # Delay to respect EEPROM write cycle (~5ms)
    sleep 0.01
done

echo "Successfully wrote 128 bytes to EEPROM at I2C bus 20, address 0x50."
