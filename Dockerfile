# Dockerfile for ESP32 C++ Compilation Environment
FROM espressif/idf:latest

# Install Python dependencies and create a virtual environment
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create a virtual environment for PlatformIO and install it
RUN python3 -m venv /opt/platformio-venv && \
    /opt/platformio-venv/bin/pip install platformio

# Add PlatformIO to PATH
ENV PATH="/opt/platformio-venv/bin:$PATH"

# Pre-install ESP32 platform
RUN platformio platform install espressif32

# Set up working directory
WORKDIR /workspace

# Create cache directory
RUN mkdir -p /root/.platformio

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD platformio platform list | grep espressif32 || exit 1

# Default command to keep container running
CMD ["tail", "-f", "/dev/null"]
