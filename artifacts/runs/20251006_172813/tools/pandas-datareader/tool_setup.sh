#!/bin/bash
################################################################################
# pandas-datareader v0.10.0 Installation Script
#
# Description: Installs pandas-datareader Python package
# Version: v0.10.0
# Package Manager: pip
################################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Script constants
readonly TOOL_NAME="pandas-datareader"
readonly TOOL_VERSION="0.10.0"
readonly PYTHON_MIN_VERSION="3.6"

################################################################################
# Logging Functions
################################################################################

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check Python3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: ${python_version}"
    else
        log_warn "Python3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: ${pip_version}"
    else
        log_warn "pip3 not found"
        all_present=false
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log_warn "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"

            # Update package lists
            log "Updating package lists..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq

            # Install Python3 and pip3 if missing
            if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
                log "Installing Python3 and pip3..."
                apt-get install -y -qq python3 python3-pip python3-venv
            fi

            # Clean up
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            log "Prerequisites installed and cache cleaned"
            ;;
        centos|rhel|fedora)
            log "Detected RedHat-based system"
            if ! command -v python3 >/dev/null 2>&1; then
                yum install -y python3 python3-pip
            fi
            yum clean all
            ;;
        alpine)
            log "Detected Alpine system"
            if ! command -v python3 >/dev/null 2>&1; then
                apk add --no-cache python3 py3-pip
            fi
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
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
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: ${pip_version}"

    log "All prerequisites verified successfully"
    return 0
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import pandas_datareader" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pandas_datareader; print(pandas_datareader.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log_warn "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Will reinstall to match required version..."
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Upgrade pip to avoid potential issues
    log "Upgrading pip..."
    pip3 install --upgrade pip --quiet

    # Install specific version of pandas-datareader
    log "Installing ${TOOL_NAME}==${TOOL_VERSION}..."
    pip3 install "pandas-datareader==${TOOL_VERSION}" --quiet

    log "${TOOL_NAME} installation completed"
}

################################################################################
# Validation Function
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if module can be imported
    if ! python3 -c "import pandas_datareader" 2>/dev/null; then
        log_error "Failed to import pandas_datareader module"
        log_error "Validation failed - module cannot be imported"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import pandas_datareader; print(pandas_datareader.__version__)" 2>/dev/null || echo "unknown")

    if [ "$installed_version" = "$TOOL_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} ${installed_version} is correctly installed"
        return 0
    else
        log_error "Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
        log_error "Validation failed"
        exit 1
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."
    log "========================================================"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "========================================================"
        log "${TOOL_NAME} is already installed and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "========================================================"
    log "Installation completed successfully"
    log "${TOOL_NAME} ${TOOL_VERSION} is ready to use"
}

# Execute main function
main "$@"
