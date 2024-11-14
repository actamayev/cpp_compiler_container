#!/bin/bash

# Define paths
WORKSPACE_DIR="/workspace"
USER_CODE_FILE="$WORKSPACE_DIR/src/user_code.cpp"

# Ensure the src directory exists
mkdir -p "$WORKSPACE_DIR/src"

# Write the user code from the environment variable to `user_code.cpp`
echo -e "$USER_CODE" > "$USER_CODE_FILE"

# Move to the workspace directory and compile
cd "$WORKSPACE_DIR"
platformio run

# Print the location of the compiled firmware binary
echo "Firmware compiled successfully! Check the .pio/build directory for the binary."
