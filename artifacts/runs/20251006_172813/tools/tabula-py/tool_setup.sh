#!/usr/bin/env bash

################################################################################
# Tool Installation Script: tabula-py v2.10.0
# Description: Python wrapper for Apache Tika's Tabula-java library
# Installation Method: pip
# Prerequisites: Python 3, pip, Java Runtime Environment
################################################################################

set -euo pipefail

# Constants
readonly TOOL_NAME="tabula-py"
readonly TOOL_VERSION="2.10.0"
readonly PACKAGE_NAME="tabula-py"

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
    local all_present=0

    # Check Python 3
    if command -v python3 >/dev/null 2>&1; then
        log "✓ Python 3 found: $(python3 --version 2>&1)"
    else
        log "✗ Python 3 not found"
        all_present=1
    fi

    # Check pip3
    if command -v pip3 >/dev/null 2>&1; then
        log "✓ pip3 found: $(pip3 --version 2>&1 | head -n1)"
    else
        log "✗ pip3 not found"
        all_present=1
    fi

    # Check Java
    if command -v java >/dev/null 2>&1; then
        log "✓ Java found: $(java -version 2>&1 | head -n1)"
    else
        log "✗ Java not found"
        all_present=1
    fi

    return $all_present
}

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update apt cache
    log "Updating apt cache..."
    apt-get update -qq

    # Install Python 3 and pip if missing
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Installing Python 3 and pip..."
        apt-get install -y python3 python3-pip python3-venv
    fi

    # Install Java Runtime Environment if missing
    if ! command -v java >/dev/null 2>&1; then
        log "Installing Java Runtime Environment..."
        apt-get install -y openjdk-11-jre-headless
    fi

    # Clean up apt cache
    log "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
    fi
    log "✓ Python 3 verified: $(python3 --version 2>&1)"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
    fi
    log "✓ pip3 verified: $(pip3 --version 2>&1 | head -n1)"

    # Verify Java
    if ! java -version >/dev/null 2>&1; then
        error "Java verification failed"
    fi
    log "✓ Java verified: $(java -version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Management
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Try to import tabula and check version
    if python3 -c "import tabula; print(tabula.__version__)" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(python3 -c "import tabula; print(tabula.__version__)" 2>/dev/null || echo "unknown")

        if [[ "$installed_version" == "$TOOL_VERSION" ]]; then
            log "✓ ${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, but need ${TOOL_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Install specific version using pip
    log "Running: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
    pip3 install --no-cache-dir "${PACKAGE_NAME}==${TOOL_VERSION}"

    log "${TOOL_NAME} installation completed"
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Run validation command
    local installed_version
    if ! installed_version=$(python3 -c "import tabula; print(tabula.__version__)" 2>&1); then
        error "Validation failed: Unable to import tabula module. Error: ${installed_version}"
    fi

    log "Installed version: ${installed_version}"

    # Check if version matches
    if [[ "$installed_version" != "$TOOL_VERSION" ]]; then
        error "Version mismatch: Expected ${TOOL_VERSION}, got ${installed_version}"
    fi

    log "✓ Validation successful: ${TOOL_NAME} ${TOOL_VERSION} is correctly installed"
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

# Execute main function
main "$@"
