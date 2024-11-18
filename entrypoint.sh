#!/bin/bash

# Function to log to stderr with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
    exit 1
}

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"
BUILD_DIR="$WORKSPACE_DIR/.pio/build/esp32dev"
USER_CODE_FILE="$SRC_DIR/user_code.cpp"
HEADER_FILE="$INCLUDE_DIR/user_code.h"

log "Starting compilation process..."

# Ensure directories exist
mkdir -p "$SRC_DIR" "$INCLUDE_DIR" "$BUILD_DIR"

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    error "USER_CODE environment variable is empty or not set"
fi

# Create the header file only if it doesn't exist
if [ ! -f "$HEADER_FILE" ]; then
    log "Creating header file..."
    cat > "$HEADER_FILE" << EOL
#ifndef USER_CODE_H
#define USER_CODE_H
void user_code();
#endif
EOL
fi

# Check if user code has changed
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << 'EOCPP'
#include <Arduino.h>
#include "./include/user_code.h"
#include "./include/config.h"

void user_code() {
EOCPP

echo "${USER_CODE//\'}" >> "$TEMP_FILE"
echo "}" >> "$TEMP_FILE"

# Only update user_code.cpp if content has changed
if [ ! -f "$USER_CODE_FILE" ] || ! cmp -s "$TEMP_FILE" "$USER_CODE_FILE"; then
    log "User code changed, updating file..."
    mv "$TEMP_FILE" "$USER_CODE_FILE"
    NEEDS_REBUILD=true
else
    log "User code unchanged, skipping file update..."
    rm "$TEMP_FILE"
    NEEDS_REBUILD=false
fi

# Build the project only if needed
cd "$WORKSPACE_DIR"

if [ "$NEEDS_REBUILD" = true ] || [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    log "Starting PlatformIO build..."
    if ! platformio run -j 2 --silent --environment esp32dev; then
        error "Build failed"
    fi
else
    log "Using cached build..."
fi

# Check if binary exists
if [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    error "Firmware binary not found after compilation"
fi

# Verify binary header
first_byte=$(od -An -t x1 -N 1 "$BUILD_DIR/firmware.bin" | tr -d ' ')
log "First byte of binary: 0x$first_byte"

if [ "$first_byte" != "e9" ]; then
    error "Invalid binary header (expected 0xE9, got 0x$first_byte)"
fi

# Output binary info
log "Binary details: $(ls -l "$BUILD_DIR/firmware.bin")"

# Stream binary directly to stdout
cat "$BUILD_DIR/firmware.bin"
