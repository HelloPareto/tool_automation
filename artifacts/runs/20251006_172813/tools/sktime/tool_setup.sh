#!/bin/bash

################################################################################
# Tool Installation Script: sktime v0.39.0
# Package Manager: pip
# Description: A unified framework for machine learning with time series
################################################################################

set -euo pipefail

# Configuration
TOOL_NAME="sktime"
TOOL_VERSION="0.39.0"
VALIDATE_CMD="python3 -c 'import sktime; print(sktime.__version__)'"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

################################################################################
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for Python3
    if command -v python3 >/dev/null 2>&1; then
        log "✓ Python3 found: $(python3 --version 2>&1)"
    else
        log "✗ Python3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 >/dev/null 2>&1; then
        log "✓ pip3 found: $(pip3 --version 2>&1 | head -n1)"
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
    log "Installing missing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    if ! apt-get update; then
        error "Failed to update package lists. Ensure you have root privileges and apt-get is available."
    fi

    # Install Python3 and pip if not present
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Installing Python3 and pip3..."
        if ! apt-get install -y python3 python3-pip python3-venv; then
            error "Failed to install Python3 and pip3. Check your system's package manager configuration."
        fi
    fi

    # Clean up apt cache
    log "Cleaning package manager cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python3 verification failed. Python3 is not working correctly."
    fi
    log "✓ Python3 verified: $(python3 --version 2>&1)"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed. pip3 is not working correctly."
    fi
    log "✓ pip3 verified: $(pip3 --version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

################################################################################
# Tool Installation
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if sktime is importable and get version
    if python3 -c "import sktime; print(sktime.__version__)" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(python3 -c "import sktime; print(sktime.__version__)" 2>/dev/null)

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "✓ ${TOOL_NAME} v${TOOL_VERSION} is already installed"
            return 0
        else
            log "Different version found: v${installed_version}. Will install v${TOOL_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Install specific version using pip
    log "Running: pip3 install ${TOOL_NAME}==${TOOL_VERSION}"
    if ! pip3 install --no-cache-dir "${TOOL_NAME}==${TOOL_VERSION}"; then
        error "Failed to install ${TOOL_NAME} v${TOOL_VERSION}. Check pip logs for details."
    fi

    log "${TOOL_NAME} installation completed"
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Run validation command
    local output
    if ! output=$(eval "$VALIDATE_CMD" 2>&1); then
        error "Validation failed: ${TOOL_NAME} is not properly installed or not accessible. Output: $output"
    fi

    # Check if version matches
    if [ "$output" != "$TOOL_VERSION" ]; then
        error "Version mismatch: expected ${TOOL_VERSION}, got ${output}"
    fi

    log "✓ Validation successful: ${TOOL_NAME} v${output}"
    return 0
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
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

# Execute main function
main "$@"
