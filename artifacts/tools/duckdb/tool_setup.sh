#!/bin/bash
set -euo pipefail

# DuckDB Installation Script
# Version: v1.4.0
# Installation Method: Binary Release
# Description: Installs DuckDB CLI from official GitHub releases

# Configuration
TOOL_VERSION="v1.4.0"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="duckdb"

# Detect architecture
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        BINARY_URL="https://github.com/duckdb/duckdb/releases/download/${TOOL_VERSION}/duckdb_cli-linux-amd64.zip"
        CHECKSUM="559398da12db9223fb0663ae65a365b2740e4e35abf009a81350a3f57e175ecc"
        BINARY_FILE="duckdb_cli-linux-amd64.zip"
        ;;
    aarch64|arm64)
        BINARY_URL="https://github.com/duckdb/duckdb/releases/download/${TOOL_VERSION}/duckdb_cli-linux-arm64.zip"
        CHECKSUM="982993fc6173814beaf432d05ef20d8c5ed0f8a903b10938ed53cee2541bdc39"
        BINARY_FILE="duckdb_cli-linux-arm64.zip"
        ;;
    *)
        echo "ERROR: Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Validation function
validate() {
    log "Validating DuckDB installation..."

    if ! command -v duckdb &> /dev/null; then
        error_exit "DuckDB binary not found in PATH"
    fi

    # Try to get version - DuckDB uses -version flag (single dash)
    local version_output
    if version_output=$(duckdb -version 2>&1); then
        log "DuckDB version output: ${version_output}"
    else
        error_exit "Failed to get DuckDB version. Output: ${version_output}"
    fi

    # Check if version matches
    if echo "${version_output}" | grep -q "${TOOL_VERSION#v}"; then
        log "SUCCESS: DuckDB ${TOOL_VERSION} is installed and validated"
        return 0
    else
        error_exit "Version mismatch. Expected ${TOOL_VERSION}, got: ${version_output}"
    fi
}

# Check if already installed (idempotency)
check_existing_installation() {
    log "Checking for existing DuckDB installation..."

    if command -v duckdb &> /dev/null; then
        local current_version
        if current_version=$(duckdb -version 2>&1); then
            log "Found existing DuckDB: ${current_version}"

            if echo "${current_version}" | grep -q "${TOOL_VERSION#v}"; then
                log "DuckDB ${TOOL_VERSION} is already installed"
                validate
                exit 0
            else
                log "Different version installed. Proceeding with installation of ${TOOL_VERSION}..."
            fi
        fi
    else
        log "DuckDB not found. Proceeding with installation..."
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."

    if command -v apt-get &> /dev/null; then
        apt-get update || true
        apt-get install -y wget unzip ca-certificates || error_exit "Failed to install dependencies"
    elif command -v yum &> /dev/null; then
        yum install -y wget unzip ca-certificates || error_exit "Failed to install dependencies"
    else
        log "WARNING: Unknown package manager. Ensure wget and unzip are installed."
    fi
}

# Download and verify binary
download_and_verify() {
    log "Downloading DuckDB ${TOOL_VERSION} for ${ARCH}..."

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "${tmp_dir}" || error_exit "Failed to create temp directory"

    # Download binary
    if ! wget -q --show-progress "${BINARY_URL}" -O "${BINARY_FILE}"; then
        rm -rf "${tmp_dir}"
        error_exit "Failed to download DuckDB from ${BINARY_URL}"
    fi

    log "Verifying checksum..."
    echo "${CHECKSUM}  ${BINARY_FILE}" > checksum.txt

    if command -v sha256sum &> /dev/null; then
        if ! sha256sum -c checksum.txt; then
            rm -rf "${tmp_dir}"
            error_exit "Checksum verification failed"
        fi
    else
        log "WARNING: sha256sum not found. Skipping checksum verification."
    fi

    log "Checksum verified successfully"
}

# Install binary
install_binary() {
    log "Installing DuckDB binary..."

    # Unzip the binary
    if ! unzip -q "${BINARY_FILE}"; then
        error_exit "Failed to unzip DuckDB binary"
    fi

    # Move binary to installation directory
    if ! mv duckdb "${INSTALL_DIR}/${BINARY_NAME}"; then
        error_exit "Failed to move binary to ${INSTALL_DIR}"
    fi

    # Set executable permissions
    chmod 755 "${INSTALL_DIR}/${BINARY_NAME}"

    log "DuckDB binary installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

# Cleanup
cleanup() {
    log "Cleaning up temporary files..."
    cd / || true
    rm -rf /tmp/duckdb_* 2>/dev/null || true

    if command -v apt-get &> /dev/null; then
        apt-get clean || true
        rm -rf /var/lib/apt/lists/* || true
    fi
}

# Main installation flow
main() {
    log "Starting DuckDB ${TOOL_VERSION} installation..."

    # Check if already installed
    check_existing_installation

    # Install dependencies
    install_dependencies

    # Download and verify
    download_and_verify

    # Install binary
    install_binary

    # Cleanup
    cleanup

    # Validate installation
    validate

    log "DuckDB ${TOOL_VERSION} installation completed successfully!"
}

# Run main function
main
