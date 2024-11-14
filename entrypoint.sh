#!/bin/bash

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
cat > "$SRC_DIR/user_code.cpp" << EOL
#include <Arduino.h>
#include "./include/user_code.h"
#include "./include/config.h"

void user_code() {
    ${USER_CODE}
}
EOL

# Confirm that the files were written (for debugging)
echo "Generated user_code.cpp:"
cat "$SRC_DIR/user_code.cpp"

# Move to the workspace directory and compile
cd "$WORKSPACE_DIR"
platformio run

# Copy the firmware to the mounted volume
echo "Firmware compilation completed. Binary location: .pio/build/esp32dev/firmware.bin
