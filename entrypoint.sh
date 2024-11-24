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

# Function to create platformio.ini
create_platformio_config() {
    log "Creating platformio.ini..."
    cat > "$WORKSPACE_DIR/platformio.ini" << EOL
[env:${pio_env}]
platform = espressif32
board = esp32-s3-devkitc-1
framework = arduino

upload_speed = 921600
monitor_speed = 115200

lib_deps = 
    gilmaimon/ArduinoWebsockets @ ^0.5.4
    adafruit/Adafruit VL53L1X @ ^3.1.0
    adafruit/Adafruit BusIO @ ^1.14.1
    SPI
    Wire
    WiFi
    WiFiClientSecure
    HttpClient
    bblanchon/ArduinoJson@^7.2.1
    adafruit/Adafruit NeoPixel

board_build.flash_mode = qio
board_build.f_cpu = 240000000L

board_build.flash_size = 8MB
board_build.psram = enabled
board_build.psram_type = opi
board_build.arduino.memory_type = qio_opi

board_build.spiram_mode = qio
board_build.spiram_speed = 80

build_flags = 
    # PSRAM
    -DBOARD_HAS_PSRAM
    -mfix-esp32-psram-cache-issue
    -DCONFIG_SPIRAM=y
    -DCONFIG_SPIRAM_SIZE=8388608
    -DCONFIG_SPIRAM_TYPE_AUTO
    -DCONFIG_ESP32_SPIRAM_SUPPORT
    -DCONFIG_SPIRAM_SPEED_80M=y
    
    # USB
    -DARDUINO_USB_MODE=1
    -DARDUINO_USB_CDC_ON_BOOT=1
    -DCONFIG_ARDUINO_USB_CDC_ON_BOOT=y
    -DCONFIG_TINYUSB_CDC=y
    
    # Core settings
    -DARDUINO_RUNNING_CORE=1
    -DDEFAULT_PIP_ID=\\"${PIP_ID}\\"
EOL
}

# Function to fetch and extract firmware from S3
fetch_firmware() {
    local env="$pio_env"
    local s3_bucket="staging-pip-firmware"

    if [ "$env" = "production" ]; then
        s3_bucket="production-pip-firmware"
    fi

    local s3_key="firmware.zip"

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
log "Using environment: ${pio_env}"

# Initialize workspace
init_workspace

# Create platformio config for local environment
if [ "$pio_env" = "local" ]; then
    create_platformio_config
fi

# Fetch firmware if needed (for non-local environments)
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
