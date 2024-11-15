#!/bin/bash

set -e  # Exit on any error

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"
BUILD_DIR="$WORKSPACE_DIR/.pio/build/esp32dev"

echo "Starting compilation process..." >&2
echo "Workspace dir: $WORKSPACE_DIR" >&2

# Ensure directories exist
mkdir -p "$SRC_DIR"
mkdir -p "$INCLUDE_DIR"
mkdir -p "$BUILD_DIR"

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    echo "USER_CODE environment variable is empty or not set. Exiting." >&2
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

# Append the user code
echo "${USER_CODE//\'}" >> "$SRC_DIR/user_code.cpp"

# Close the function
echo "}" >> "$SRC_DIR/user_code.cpp"

# Debug output
echo "Generated user_code.cpp:" >&2
cat "$SRC_DIR/user_code.cpp" >&2

# Move to the workspace directory
cd "$WORKSPACE_DIR"

# Clean the build directory
echo "Cleaning build directory..." >&2
platformio run --target clean

# Try build
echo "Starting PlatformIO build..." >&2
if ! platformio run --silent; then
    echo "Build failed, running with verbose output..." >&2
    platformio run -v
    exit 1
fi

# Check if the binary exists and verify its size
if [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    echo "Firmware binary not found after compilation" >&2
    exit 1
fi

# Output binary file size and info to stderr for debugging
echo "Binary details:" >&2
ls -l "$BUILD_DIR/firmware.bin" >&2

# Important: Send ONLY the binary data to stdout, all other output to stderr
cat "$BUILD_DIR/firmware.bin"
