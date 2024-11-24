#!/bin/bash

# Function to log to stderr with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
    exit 1
}

# Get environment, default to local if not set
pio_env="${ENVIRONMENT:-local}"

# Define paths
WORKSPACE_DIR="/workspace"
SRC_DIR="$WORKSPACE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"
BUILD_DIR="$WORKSPACE_DIR/.pio/build/${pio_env}"
USER_CODE_FILE="$SRC_DIR/user_code.cpp"
HEADER_FILE="$INCLUDE_DIR/user_code.h"
FIRMWARE_SOURCE="${FIRMWARE_SOURCE:-}"


# Function to fetch and extract firmware from S3
fetch_firmware() {
    local env="$pio_env"
    local s3_bucket=""
    local s3_key="firmware/latest/firmware.zip"

    if [ "$env" = "production" ]; then
        s3_bucket="${PRODUCTION_FIRMWARE_BUCKET:-production-pip-firmware}"
    else
        s3_bucket="${STAGING_FIRMWARE_BUCKET:-staging-pip-firmware}"
    fi

    if [ "$env" != "local" ]; then
        log "Fetching firmware from S3 bucket: ${s3_bucket} for environment: $env"
        if ! aws s3 cp "s3://${s3_bucket}/${s3_key}" /tmp/firmware.zip; then
            error "Failed to fetch firmware from S3"
        fi

        log "Extracting firmware..."
        rm -rf "$WORKSPACE_DIR"/*
        unzip -q /tmp/firmware.zip -d "$WORKSPACE_DIR"
        rm /tmp/firmware.zip
    else
        log "Using local firmware directory"
        # No need to do anything as the local directory is mounted
    fi
}

# Initialize workspace
init_workspace() {
    log "Initializing workspace..."
    mkdir -p "$SRC_DIR" "$INCLUDE_DIR" "$BUILD_DIR"
}

# Main execution starts here
log "Starting compilation process..."
log "Using environment: ${pio_env}"

if [ "$pio_env" != "local" ]; then
    init_workspace
    fetch_firmware
else
    # Handle local environment
    if [ -n "$FIRMWARE_SOURCE" ] && [ -d "$FIRMWARE_SOURCE" ]; then
        log "Copying local firmware files..."
        # Copy files from read-only firmware directory to workspace
        cp -r "$FIRMWARE_SOURCE"/* "$WORKSPACE_DIR"/ || error "Failed to copy firmware files"
    else
        error "FIRMWARE_SOURCE not set or directory not found"
    fi
fi

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

# Verify platformio.ini exists
if [ ! -f "$WORKSPACE_DIR/platformio.ini" ]; then
    error "platformio.ini not found before build"
fi

if [ "$NEEDS_REBUILD" = true ] || [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    log "Starting PlatformIO build..."
    log "Using PlatformIO environment: ${pio_env}"
    
    if ! platformio run --environment "$pio_env" -j 2 --silent; then
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
