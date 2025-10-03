#!/bin/bash
#
# Installation script for statsforecast (referred to as statsforecas in specs)
# Version: 2.0.2 (latest as of 2025-07-05)
# Package Manager: pip
# Validation: statsforecas --version (with Python fallback)
#
# This script follows Solutions Team Install Standards:
# - Idempotent installation
# - Version pinning
# - Non-interactive
# - Verification included
# - Clean up after installation

set -euo pipefail

# Configuration
readonly TOOL_NAME="statsforecast"
readonly TOOL_VERSION="2.0.2"
readonly PYTHON_MIN_VERSION="3.8"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if Python 3 is installed
check_python() {
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed"
        error "Please install Python 3.${PYTHON_MIN_VERSION} or higher"
        return 1
    fi

    local python_version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log "Found Python ${python_version}"

    # Check minimum version
    if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)"; then
        error "Python ${python_version} is too old. Minimum required: ${PYTHON_MIN_VERSION}"
        return 1
    fi
}

# Check if pip is installed
check_pip() {
    if ! python3 -m pip --version &> /dev/null; then
        error "pip is not installed"
        error "Installing pip..."

        # Install pip
        if command -v apt-get &> /dev/null; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq python3-pip
            apt-get clean
            rm -rf /var/lib/apt/lists/*
        elif command -v yum &> /dev/null; then
            yum install -y -q python3-pip
            yum clean all
        else
            error "Unable to install pip automatically. Please install pip manually."
            return 1
        fi
    fi
    log "pip is available"
}

# Check if tool is already installed with correct version
is_installed() {
    if python3 -c "import ${TOOL_NAME}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${TOOL_NAME}; print(${TOOL_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [[ "${installed_version}" == "${TOOL_VERSION}" ]]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            return 1
        fi
    fi
    return 1
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Install with pinned version
    python3 -m pip install --no-cache-dir "${TOOL_NAME}==${TOOL_VERSION}"

    log "Installation complete"
}

# Validate installation
validate() {
    log "Validating installation..."

    # First, try the specified validation command (statsforecas --version)
    # Note: statsforecast is a Python library, not a CLI tool, so this may fail
    if command -v statsforecas &> /dev/null; then
        log "Found statsforecas CLI command"
        if statsforecas --version &> /dev/null; then
            log "Validation successful using CLI command"
            return 0
        fi
    fi

    # Fallback: Validate using Python import and version check
    log "Validating using Python import..."

    if ! python3 -c "import ${TOOL_NAME}" 2>/dev/null; then
        error "Failed to import ${TOOL_NAME}"
        error "Installation validation failed"
        return 1
    fi

    local installed_version
    installed_version=$(python3 -c "import ${TOOL_NAME}; print(${TOOL_NAME}.__version__)" 2>/dev/null)

    if [[ "${installed_version}" != "${TOOL_VERSION}" ]]; then
        error "Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
        return 1
    fi

    log "Validation successful: ${TOOL_NAME} version ${installed_version} is installed"
    return 0
}

# Main installation flow
main() {
    log "Starting installation of ${TOOL_NAME} version ${TOOL_VERSION}"

    # Check prerequisites
    check_python || exit 1
    check_pip || exit 1

    # Check if already installed (idempotency)
    if is_installed; then
        log "Tool is already installed with correct version"
        validate
        exit 0
    fi

    # Install the tool
    install_tool

    # Validate installation
    if ! validate; then
        error "Installation validation failed"
        error "Please check the logs above for details"
        exit 1
    fi

    log "Installation completed successfully"
}

# Run main function
main "$@"
