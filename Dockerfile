# Use Python 3.13 as base
FROM python:3.13-slim

# Install required packages
RUN apt-get update && \
    apt-get install -y \
    git \
    curl \
    udev \
    build-essential \
    bsdmainutils \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Install PlatformIO
RUN python3 -m pip install --no-cache-dir platformio==6.1.16

# Create workspace directory
WORKDIR /workspace

# Pre-install ESP32 platform only
RUN platformio platform install espressif32

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create necessary directories
RUN mkdir -p /workspace/src/include

# Verify installations
RUN platformio --version && \
    dd --version > /dev/null 2>&1

# Set environment variable for PlatformIO cache
ENV PLATFORMIO_CACHE_DIR="/root/.platformio"

# Keep container running
CMD ["tail", "-f", "/dev/null"]
