#!/usr/bin/env bash
set -euo pipefail

#######################################
# DuckDB v1.4.0 Installation Script
#
# This script installs DuckDB CLI from binary release
# Following Solutions Team Install Standards
#
# Tool: duckdb
# Version: v1.4.0
# Method: binary_release
# Validate: duckdb --version || duckdb version
#######################################

# Configuration
readonly TOOL_NAME="duckdb"
readonly TOOL_VERSION="v1.4.0"
readonly VERSION_NUMBER="1.4.0"
readonly DOWNLOAD_URL="https://github.com/duckdb/duckdb/releases/download/${TOOL_VERSION}/duckdb_cli-linux-amd64.zip"
readonly INSTALL_DIR="/usr/local/bin"
readonly CHECKSUM="559398da12db9223fb0663ae65a365b2740e4e35abf009a81350a3f57e175ecc"

#######################################
# Logging function with timestamps
#######################################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

#######################################
# Error handler
#######################################
error_exit() {
    log "ERROR: $1"
    exit 1
}

#######################################
# Check Prerequisites
# DuckDB binary has no runtime prerequisites
# Only needs basic utilities (curl, unzip) which are in base image
#######################################
check_prerequisites() {
    log "Checking prerequisites for ${TOOL_NAME}..."

    local missing_tools=()

    # Check for curl or wget
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        missing_tools+=("curl or wget")
    fi

    # Check for unzip
    if ! command -v unzip &>/dev/null; then
        missing_tools+=("unzip")
    fi

    if [ ${#missing_tools[@]} -eq 0 ]; then
        log "All prerequisites are satisfied"
        return 0
    else
        log "Missing prerequisites: ${missing_tools[*]}"
        return 1
    fi
}

#######################################
# Install Prerequisites
# Install any missing basic utilities
#######################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    apt-get update || error_exit "Failed to update package lists"

    # Install missing tools
    local tools_to_install=()

    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        tools_to_install+=("curl")
    fi

    if ! command -v unzip &>/dev/null; then
        tools_to_install+=("unzip")
    fi

    if [ ${#tools_to_install[@]} -gt 0 ]; then
        log "Installing: ${tools_to_install[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${tools_to_install[@]}" || \
            error_exit "Failed to install prerequisites"
    fi

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

#######################################
# Verify Prerequisites
# Confirm all prerequisites work correctly
#######################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify download tool
    if command -v curl &>/dev/null; then
        curl --version >/dev/null || error_exit "curl is installed but not working"
        log "✓ curl is working"
    elif command -v wget &>/dev/null; then
        wget --version >/dev/null || error_exit "wget is installed but not working"
        log "✓ wget is working"
    else
        error_exit "No download tool (curl/wget) available"
    fi

    # Verify unzip
    if ! command -v unzip &>/dev/null; then
        error_exit "unzip is not available"
    fi
    unzip -v >/dev/null || error_exit "unzip is installed but not working"
    log "✓ unzip is working"

    log "All prerequisites verified successfully"
}

#######################################
# Check Existing Installation
# Returns 0 if already installed with correct version
#######################################
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if ! command -v duckdb &>/dev/null; then
        log "${TOOL_NAME} is not installed"
        return 1
    fi

    # Check version
    local installed_version
    installed_version=$(duckdb --version 2>/dev/null | head -n1 || echo "unknown")

    log "Found ${TOOL_NAME} version: ${installed_version}"

    # Check if it matches our target version
    if echo "${installed_version}" | grep -q "${VERSION_NUMBER}"; then
        log "${TOOL_NAME} ${VERSION_NUMBER} is already installed"
        return 0
    else
        log "Different version installed. Will reinstall ${VERSION_NUMBER}"
        return 1
    fi
}

#######################################
# Install Tool
# Download and install DuckDB binary
#######################################
install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Create temporary directory
    local tmp_dir
    tmp_dir=$(mktemp -d) || error_exit "Failed to create temporary directory"

    # Ensure cleanup on exit
    trap 'rm -rf '"${tmp_dir}" EXIT

    cd "${tmp_dir}"

    # Download binary
    log "Downloading ${TOOL_NAME} from ${DOWNLOAD_URL}..."
    if command -v curl &>/dev/null; then
        curl -fsSL -o duckdb_cli.zip "${DOWNLOAD_URL}" || \
            error_exit "Failed to download ${TOOL_NAME}"
    else
        wget -q -O duckdb_cli.zip "${DOWNLOAD_URL}" || \
            error_exit "Failed to download ${TOOL_NAME}"
    fi

    # Verify checksum
    log "Verifying checksum..."
    echo "${CHECKSUM}  duckdb_cli.zip" > checksum.txt

    if command -v sha256sum &>/dev/null; then
        sha256sum -c checksum.txt || error_exit "Checksum verification failed"
    else
        log "WARNING: sha256sum not available, skipping checksum verification"
    fi

    # Extract binary
    log "Extracting binary..."
    unzip -q duckdb_cli.zip || error_exit "Failed to extract ${TOOL_NAME}"

    # Install binary
    log "Installing to ${INSTALL_DIR}..."
    chmod +x duckdb || error_exit "Failed to set executable permissions"

    # Remove old version if exists
    if [ -f "${INSTALL_DIR}/duckdb" ]; then
        log "Removing old version..."
        rm -f "${INSTALL_DIR}/duckdb"
    fi

    # Move to install directory
    mv duckdb "${INSTALL_DIR}/duckdb" || error_exit "Failed to install ${TOOL_NAME}"

    # Verify it's executable
    if [ ! -x "${INSTALL_DIR}/duckdb" ]; then
        error_exit "${TOOL_NAME} binary is not executable"
    fi

    log "${TOOL_NAME} installed successfully to ${INSTALL_DIR}/duckdb"
}

#######################################
# Validate Installation
# Verify the tool works and reports correct version
#######################################
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if binary exists and is executable
    if [ ! -x "${INSTALL_DIR}/duckdb" ]; then
        error_exit "${TOOL_NAME} binary not found or not executable at ${INSTALL_DIR}/duckdb"
    fi

    # Verify command is in PATH
    if ! command -v duckdb &>/dev/null; then
        error_exit "${TOOL_NAME} is not in PATH"
    fi

    # Run validation command
    local version_output
    version_output=$(duckdb --version 2>&1 || duckdb version 2>&1) || \
        error_exit "Failed to run ${TOOL_NAME} --version"

    log "Version output: ${version_output}"

    # Verify version matches
    if echo "${version_output}" | grep -q "${VERSION_NUMBER}"; then
        log "✓ ${TOOL_NAME} ${VERSION_NUMBER} validated successfully"
        return 0
    else
        error_exit "Version mismatch. Expected ${VERSION_NUMBER}, got: ${version_output}"
    fi
}

#######################################
# Main Installation Flow
#######################################
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."
    log "Installation method: binary_release"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "${TOOL_NAME} is already installed with correct version"
        validate
        log "Installation check completed - no changes needed"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "Installation completed successfully"
    log "${TOOL_NAME} ${TOOL_VERSION} is ready to use"
}

# Execute main function
main "$@"
