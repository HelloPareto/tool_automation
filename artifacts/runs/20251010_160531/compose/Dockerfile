# Base Dockerfile for tool installations
FROM ubuntu:22.04

# Set non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive

# Update and install base dependencies
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        sudo \
        unzip \
        git \
        file \
        build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create standard directories
RUN mkdir -p /usr/share/keyrings \
    /etc/apt/sources.list.d \
    /usr/local/bin \
    /opt/tools

# Set up locale
RUN apt-get update && apt-get install -y locales && \
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
RUN mkdir -p /workspace && chmod 755 /workspace
COPY shared_setup.sh /workspace/shared_setup.sh
COPY tools/core/tool_setup.sh /workspace/tools/core/tool_setup.sh
COPY tools/metabase/tool_setup.sh /workspace/tools/metabase/tool_setup.sh
COPY tools/pymc/tool_setup.sh /workspace/tools/pymc/tool_setup.sh
COPY run_all.sh /workspace/run_all.sh
RUN chmod +x /workspace/run_all.sh /workspace/shared_setup.sh || true
