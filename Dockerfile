# Dockerfile for ESP32 C++ Compilation Environment
FROM espressif/idf:latest

# Install PlatformIO
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    pip3 install platformio

# Set up working directory
WORKDIR /workspace

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default command to run the entrypoint
CMD ["/entrypoint.sh"]
