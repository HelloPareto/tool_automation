#!/bin/bash
#
# Installation script for SBTi-finance-tool v1.1.0
# This script follows the Solutions Team Install Standards
# and is idempotent, non-interactive, and includes prerequisite detection.
#

set -euo pipefail

# Constants
readonly TOOL_NAME="SBTi-finance-tool"
readonly TOOL_VERSION="v1.1.0"
readonly PACKAGE_NAME="sbti-finance-tool"
readonly PACKAGE_VERSION="1.1.0"  # pip version without 'v' prefix

# Logging function with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Python3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python3: $python_version"
    else
        log "Python3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip3: $pip_version"
    else
        log "pip3 not found"
        all_present=false
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating apt package lists..."
    apt-get update

    # Install Python3, pip, and venv
    log "Installing Python3, pip3, and python3-venv..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv

    # Clean up apt cache
    log "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python3 verification failed"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python3 verified: $python_version"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed
check_existing_installation() {
    log "Checking if ${TOOL_NAME} ${TOOL_VERSION} is already installed..."

    # Check using pip show instead of importing to avoid dependency issues
    if pip3 show "${PACKAGE_NAME}" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(pip3 show "${PACKAGE_NAME}" | grep '^Version:' | awk '{print $2}')

        if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
            log "${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is $installed_version (expected $PACKAGE_VERSION)"
            log "Proceeding with installation to ensure correct version..."
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Install using pip with pinned version
    # Using --no-cache-dir to reduce image size
    # Using --upgrade to ensure we get the correct version if already installed
    log "Running: pip3 install --no-cache-dir ${PACKAGE_NAME}==${PACKAGE_VERSION}"
    pip3 install --no-cache-dir "${PACKAGE_NAME}==${PACKAGE_VERSION}"

    log "${TOOL_NAME} installed successfully"
}

# Validate installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Validate using pip show to check installation
    if ! pip3 show "${PACKAGE_NAME}" >/dev/null 2>&1; then
        error "Package ${PACKAGE_NAME} not found via pip"
        error "Please check that ${TOOL_NAME} was installed correctly"
        exit 1
    fi

    local installed_version
    installed_version=$(pip3 show "${PACKAGE_NAME}" | grep '^Version:' | awk '{print $2}')
    log "Installed version: $installed_version"

    # Check if version matches expected version
    if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
        log "Version matches expected version: ${TOOL_VERSION}"
        log "Validation successful"
        return 0
    else
        error "Version mismatch: expected ${PACKAGE_VERSION}, got ${installed_version}"
        exit 1
    fi
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."
    log "Package: ${PACKAGE_NAME}==${PACKAGE_VERSION}"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation completed successfully (already installed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# Run main function
main "$@"
