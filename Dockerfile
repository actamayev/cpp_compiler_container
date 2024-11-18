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
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PLATFORMIO_CACHE_DIR="/root/.platformio" \
    PLATFORMIO_BUILD_FLAGS="-j 2" \
    PLATFORMIO_UPLOAD_SPEED="921600"

# Install PlatformIO with specific version
RUN python3 -m pip install --no-cache-dir platformio==6.1.16

# Create a temporary project directory for installing dependencies
WORKDIR /tmp/pio-init

# Initialize a temporary PlatformIO project
RUN platformio init --board esp32dev && \
    platformio platform install espressif32 && \
    platformio lib install \
        "gilmaimon/ArduinoWebsockets@^0.5.4" \
        "adafruit/Adafruit VL53L1X@^3.1.0" \
        "adafruit/Adafruit BusIO@^1.14.1" \
        "bblanchon/ArduinoJson@^7.2.0" && \
    rm -rf /tmp/pio-init

# Verify installations
RUN platformio --version && \
    dd --version > /dev/null 2>&1

# Copy and prepare entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create volume mount points
VOLUME ["/root/.platformio", "/workspace"]

# Set workspace directory
WORKDIR /workspace

CMD ["tail", "-f", "/dev/null"]
