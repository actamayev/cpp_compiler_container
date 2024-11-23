# Use Python 3.13 slim-bullseye for better performance
FROM python:3.13-slim-bullseye

# Install required packages in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    udev \
    build-essential \
    bsdmainutils \
    coreutils \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PLATFORMIO_CACHE_DIR="/root/.platformio" \
    PLATFORMIO_UPLOAD_SPEED="921600" \
    WORKSPACE_DIR="/workspace" \
    AWS_DEFAULT_REGION="us-east-1"

# Install AWS CLI and PlatformIO
RUN pip3 install --no-cache-dir \
    awscli \
    platformio==6.1.16

# Create necessary directories
RUN mkdir -p /workspace

# Initialize a temporary PlatformIO project and install dependencies
WORKDIR /tmp/pio-init
RUN platformio init --board esp32-s3-devkitc-1 && \
    platformio platform install espressif32 && \
    platformio lib install \
        "gilmaimon/ArduinoWebsockets @ ^0.5.4" \
        "adafruit/Adafruit VL53L1X @ ^3.1.0" \
        "adafruit/Adafruit BusIO @ ^1.14.1" \
        "bblanchon/ArduinoJson@^7.2.1" \
        "adafruit/Adafruit NeoPixel" && \
    rm -rf /tmp/pio-init

# Verify installations
RUN platformio --version && \
    aws --version && \
    dd --version > /dev/null 2>&1

# Copy and prepare entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create volume mount points
VOLUME ["/root/.platformio", "/workspace"]

# Set final workspace directory
WORKDIR /workspace

# Default command
CMD ["/entrypoint.sh"]
