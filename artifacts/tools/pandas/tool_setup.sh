#!/usr/bin/env bash
#
# Installation script for pandas v2.3.3
# This script installs pandas using pip with pinned version
# Idempotent: Safe to run multiple times
#

set -euo pipefail

# Configuration
TOOL_NAME="pandas"
TOOL_VERSION="2.2.3"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Validation function
validate() {
    log "Validating ${TOOL_NAME} installation..."

    if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        error "Python is not installed. Please install Python 3.8 or higher."
        return 1
    fi

    # Use python3 if available, otherwise python
    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        python_cmd="python"
    fi

    # Check if pandas is installed and get version
    if ! ${python_cmd} -c "import pandas" >/dev/null 2>&1; then
        error "${TOOL_NAME} is not installed"
        return 1
    fi

    local installed_version
    installed_version=$(${python_cmd} -c 'import pandas; print(pandas.__version__)' 2>/dev/null || echo "")

    if [[ -z "${installed_version}" ]]; then
        error "Failed to retrieve ${TOOL_NAME} version"
        return 1
    fi

    if [[ "${installed_version}" != "${TOOL_VERSION}" ]]; then
        error "Version mismatch: expected ${TOOL_VERSION}, found ${installed_version}"
        return 1
    fi

    log "✓ ${TOOL_NAME} ${installed_version} is correctly installed"
    return 0
}

# Check if already installed with correct version
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        if command -v python >/dev/null 2>&1; then
            python_cmd="python"
        else
            return 1
        fi
    fi

    if ${python_cmd} -c "import pandas" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(${python_cmd} -c 'import pandas; print(pandas.__version__)' 2>/dev/null || echo "")

        if [[ "${installed_version}" == "${TOOL_VERSION}" ]]; then
            log "✓ ${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, will reinstall ${TOOL_VERSION}"
            return 1
        fi
    fi

    return 1
}

# Install Python if not available
install_python() {
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        log "Python is already installed"
        return 0
    fi

    log "Installing Python..."

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip python3-venv >/dev/null
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q python3 python3-pip
        yum clean all
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache python3 py3-pip
    else
        error "No supported package manager found. Please install Python 3.8 or higher manually."
        return 1
    fi

    log "✓ Python installed successfully"
    return 0
}

# Install pandas using pip
install_pandas() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        python_cmd="python"
    fi

    # Ensure pip is available
    if ! ${python_cmd} -m pip --version >/dev/null 2>&1; then
        log "Installing pip..."
        if command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq python3-pip >/dev/null
            apt-get clean
            rm -rf /var/lib/apt/lists/*
        else
            error "pip is not available. Please install pip manually."
            return 1
        fi
    fi

    # Upgrade pip to latest version for better dependency resolution
    log "Ensuring pip is up to date..."
    ${python_cmd} -m pip install --quiet --upgrade pip

    # Install pandas with pinned version
    # Using --no-cache-dir to avoid caching and reduce disk usage
    # Using --upgrade to ensure we get the exact version even if another version is installed
    log "Installing pandas==${TOOL_VERSION} via pip..."
    ${python_cmd} -m pip install --no-cache-dir --upgrade "pandas==${TOOL_VERSION}"

    log "✓ ${TOOL_NAME} ${TOOL_VERSION} installed successfully"
    return 0
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        exit $?
    fi

    # Install Python if needed
    if ! install_python; then
        error "Failed to install Python"
        exit 1
    fi

    # Install pandas
    if ! install_pandas; then
        error "Failed to install ${TOOL_NAME}"
        error "Troubleshooting steps:"
        error "  1. Ensure Python 3.8 or higher is installed"
        error "  2. Check internet connectivity"
        error "  3. Verify pip is working: python3 -m pip --version"
        error "  4. Try manual installation: pip install pandas==${TOOL_VERSION}"
        exit 1
    fi

    # Validate installation
    if ! validate; then
        error "Installation completed but validation failed"
        error "Please check the installation manually"
        exit 1
    fi

    log "✓ ${TOOL_NAME} ${TOOL_VERSION} installation completed successfully"
    exit 0
}

# Run main function
main "$@"
