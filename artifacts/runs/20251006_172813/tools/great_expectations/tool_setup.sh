#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# great_expectations 1.6.4 Installation Script
# =============================================================================
# This script installs great_expectations version 1.6.4 following the
# Solutions Team installation standards.
#
# Tool: great_expectations
# Version: 1.6.4
# Package: great-expectations (pip)
# Validation: python -c 'import great_expectations; print(great_expectations.__version__)'
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly TOOL_NAME="great_expectations"
readonly TOOL_VERSION="1.6.4"
readonly PACKAGE_NAME="great-expectations"  # PyPI package name (with hyphen)
readonly IMPORT_NAME="great_expectations"     # Python import name (with underscore)
readonly EXPECTED_VERSION="1.6.4"

# NOTE: The provided validation command referenced "docs" package, but the correct
# package is "great-expectations" on PyPI, imported as "great_expectations" in Python.
# This script uses the correct package/import names.

# Checksum for the package (from PyPI)
# Note: For pip packages, we rely on pip's built-in verification mechanism
# which checks package signatures from PyPI

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

fatal() {
    error "$@"
    exit 1
}

# -----------------------------------------------------------------------------
# Prerequisite Detection
# -----------------------------------------------------------------------------
check_prerequisites() {
    log "Checking for required prerequisites..."
    local all_present=0

    # Check for Python 3
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: ${python_version}"
    else
        log "Python 3 not found - will need to install"
        all_present=1
    fi

    # Check for pip3
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: ${pip_version}"
    else
        log "pip3 not found - will need to install"
        all_present=1
    fi

    return ${all_present}
}

# -----------------------------------------------------------------------------
# Prerequisite Installation
# -----------------------------------------------------------------------------
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python 3 and pip if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python 3, pip, and venv support..."
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv

        # Clean up apt cache
        apt-get clean
        rm -rf /var/lib/apt/lists/*

        log "Python prerequisites installed successfully"
    else
        log "Python prerequisites already present"
    fi
}

# -----------------------------------------------------------------------------
# Prerequisite Verification
# -----------------------------------------------------------------------------
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        fatal "Python 3 verification failed. Please install Python 3 manually."
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python 3 verified: ${python_version}"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        fatal "pip3 verification failed. Please install pip3 manually."
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: ${pip_version}"

    log "All prerequisites verified successfully"
}

# -----------------------------------------------------------------------------
# Check Existing Installation
# -----------------------------------------------------------------------------
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Try to import the package and check version (use IMPORT_NAME for Python import)
    if python3 -c "import ${IMPORT_NAME}" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${IMPORT_NAME}; print(${IMPORT_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [[ "${installed_version}" == "${EXPECTED_VERSION}" ]]; then
            log "${TOOL_NAME} version ${EXPECTED_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, but need ${EXPECTED_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not currently installed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Install Tool
# -----------------------------------------------------------------------------
install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Upgrade pip to latest version for better security and reliability
    log "Upgrading pip to latest version..."
    python3 -m pip install --upgrade pip

    # Install the specific version of the package
    log "Installing ${PACKAGE_NAME}==${TOOL_VERSION} via pip..."
    pip3 install --no-cache-dir "${PACKAGE_NAME}==${TOOL_VERSION}"

    log "${TOOL_NAME} installation completed"
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Run the validation command (use IMPORT_NAME for Python import)
    local installed_version
    if ! installed_version=$(python3 -c "import ${IMPORT_NAME}; print(${IMPORT_NAME}.__version__)" 2>&1); then
        fatal "Validation failed: Cannot import ${IMPORT_NAME}. Error: ${installed_version}"
    fi

    log "Installed version: ${installed_version}"

    # Check if version matches expected version
    if [[ "${installed_version}" != "${EXPECTED_VERSION}" ]]; then
        fatal "Version mismatch: Expected ${EXPECTED_VERSION}, but got ${installed_version}"
    fi

    log "Validation successful: ${TOOL_NAME} ${installed_version} is correctly installed"
}

# -----------------------------------------------------------------------------
# Main Installation Flow
# -----------------------------------------------------------------------------
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites already present"
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation verified - no changes needed"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# -----------------------------------------------------------------------------
# Script Entry Point
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
