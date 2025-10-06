#!/usr/bin/env bash

################################################################################
# xclim v0.58.1 Installation Script
#
# This script installs xclim v0.58.1 following Solutions Team standards:
# - Detects and installs prerequisites (Python 3, pip)
# - Idempotent: safe to run multiple times
# - Version pinned: specifically installs v0.58.1
# - Non-interactive: no user prompts
# - Validates installation
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="xclim"
readonly TOOL_VERSION="0.58.1"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking for prerequisites..."
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
        log "Found pip: $pip_version"
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

# Install missing prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package list
    log "Updating package list..."
    apt-get update

    # Install Python 3 and pip if not present
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Installing Python 3 and pip..."
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv \
            python3-dev
    fi

    # Install build tools for compiling Python extensions
    if ! command -v gcc >/dev/null 2>&1; then
        log "Installing build-essential for Python extensions..."
        apt-get install -y build-essential
    fi

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Verified Python: $python_version"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "Verified pip: $pip_version"

    # Verify gcc (for building extensions)
    if command -v gcc >/dev/null 2>&1; then
        local gcc_version
        gcc_version=$(gcc --version 2>&1 | head -n1)
        log "Verified gcc: $gcc_version"
    fi

    log "All prerequisites verified successfully"
}

# Check if tool is already installed at the correct version
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import xclim" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import xclim; print(xclim.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} v${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is $installed_version (expected: $TOOL_VERSION)"
            log "Will reinstall to ensure correct version"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    python3 -m pip install --upgrade pip

    # Install xclim with pinned version
    log "Installing ${TOOL_NAME}==${TOOL_VERSION}..."
    pip3 install --no-cache-dir "xclim==${TOOL_VERSION}"

    log "${TOOL_NAME} installation completed"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if module can be imported
    if ! python3 -c "import xclim" 2>/dev/null; then
        error "Failed to import ${TOOL_NAME}"
        error "Validation failed"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import xclim; print(xclim.__version__)" 2>/dev/null)

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
        error "Validation failed"
        exit 1
    fi

    log "Validation successful: ${TOOL_NAME} v${installed_version}"
    return 0
}

# Main installation flow
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
