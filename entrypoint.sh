#!/bin/bash

# Function to log to stderr with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
    exit 1
}

log "Checking PlatformIO cache:"
ls -la /root/.platformio
df -h /root/.platformio

# Get environment, default to local if not set
pio_env="${ENVIRONMENT:-local}"
FIRMWARE_SOURCE="${FIRMWARE_SOURCE:-}"
WORKSPACE_DIR="/workspace"
WARMUP="${WARMUP:-false}"  # Default to false

if [ "$pio_env" = "local" ] && [ -n "${WORKSPACE_DIR:-}" ]; then
    WORKSPACE_BASE_DIR="$WORKSPACE_DIR"
else
    WORKSPACE_BASE_DIR="/workspace"
fi

SRC_DIR="$WORKSPACE_BASE_DIR/src"
INCLUDE_DIR="$SRC_DIR/include"
BUILD_DIR="$WORKSPACE_BASE_DIR/.pio/build/${pio_env}"
USER_CODE_FILE="$SRC_DIR/user_code.cpp"
HEADER_FILE="$INCLUDE_DIR/user_code.h"

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

    log "Fetching firmware from S3 bucket: ${s3_bucket} for environment: $env"
    if ! aws s3 cp "s3://${s3_bucket}/${s3_key}" /tmp/firmware.zip; then
        error "Failed to fetch firmware from S3"
    fi

    log "Extracting firmware..."
    rm -rf "$WORKSPACE_BASE_DIR"/*
    unzip -q /tmp/firmware.zip -d "$WORKSPACE_BASE_DIR"
    rm /tmp/firmware.zip
}

# Initialize workspace
init_workspace() {
    log "Initializing workspace..."
    mkdir -p "$SRC_DIR" "$INCLUDE_DIR" "$BUILD_DIR"
}

# Main execution starts here
log "Starting compilation process..."
log "Using environment: ${pio_env}"

log "FIRMWARE_SOURCE: ${FIRMWARE_SOURCE}"

log "WORKSPACE_BASE_DIR: ${WORKSPACE_BASE_DIR}"

# Always start with a clean workspace
init_workspace

if [ "$pio_env" = "local" ]; then
    if [ -n "$FIRMWARE_SOURCE" ] && [ -d "$FIRMWARE_SOURCE" ]; then
        log "Setting up local workspace..."
        # Copy core build files
        cp "$FIRMWARE_SOURCE/platformio.ini" "$WORKSPACE_BASE_DIR/"
        cp "$FIRMWARE_SOURCE/partitions_custom.csv" "$WORKSPACE_BASE_DIR/"

        # Copy source files
        mkdir -p "$SRC_DIR"
        cp -r "$FIRMWARE_SOURCE/src/"* "$SRC_DIR/"
        
        # Debug output
        log "Workspace contents after copy:"
        ls -la "$WORKSPACE_BASE_DIR"
        log "Source directory contents:"
        ls -la "$SRC_DIR"
    else
        error "FIRMWARE_SOURCE ($FIRMWARE_SOURCE) not set or directory not found"
    fi
else
    fetch_firmware
fi

# Check if the USER_CODE environment variable is set
if [ -z "$USER_CODE" ]; then
    error "USER_CODE environment variable is empty or not set"
fi

if [ -z "$PIP_ID" ]; then
    log "PIP_ID not set, will use default based on ENVIRONMENT"
fi

# Create new user code file in workspace
log "Creating user code file in workspace..."
cat > "$USER_CODE_FILE" << EOL
#include "./include/config.h"
#include "./include/rgb_led.h"
#include "./include/user_code.h"

void user_code() {
${USER_CODE//\'}
}
EOL

# Build the project
cd "$WORKSPACE_BASE_DIR"

# Verify platformio.ini exists
if [ ! -f "$WORKSPACE_BASE_DIR/platformio.ini" ]; then
    error "platformio.ini not found before build"
fi

export PLATFORMIO_CACHE_DIR="/root/.platformio"
export PLATFORMIO_GLOBAL_DIR="/root/.platformio"

log "Starting PlatformIO build..."
log "Using PlatformIO environment: ${pio_env}"

if ! PLATFORMIO_BUILD_CACHE_DIR="/root/.platformio/cache" \
    platformio run --environment "$pio_env" --silent; then
    error "Build failed"
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

# Output binary info to stderr
log "Binary details: $(ls -l "$BUILD_DIR/firmware.bin")" >&2

if [ "$WARMUP" = "true" ]; then
    log "Warmup complete - dependencies cached in /root/.platformio"
    exit 0
fi

# If S3 bucket info is provided, upload the binary
if [ -n "${COMPILED_BINARY_OUTPUT_BUCKET}" ] && [ -n "${OUTPUT_KEY}" ]; then
    log "Uploading binary to S3: s3://${COMPILED_BINARY_OUTPUT_BUCKET}/${OUTPUT_KEY}" >&2
    if ! aws s3 cp "$BUILD_DIR/firmware.bin" "s3://${COMPILED_BINARY_OUTPUT_BUCKET}/${OUTPUT_KEY}"; then
        error "Failed to upload binary to S3"
    fi
    log "Successfully uploaded binary to S3" >&2
fi

# Only output binary to stdout for local environment
if [ "$pio_env" = "local" ]; then
    cat "$BUILD_DIR/firmware.bin"
fi
