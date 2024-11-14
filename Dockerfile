# Dockerfile for ESP32 C++ Compilation Environment
FROM espressif/idf:latest

# Install Python dependencies and create a virtual environment
RUN apt-get update && \
    apt-get install -y python3 python3-pip python3-venv

# Create a virtual environment for PlatformIO
RUN python3 -m venv /opt/platformio-venv

# Install PlatformIO inside the virtual environment
RUN /opt/platformio-venv/bin/pip install platformio

# Add PlatformIO to PATH for convenience
ENV PATH="/opt/platformio-venv/bin:$PATH"

# Set up working directory
WORKDIR /workspace

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default command to run the entrypoint
CMD ["/entrypoint.sh"]
