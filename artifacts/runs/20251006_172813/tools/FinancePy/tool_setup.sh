#!/bin/bash
set -euo pipefail

# FinancePy V0.360 Installation Script
# This script installs FinancePy version V0.360 following Solutions Team standards

# Constants
TOOL_NAME="FinancePy"
TOOL_VERSION="V0.360"
PACKAGE_NAME="financepy"
# Note: PyPI uses version 0.360 without the V prefix
PIP_VERSION="0.360"

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

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python 3 and pip
    log "Installing Python 3 and pip..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv

    # Clean up to minimize image size
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        exit 1
    fi
    log "Python 3 verified: $(python3 --version 2>&1)"

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        exit 1
    fi
    log "pip3 verified: $(pip3 --version 2>&1)"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed (idempotency)
check_existing_installation() {
    log "Checking if ${TOOL_NAME} is already installed..."

    if python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${PACKAGE_NAME}; print(${PACKAGE_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$PIP_VERSION" ]; then
            log "${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is $installed_version (expected ${PIP_VERSION})"
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
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Upgrade pip to ensure compatibility
    log "Upgrading pip..."
    pip3 install --upgrade pip

    # Install specific version of financepy
    log "Installing ${PACKAGE_NAME}==${PIP_VERSION}..."
    pip3 install --no-cache-dir "${PACKAGE_NAME}==${PIP_VERSION}"

    log "${TOOL_NAME} installed successfully"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if package can be imported (suppressing the banner)
    if ! python3 -c "import ${PACKAGE_NAME}" >/dev/null 2>&1; then
        error "Failed to import ${PACKAGE_NAME}"
        error "Validation failed: ${TOOL_NAME} is not properly installed"
        exit 1
    fi

    # Check version using pip show (more reliable than importing since FinancePy prints a banner)
    local installed_version
    installed_version=$(pip3 show "${PACKAGE_NAME}" 2>/dev/null | grep "^Version:" | awk '{print $2}' | tr -d '[:space:]')

    if [ "$installed_version" = "$PIP_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} version ${installed_version} is correctly installed"
        return 0
    else
        error "Version mismatch: expected ${PIP_VERSION}, got '${installed_version}'"
        error "Validation failed"
        exit 1
    fi
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
        log "Installation already complete and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# Run main function
main
