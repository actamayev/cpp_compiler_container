#!/bin/bash

set -e  # Exit on any error

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"

# Ensure directories exist
mkdir -p "$SRC_DIR"
mkdir -p "$INCLUDE_DIR"

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    echo "USER_CODE environment variable is empty or not set. Exiting."
    exit 1
fi

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
cat > "$SRC_DIR/user_code.cpp" << 'EOCPP'
#include <Arduino.h>
#include "./include/user_code.h"
#include "./include/config.h"

void user_code() {
EOCPP

# Append the user code (remove surrounding quotes if present)
echo "${USER_CODE//\'}" >> "$SRC_DIR/user_code.cpp"

# Close the function
echo "}" >> "$SRC_DIR/user_code.cpp"

# Debug output
echo "Generated user_code.cpp:"
cat "$SRC_DIR/user_code.cpp"

# Move to the workspace directory and compile
cd "$WORKSPACE_DIR"

# Run platformio with optimizations
platformio run --silent || {
    echo "PlatformIO build failed"
    platformio run -v  # Run again with verbose output for debugging
    exit 1
}

# Check if the binary exists
if [ ! -f ".pio/build/esp32dev/firmware.bin" ]; then
    echo "Firmware binary not found after compilation"
    exit 1
fi

# Output the binary to stdout
cat .pio/build/esp32dev/firmware.bin
