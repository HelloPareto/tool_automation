#!/bin/bash

##############################################################################
# data-link-python Installation Script
# Tool: data-link-python
# Version: 1.0.4
# Package Manager: pip
# Description: Installs Nasdaq Data Link Python library
##############################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Tool details
readonly TOOL_NAME="data-link-python"
readonly TOOL_VERSION="1.0.4"
readonly PACKAGE_NAME="nasdaq-data-link"

##############################################################################
# Logging Functions
##############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

##############################################################################
# Prerequisite Management
##############################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python 3: version ${python_version}"
    else
        log_warn "Python 3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip3: version ${pip_version}"
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

    # Update package lists
    log "Updating package lists..."
    if command -v apt-get &> /dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        # Install Python 3 and pip if not present
        if ! command -v python3 &> /dev/null; then
            log "Installing Python 3..."
            apt-get install -y python3
        fi

        if ! command -v pip3 &> /dev/null; then
            log "Installing pip3..."
            apt-get install -y python3-pip
        fi

        # Clean up
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum &> /dev/null; then
        # RHEL/CentOS
        if ! command -v python3 &> /dev/null; then
            log "Installing Python 3..."
            yum install -y python3
        fi

        if ! command -v pip3 &> /dev/null; then
            log "Installing pip3..."
            yum install -y python3-pip
        fi

        yum clean all

    else
        log_error "Unsupported package manager. Please install Python 3 and pip3 manually."
        exit 1
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 installation verification failed"
        log_error "Python 3 is required but was not successfully installed"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1)
    log "Python 3 verified: ${python_version}"

    # Verify pip3
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 installation verification failed"
        log_error "pip3 is required but was not successfully installed"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1)
    log "pip3 verified: ${pip_version}"

    log "All prerequisites verified successfully"
}

##############################################################################
# Installation Functions
##############################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if the package is already installed with the correct version
    if pip3 show "${PACKAGE_NAME}" &> /dev/null; then
        local installed_version
        installed_version=$(pip3 show "${PACKAGE_NAME}" | grep "^Version:" | awk '{print $2}')

        if [ "${installed_version}" = "${TOOL_VERSION}" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log_warn "${TOOL_NAME} version ${installed_version} is installed, but version ${TOOL_VERSION} is required"
            log "Upgrading to version ${TOOL_VERSION}..."
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Install the specific version using pip
    log "Running: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"

    if pip3 install "${PACKAGE_NAME}==${TOOL_VERSION}" --quiet --no-cache-dir; then
        log "${TOOL_NAME} installed successfully"
    else
        log_error "Failed to install ${TOOL_NAME}"
        log_error "Command failed: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
        log_error "Please check your internet connection and try again"
        exit 1
    fi
}

##############################################################################
# Validation Function
##############################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Try to import the module and print version
    local validation_output
    if validation_output=$(python3 -c "import nasdaqdatalink; print(nasdaqdatalink.version.VERSION)" 2>&1); then
        local installed_version="${validation_output}"

        if [ "${installed_version}" = "${TOOL_VERSION}" ]; then
            log "Validation successful: ${TOOL_NAME} version ${installed_version}"
            return 0
        else
            log_error "Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
            exit 1
        fi
    else
        log_error "Validation failed: unable to import nasdaqdatalink module"
        log_error "Output: ${validation_output}"
        exit 1
    fi
}

##############################################################################
# Main Function
##############################################################################

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
        log "Installation completed successfully (already installed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

##############################################################################
# Script Entry Point
##############################################################################

main "$@"
