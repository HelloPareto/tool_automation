#!/bin/bash
#
# Installation script for plotly v4.11.0
# This script installs the plotly Python package with CLI support
#
# Prerequisites: Python 3, pip
# Installation Method: pip package manager
#

set -euo pipefail

# Configuration
TOOL_NAME="plotly"
TOOL_VERSION="4.11.0"

# Logging function
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
    if command -v python3 &> /dev/null; then
        log "✓ Python3 is installed: $(python3 --version 2>&1)"
    else
        log "✗ Python3 is not installed"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 &> /dev/null; then
        log "✓ pip3 is installed: $(pip3 --version 2>&1 | head -n1)"
    else
        log "✗ pip3 is not installed"
        all_present=false
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are already installed"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update apt cache
    log "Updating apt cache..."
    apt-get update -qq

    # Install Python3 and pip3 if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python3 and pip3..."
        apt-get install -y python3 python3-pip python3-venv
    fi

    # Clean up apt cache
    log "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version &> /dev/null; then
        error "Python3 verification failed"
        exit 1
    fi
    log "✓ Python3 verified: $(python3 --version 2>&1)"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        exit 1
    fi
    log "✓ pip3 verified: $(pip3 --version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed (idempotency)
check_existing_installation() {
    log "Checking if ${TOOL_NAME} ${TOOL_VERSION} is already installed..."

    # Check if plotly module is installed
    if python3 -c "import plotly; print(plotly.__version__)" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import plotly; print(plotly.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, not ${TOOL_VERSION}"
            log "Will reinstall to ensure correct version"
            return 1
        fi
    fi

    log "${TOOL_NAME} is not installed"
    return 1
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Pin the specific version
    local package_spec="${TOOL_NAME}==${TOOL_VERSION}"

    log "Installing package: ${package_spec}"

    # Install using pip3 with --no-cache-dir for minimal image size
    # Using --force-reinstall to ensure correct version if already installed
    pip3 install --no-cache-dir --force-reinstall "${package_spec}"

    log "${TOOL_NAME} installation completed"
}

# Validate installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if plotly module can be imported and version is correct
    if ! python3 -c "import plotly; print(plotly.__version__)" &> /dev/null; then
        error "${TOOL_NAME} module cannot be imported"
        exit 1
    fi

    local installed_version
    installed_version=$(python3 -c "import plotly; print(plotly.__version__)" 2>/dev/null)

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
        exit 1
    fi

    log "✓ ${TOOL_NAME} version verified: ${installed_version}"

    # Note: plotly does not have a direct CLI command 'plotly --version'
    # The library is primarily used as a Python module
    # We validate by importing the module and checking the version
    log "✓ Validation successful: ${TOOL_NAME} ${TOOL_VERSION} is correctly installed"

    return 0
}

# Main installation flow
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
