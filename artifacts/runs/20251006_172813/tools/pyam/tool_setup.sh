#!/bin/bash

################################################################################
# pyam v3.1.0 Installation Script
# Description: Installs pyam Python package for integrated assessment modeling
# Prerequisites: Python 3, pip3
################################################################################

set -euo pipefail

# Configuration
TOOL_NAME="pyam"
TOOL_VERSION="3.1.0"
VALIDATE_CMD="python3 -c 'import pyam; print(pyam.__version__)'"

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
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python 3: version ${python_version}"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip3: version ${pip_version}"
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
    log "Installing missing prerequisites..."

    # Update package lists
    if command -v apt-get >/dev/null 2>&1; then
        log "Updating apt package lists..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        # Install Python 3 and pip if missing
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            apt-get install -y python3 python3-pip python3-venv
        elif ! command -v pip3 >/dev/null 2>&1; then
            log "Installing pip3..."
            apt-get install -y python3-pip
        fi

        # Clean up apt cache
        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum >/dev/null 2>&1; then
        log "Using yum package manager..."
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            yum install -y python3 python3-pip
        elif ! command -v pip3 >/dev/null 2>&1; then
            log "Installing pip3..."
            yum install -y python3-pip
        fi
        yum clean all

    else
        error "No supported package manager found (apt-get or yum)"
        error "Please install Python 3 and pip3 manually"
        exit 1
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        error "Please ensure Python 3 is installed correctly"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1)
    log "Python 3 verified: ${python_version}"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        error "Please ensure pip3 is installed correctly"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1)
    log "pip3 verified: ${pip_version}"

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import pyam" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pyam; print(pyam.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Will reinstall to ensure correct version"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Install pyam with pinned version
    # Using --no-cache-dir to avoid caching issues and reduce space usage
    log "Running: pip3 install --no-cache-dir pyam-iamc==${TOOL_VERSION}"

    if pip3 install --no-cache-dir "pyam-iamc==${TOOL_VERSION}"; then
        log "${TOOL_NAME} ${TOOL_VERSION} installed successfully"
    else
        error "Failed to install ${TOOL_NAME} ${TOOL_VERSION}"
        error "Please check pip3 configuration and network connectivity"
        error "You can try manually with: pip3 install pyam-iamc==${TOOL_VERSION}"
        exit 1
    fi
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if pyam can be imported
    if ! python3 -c "import pyam" 2>/dev/null; then
        error "Validation failed: Cannot import pyam module"
        error "Installation may be incomplete or corrupted"
        exit 1
    fi

    # Get installed version
    local installed_version
    installed_version=$(eval "$VALIDATE_CMD" 2>&1 || echo "unknown")

    if [ "$installed_version" = "$TOOL_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} version ${installed_version}"
        return 0
    else
        error "Validation failed: Expected version ${TOOL_VERSION}, got ${installed_version}"
        error "Please check the installation or try reinstalling"
        exit 1
    fi
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."
    log "=================================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "=================================================="
        log "${TOOL_NAME} v${TOOL_VERSION} is ready to use"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=================================================="
    log "Installation completed successfully"
    log "${TOOL_NAME} v${TOOL_VERSION} is ready to use"
}

# Execute main function
main "$@"
