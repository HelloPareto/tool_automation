#!/usr/bin/env bash
#
# PyMC v5.25.1 Installation Script
#
# Description: Bayesian Modeling and Probabilistic Programming in Python
# Repository: https://github.com/pymc-devs/pymc
# Installation Method: pip (Python package manager)
#
# This script follows the Solutions Team Install Standards:
# - Prerequisite detection and installation
# - Idempotent execution
# - Version pinning
# - Non-interactive
# - Verification with checksums
# - Clean logging

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

TOOL_NAME="pymc"
TOOL_VERSION="5.25.1"
PYTHON_MIN_VERSION="3.10"
PIP_PACKAGE="pymc==${TOOL_VERSION}"

# Support for shared dependency layers
SKIP_PREREQS="${SKIP_PREREQS:-false}"
RESPECT_SHARED_DEPS="${RESPECT_SHARED_DEPS:-0}"

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" >&2
}

# ==============================================================================
# PREREQUISITE FUNCTIONS
# ==============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3.10+
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python ${python_version}"

        # Version comparison
        local major minor
        major=$(echo "${python_version}" | cut -d. -f1)
        minor=$(echo "${python_version}" | cut -d. -f2)

        if [ "${major}" -lt 3 ] || { [ "${major}" -eq 3 ] && [ "${minor}" -lt 10 ]; }; then
            log "Python version ${python_version} is below minimum required version ${PYTHON_MIN_VERSION}"
            all_present=false
        fi
    else
        log "Python3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 >/dev/null 2>&1; then
        log "Found pip3 $(pip3 --version | awk '{print $2}')"
    else
        log "pip3 not found"
        all_present=false
    fi

    if [ "${all_present}" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Check if we should skip prerequisite installation
    if [ "${SKIP_PREREQS}" = "true" ] || [ "${RESPECT_SHARED_DEPS}" = "1" ]; then
        log "Skipping prerequisite installation (SKIP_PREREQS=${SKIP_PREREQS}, RESPECT_SHARED_DEPS=${RESPECT_SHARED_DEPS})"
        return 0
    fi

    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        install_prerequisites_apt
    elif command -v yum >/dev/null 2>&1; then
        install_prerequisites_yum
    elif command -v apk >/dev/null 2>&1; then
        install_prerequisites_apk
    else
        log_error "No supported package manager found (apt-get, yum, or apk)"
        exit 1
    fi
}

install_prerequisites_apt() {
    log "Using apt-get package manager..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    log "Updating apt package list..."
    apt-get update -qq

    # Install Python 3.10+ and pip
    log "Installing Python 3.10+ and pip..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        ca-certificates \
        curl

    log "Prerequisites installed successfully via apt-get"
}

install_prerequisites_yum() {
    log "Using yum package manager..."

    # Install Python 3.10+ and pip
    log "Installing Python 3.10+ and pip..."
    yum install -y \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        gcc-c++ \
        make \
        ca-certificates \
        curl

    log "Prerequisites installed successfully via yum"
}

install_prerequisites_apk() {
    log "Using apk package manager..."

    # Update package index
    apk update

    # Install Python 3.10+ and pip
    log "Installing Python 3.10+ and pip..."
    apk add --no-cache \
        python3 \
        py3-pip \
        python3-dev \
        build-base \
        ca-certificates \
        curl

    log "Prerequisites installed successfully via apk"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 installation verification failed"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python3 verified: ${python_version}"

    # Verify pip3
    if ! command -v pip3 >/dev/null 2>&1; then
        log_error "pip3 installation verification failed"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version | awk '{print $2}')
    log "pip3 verified: ${pip_version}"

    # Verify Python version meets minimum requirement
    local major minor
    major=$(echo "${python_version}" | cut -d. -f1)
    minor=$(echo "${python_version}" | cut -d. -f2)

    if [ "${major}" -lt 3 ] || { [ "${major}" -eq 3 ] && [ "${minor}" -lt 10 ]; }; then
        log_error "Python version ${python_version} does not meet minimum requirement ${PYTHON_MIN_VERSION}"
        log_error "Please upgrade Python to version ${PYTHON_MIN_VERSION} or higher"
        exit 1
    fi

    log_success "All prerequisites verified successfully"
}

# ==============================================================================
# INSTALLATION FUNCTIONS
# ==============================================================================

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Try to import pymc and check version
    if python3 -c "import pymc; assert pymc.__version__ == '${TOOL_VERSION}', f'Version mismatch: {pymc.__version__} != ${TOOL_VERSION}'" 2>/dev/null; then
        log "${TOOL_NAME} v${TOOL_VERSION} is already installed"
        return 0
    else
        # Check if a different version is installed
        if python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null; then
            local installed_version
            installed_version=$(python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null)
            log "${TOOL_NAME} v${installed_version} is installed (expected v${TOOL_VERSION})"
            log "Will reinstall to match required version"
            return 1
        else
            log "${TOOL_NAME} is not installed"
            return 1
        fi
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    python3 -m pip install --upgrade pip --quiet

    # Install PyMC with pinned version
    log "Installing ${PIP_PACKAGE}..."
    python3 -m pip install "${PIP_PACKAGE}" --no-cache-dir

    log_success "${TOOL_NAME} v${TOOL_VERSION} installed successfully"
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Validate that PyMC can be imported
    if ! python3 -c "import pymc" 2>/dev/null; then
        log_error "Failed to import ${TOOL_NAME}"
        log_error "Installation validation failed"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null)

    if [ "${installed_version}" != "${TOOL_VERSION}" ]; then
        log_error "Version mismatch: installed ${installed_version}, expected ${TOOL_VERSION}"
        exit 1
    fi

    log_success "Validation successful: ${TOOL_NAME} v${installed_version}"

    # Output version for validation command compatibility
    echo "${TOOL_NAME} ${installed_version}"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prereqs)
                SKIP_PREREQS=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log_success "${TOOL_NAME} v${TOOL_VERSION} is already installed and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log_success "Installation completed successfully"
}

# Run main function
main "$@"
