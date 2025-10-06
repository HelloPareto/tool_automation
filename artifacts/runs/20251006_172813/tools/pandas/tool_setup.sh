#!/bin/bash

################################################################################
# pandas v2.3.3 Installation Script
# Solutions Team - Automated Tool Installation
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="pandas"
readonly TOOL_VERSION="2.3.3"
readonly VALIDATE_CMD="python3 -c 'import pandas; print(pandas.__version__)'"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip3
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

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Updating apt package lists..."
        apt-get update

        # Install Python 3 and pip3 if not present
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            apt-get install -y python3
        fi

        if ! command -v pip3 >/dev/null 2>&1; then
            log "Installing pip3..."
            apt-get install -y python3-pip
        fi

        # Clean up apt cache
        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! command -v python3 >/dev/null 2>&1; then
        error "Python 3 verification failed: command not found"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python 3 verified: $python_version"

    # Verify pip3
    if ! command -v pip3 >/dev/null 2>&1; then
        error "pip3 verification failed: command not found"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    log "All prerequisites verified successfully"
    return 0
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import pandas" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pandas; print(pandas.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Will proceed with installation to ensure correct version"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Use pip to install the specific version
    # --no-cache-dir to avoid caching issues
    # --disable-pip-version-check to avoid unnecessary checks
    log "Running: pip3 install --no-cache-dir pandas==${TOOL_VERSION}"

    if pip3 install --no-cache-dir --disable-pip-version-check "pandas==${TOOL_VERSION}"; then
        log "${TOOL_NAME} installed successfully"
    else
        error "Failed to install ${TOOL_NAME} version ${TOOL_VERSION}"
        error "Please check pip3 connectivity and package availability"
        exit 1
    fi
}

################################################################################
# Validation Function
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if pandas can be imported
    if ! python3 -c "import pandas" 2>/dev/null; then
        error "Validation failed: Cannot import pandas"
        error "Please check Python environment and installation"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(eval "$VALIDATE_CMD" 2>/dev/null || echo "unknown")

    if [ "$installed_version" = "$TOOL_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} version ${installed_version}"
        return 0
    else
        error "Validation failed: Expected version ${TOOL_VERSION}, found ${installed_version}"
        error "Please check installation process"
        exit 1
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

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

################################################################################
# Script Entry Point
################################################################################

main "$@"
