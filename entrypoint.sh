#!/bin/bash

# Define paths
WORKSPACE_DIR="/workspace"
USER_CODE_FILE="$WORKSPACE_DIR/src/user_code.cpp"

# Ensure the src directory exists
mkdir -p "$WORKSPACE_DIR/src"

# Write user code to `user_code.cpp` in the src directory
echo "$1" > "$USER_CODE_FILE"

# Move to the workspace directory and compile
cd "$WORKSPACE_DIR"
platformio run

# Print the location of the compiled binary
echo "Firmware compiled successfully! Check the .pio/build directory for the binary."
