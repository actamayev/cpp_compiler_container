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
BUILD_DIR="$WORKSPACE_DIR/.pio/build/esp32-s3-devkitc-1"
USER_CODE_FILE="$SRC_DIR/user_code.cpp"
HEADER_FILE="$INCLUDE_DIR/user_code.h"

# Function to fetch and extract firmware from S3
fetch_firmware() {
    local env="${ENVIRONMENT:-local}"
    local s3_bucket="staging-pip-firmware"  # default to staging

    if [ "$env" = "production" ]; then
        s3_bucket="production-pip-firmware"
    fi

    local s3_key="firmware.zip"  # or whatever naming convention you prefer

    if [ "$env" != "local" ]; then
        log "Fetching firmware from S3 bucket: ${s3_bucket} for environment: $env"
        if ! aws s3 cp "s3://${s3_bucket}/${s3_key}" /tmp/firmware.zip; then
            error "Failed to fetch firmware from S3"
        fi

        log "Extracting firmware..."
        rm -rf "$WORKSPACE_DIR"/*
        unzip -q /tmp/firmware.zip -d "$WORKSPACE_DIR"
        rm /tmp/firmware.zip
    fi
}

# Initialize workspace
init_workspace() {
    log "Initializing workspace..."
    mkdir -p "$SRC_DIR" "$INCLUDE_DIR" "$BUILD_DIR"
}

# Main execution starts here
log "Starting compilation process..."

# Initialize workspace
init_workspace

# Fetch firmware if needed
fetch_firmware

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    error "USER_CODE environment variable is empty or not set"
fi

if [ -z "$PIP_ID" ]; then
    log "PIP_ID not set, will use default based on ENVIRONMENT"
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
cat > "$TEMP_FILE" << EOL
#include "./include/config.h"
#include "./include/rgb_led.h"
#include "./include/user_code.h"

void user_code() {
${USER_CODE//\'}
}
EOL

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

# In entrypoint.sh, before the platformio run command:
if [ "$NEEDS_REBUILD" = true ] || [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    log "Starting PlatformIO build..."
    
    # Create or update platformio.ini with build flags
    sed -i "s/^build_flags.*$/build_flags = ${BUILD_FLAGS}/" platformio.ini
    
    if ! platformio run -j 2 --silent --environment ${ENVIRONMENT}; then
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
