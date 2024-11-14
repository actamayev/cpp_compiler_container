# Dockerfile for ESP32 C++ Compilation Environment
FROM espressif/idf:latest

# Install additional build tools if needed
# THIS MIGHT BE NEEDED:
# RUN apt-get update && apt-get install -y make cmake ninja-build

# Install PlatformIO
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    pip3 install platformio

# Copy PlatformIO configuration and firmware
COPY platformio.ini /workspace/platformio.ini
COPY firmware /workspace/firmware  

# Pre-install libraries specified in platformio.ini
RUN cd /workspace && platformio lib install

# Set up the working directory
WORKDIR /workspace

# Ensure the ESP-IDF environment is loaded for subsequent commands
RUN /bin/bash -c "source /opt/esp/idf/export.sh"

# Copy and make the entrypoint executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default command for running compilation
CMD ["/entrypoint.sh"]
