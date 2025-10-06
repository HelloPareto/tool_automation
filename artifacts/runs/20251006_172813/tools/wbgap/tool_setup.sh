#!/bin/bash

################################################################################
# Tool Installation Script: wbgap
# Version: 1.0.12
# Package Manager: pip
# Description: World Bank Group API Python library
################################################################################

set -euo pipefail

# Configuration
TOOL_NAME="wbgap"
TOOL_VERSION="1.0.12"
PACKAGE_NAME="wbgapi"
VALIDATE_CMD="python3 -c 'import wbgapi; print(wbgapi.__version__)'"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

################################################################################
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Python3
    if command -v python3 &>/dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "✓ Python3 found: $python_version"
    else
        log "✗ Python3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 &>/dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "✓ pip3 found: $pip_version"
    else
        log "✗ pip3 not found"
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

    # Set non-interactive frontend for apt
    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    if ! apt-get update; then
        error "Failed to update package lists"
        exit 1
    fi

    # Install Python3 and pip3 if not present
    if ! command -v python3 &>/dev/null || ! command -v pip3 &>/dev/null; then
        log "Installing python3, python3-pip, and python3-venv..."
        if ! apt-get install -y python3 python3-pip python3-venv; then
            error "Failed to install Python prerequisites"
            exit 1
        fi
    fi

    # Clean up apt cache
    log "Cleaning up apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version &>/dev/null; then
        error "Python3 verification failed"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1)
    log "✓ Python3 verified: $python_version"

    # Verify pip3
    if ! pip3 --version &>/dev/null; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1)
    log "✓ pip3 verified: $pip_version"

    log "All prerequisites verified successfully"
}

################################################################################
# Tool Installation
################################################################################

check_existing_installation() {
    log "Checking for existing installation..."

    # Check if package is already installed with correct version
    if python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${PACKAGE_NAME}; print(${PACKAGE_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "✓ ${PACKAGE_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "Found ${PACKAGE_NAME} version ${installed_version}, but need version ${TOOL_VERSION}"
            return 1
        fi
    else
        log "✗ ${PACKAGE_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Install the package with pinned version
    log "Running: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
    if ! pip3 install --no-cache-dir "${PACKAGE_NAME}==${TOOL_VERSION}"; then
        error "Failed to install ${PACKAGE_NAME}"
        error "Remediation: Check network connectivity and PyPI availability"
        error "Try manually: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
        exit 1
    fi

    log "${TOOL_NAME} installed successfully"
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating installation..."

    # Run the validation command
    log "Running validation command: ${VALIDATE_CMD}"
    local output
    if output=$(eval "${VALIDATE_CMD}" 2>&1); then
        log "✓ Validation command executed successfully"
        log "Output: $output"

        # Verify the version matches
        if [ "$output" = "$TOOL_VERSION" ]; then
            log "✓ Version verification passed: ${TOOL_VERSION}"
            return 0
        else
            error "Version mismatch: expected ${TOOL_VERSION}, got ${output}"
            exit 1
        fi
    else
        error "Validation command failed"
        error "Command: ${VALIDATE_CMD}"
        error "Output: $output"
        error "Remediation: Check if ${PACKAGE_NAME} is properly installed in Python path"
        exit 1
    fi
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    log "=========================================="
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."
    log "=========================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "Tool is already installed with correct version"
        validate
        log "=========================================="
        log "Installation verification completed successfully"
        log "=========================================="
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "Installation completed successfully"
    log "=========================================="
}

# Execute main function
main "$@"
