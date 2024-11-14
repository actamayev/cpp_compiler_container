#!/bin/bash

set -e  # Exit on any error

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"

# Ensure directories exist
mkdir -p "$SRC_DIR"
mkdir -p "$INCLUDE_DIR"

# Print environment variables for debugging
echo "Environment variables:"
env

# Check if the USER_CODE_BASE64 environment variable is set
if [ -z "$USER_CODE_BASE64" ]; then
    echo "USER_CODE_BASE64 environment variable is empty or not set. Exiting."
    exit 1
fi

echo "Decoding user code..."

# Decode the base64 user code and handle the result safely
DECODED_CODE=$(echo "$USER_CODE_BASE64" | base64 --decode)
if [ $? -ne 0 ]; then
    echo "Failed to decode base64 input"
    exit 1
fi

echo "Successfully decoded user code:"
echo "$DECODED_CODE"

# Create the header file if it doesn't exist
if [ ! -f "$INCLUDE_DIR/user_code.h" ]; then
    cat > "$INCLUDE_DIR/user_code.h" << EOL
#ifndef USER_CODE_H
#define USER_CODE_H

void user_code();

#endif
EOL
fi

# Create the implementation file
cat > "$SRC_DIR/user_code.cpp" << EOL
#include <Arduino.h>
#include "./include/user_code.h"
#include "./include/config.h"

void user_code() {
${DECODED_CODE}
}
EOL

# Debug output
echo "Generated user_code.cpp:"
cat "$SRC_DIR/user_code.cpp"

# Move to the workspace directory and compile
cd "$WORKSPACE_DIR"

# Run platformio with detailed output
platformio run -v || {
    echo "PlatformIO build failed"
    exit 1
}

# Check if the binary exists
if [ ! -f ".pio/build/esp32dev/firmware.bin" ]; then
    echo "Firmware binary not found after compilation"
    exit 1
fi

# Output the binary to stdout
cat .pio/build/esp32dev/firmware.bin
