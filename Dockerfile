# Use Python 3.13 slim-bullseye as base
FROM python:3.13-slim-bullseye AS builder

# Set shell options
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Node.js 20.x first (since this is needed for building)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    printf "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main\n" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Set up for building TypeScript
WORKDIR /build
COPY package*.json ./
COPY tsconfig.json ./
COPY src/ ./src/

# Install dependencies and build
RUN npm install && npm run build

# Start fresh for the final image
FROM python:3.13-slim-bullseye

# Set shell options
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Node.js and other runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    udev \
    build-essential \
    bsdmainutils \
    coreutils \
    python3-pip \
    unzip \
    ca-certificates \
    gnupg \
    less && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    printf "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main\n" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip && \
    rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PLATFORMIO_CACHE_DIR="/root/.platformio" \
    PLATFORMIO_UPLOAD_SPEED="921600" \
    WORKSPACE_DIR="/workspace" \
    AWS_DEFAULT_REGION="us-east-1" \
    SERVER_PORT=3001

# Install PlatformIO
RUN pip3 install --no-cache-dir platformio==6.1.16

# Create workspace and initialize PlatformIO project
WORKDIR /workspace
RUN printf "[env:local]\nplatform = espressif32\nboard = esp32-s3-devkitc-1\nframework = arduino\n" > platformio.ini && \
    platformio platform install espressif32 && \
    platformio lib install \
    "gilmaimon/ArduinoWebsockets @ ^0.5.4" \
    "adafruit/Adafruit VL53L1X @ ^3.1.0" \
    "adafruit/Adafruit BusIO @ ^1.14.1" \
    "bblanchon/ArduinoJson@^7.2.1" \
    "adafruit/Adafruit NeoPixel" && \
    rm platformio.ini

# Set up application
WORKDIR /app

# Copy only production dependencies
COPY package*.json ./
RUN npm install --production

# Copy built files from builder stage and entrypoint script
COPY --from=builder /build/dist ./dist
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# Expose API port
EXPOSE 3001

# Start the server
CMD ["node", "dist/server.js"]
