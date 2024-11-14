#!/bin/bash

# Source ESP-IDF environment
source /opt/esp/idf/export.sh

# Define paths
FIRMWARE_DIR="/workspace/firmware"
BUILD_DIR="/workspace/build"
USER_CODE_FILE="$BUILD_DIR/user_code.cpp"

# Create build directory if it doesn’t exist
mkdir -p $BUILD_DIR

# Copy base firmware to build directory
cp -r $FIRMWARE_DIR/* $BUILD_DIR/

# Write user code to file (expects user code as the first argument)
echo "$1" > $USER_CODE_FILE

# Compile with user code included
echo "Compiling firmware with user code..."
cd $BUILD_DIR
idf.py build  # Use platformio here if using PlatformIO commands

# Output binary location
echo "Firmware compiled successfully! Binary is located at: $BUILD_DIR/build/firmware.bin"
