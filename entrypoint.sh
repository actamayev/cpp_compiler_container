#!/bin/bash

# Function to log to stderr
log() {
    echo "[INFO] $1" >&2
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"
BUILD_DIR="$WORKSPACE_DIR/.pio/build/esp32dev"

log "Starting compilation process..."

# Ensure directories exist
mkdir -p "$SRC_DIR" "$INCLUDE_DIR" "$BUILD_DIR"

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    error "USER_CODE environment variable is empty or not set"
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

# Append the user code and close the function
echo "${USER_CODE//\'}" >> "$SRC_DIR/user_code.cpp"
echo "}" >> "$SRC_DIR/user_code.cpp"

log "Generated user_code.cpp:"
cat "$SRC_DIR/user_code.cpp" >&2

# Build the project
cd "$WORKSPACE_DIR"

log "Cleaning build directory..."
platformio run --target clean >&2

log "Starting PlatformIO build..."
if ! platformio run --silent >&2; then
    error "Build failed"
fi

# Check if binary exists
if [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    error "Firmware binary not found after compilation"
fi

# Output binary info to stderr
log "Binary details:"
ls -l "$BUILD_DIR/firmware.bin" >&2

# Verify binary header
first_byte=$(od -An -t x1 -N 1 "$BUILD_DIR/firmware.bin" | tr -d ' ')
log "First byte of binary: 0x$first_byte"

if [ "$first_byte" != "e9" ]; then
    error "Invalid binary header (expected 0xE9, got 0x$first_byte)"
fi

# Output only the binary to stdout
cat "$BUILD_DIR/firmware.bin"
