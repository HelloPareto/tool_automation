# Base Dockerfile for tool installations
FROM ubuntu:22.04

# Set non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive

# Update and install base dependencies
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        ca-certificates \
        sudo \
        unzip \
        git \
        build-essential \
        apt-transport-https \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create standard directories
RUN mkdir -p /usr/share/keyrings \
    /etc/apt/sources.list.d \
    /usr/local/bin \
    /opt/tools

# Set up locale
RUN apt-get update && \
    apt-get install -y locales && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create non-root user for testing
RUN useradd -m -s /bin/bash -u 1000 installer && \
    echo "installer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /workspace

# Default to bash
CMD ["/bin/bash"]
