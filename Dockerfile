# Use Python 3.13 slim-bullseye for better performance
FROM python:3.13-slim-bullseye

# Install required packages in a single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git=1:2.30.2-1+deb11u2 \
    curl=7.74.0-1.3+deb11u11 \
    udev=247.3-7+deb11u4 \
    build-essential=12.9 \
    bsdmainutils=12.1.7+nmu3 \
    coreutils=8.32-4+b1 \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PLATFORMIO_CACHE_DIR="/root/.platformio" \
    PLATFORMIO_BUILD_FLAGS="-j 2" \
    PLATFORMIO_UPLOAD_SPEED="921600"

# Install PlatformIO with specific version
RUN python3 -m pip install --no-cache-dir platformio==6.1.16

# Create workspace directory and cache volume mount points
WORKDIR /workspace
VOLUME ["/root/.platformio", "/workspace/.pio"]

# Pre-install ESP32 platform and common libraries
RUN platformio platform install espressif32 && \
    platformio lib install \
    "gilmaimon/ArduinoWebsockets@^0.5.4" \
    "adafruit/Adafruit VL53L1X@^3.1.0" \
    "adafruit/Adafruit BusIO@^1.14.1" \
    "bblanchon/ArduinoJson@^7.2.0"

# Create necessary directories
RUN mkdir -p /workspace/src/include

# Copy and prepare entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Verify installations and cache setup
RUN platformio --version && \
    dd --version > /dev/null 2>&1 && \
    platformio run --target idedata

# Warmup cache with initial build
COPY platformio.ini /workspace/
RUN platformio run --target idedata

# Default command
CMD ["tail", "-f", "/dev/null"]
