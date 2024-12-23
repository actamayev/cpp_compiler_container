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
WORKSPACE_DIR="/workspace"
WORKSPACE_BASE_DIR="$WORKSPACE_DIR"
SRC_DIR="$WORKSPACE_BASE_DIR/src"
USER_CODE_FILE="$SRC_DIR/user_code.cpp"
BUILD_DIR="$WORKSPACE_BASE_DIR/.pio/build/${pio_env}"

# Check if workspace is initialized
if [ ! -f "$WORKSPACE_BASE_DIR/platformio.ini" ]; then
    error "Workspace not initialized. Please run /update-firmware first"
fi

# Check USER_CODE
if [ -z "$USER_CODE" ]; then
    error "USER_CODE environment variable is empty or not set"
fi

log "Creating user code file..."
cat > "$USER_CODE_FILE" << EOL
#include "./include/config.h"
#include "./include/rgb_led.h"
#include "./include/user_code.h"

void user_code() {
${USER_CODE//\'}
}
EOL

log "User code file contents:"
cat "$USER_CODE_FILE"

# Build the project
cd "$WORKSPACE_BASE_DIR" || error "Failed to change to workspace directory"

export PLATFORMIO_CACHE_DIR="/root/.platformio"
export PLATFORMIO_GLOBAL_DIR="/root/.platformio"

log "Starting PlatformIO build..."
log "Command: platformio run --environment $pio_env --verbose"

if ! PLATFORMIO_BUILD_CACHE_DIR="/root/.platformio/cache" \
    platformio run --environment "$pio_env" --verbose; then
    error "Build failed"
fi

log "Build completed successfully"

# Check binary
if [ ! -f "$BUILD_DIR/firmware.bin" ]; then
    error "Firmware binary not found after compilation"
fi

log "Verifying binary..."
first_byte=$(od -An -t x1 -N 1 "$BUILD_DIR/firmware.bin" | tr -d ' ')
log "First byte of binary: 0x$first_byte"

if [ "$first_byte" != "e9" ]; then
    error "Invalid binary header (expected 0xE9, got 0x$first_byte)"
fi

log "Binary details: $(ls -l "$BUILD_DIR/firmware.bin")"

# Output binary
cat "$BUILD_DIR/firmware.bin"

log "Compilation completed successfully"
