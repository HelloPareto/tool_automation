#!/bin/bash

################################################################################
# Tool Installation Script: pdfminer
# Version: latest (pinned to 20231228)
# Description: PDF parser and text extraction tool
# Generated: 2025-01-06
################################################################################

set -euo pipefail

# Configuration
TOOL_NAME="pdfminer"
TOOL_VERSION="20231228"  # Latest stable version from pdfminer.six
VALIDATE_CMD="pdf2txt.py --version"
PYTHON_MIN_VERSION="3.8"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check pip
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

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    export DEBIAN_FRONTEND=noninteractive
    apt-get update

    # Install Python 3 and pip if not present
    if ! command -v python3 >/dev/null 2>&1; then
        log "Installing Python 3..."
        apt-get install -y python3 python3-pip python3-venv
    else
        log "Python 3 already installed, ensuring pip is available..."
        apt-get install -y python3-pip
    fi

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python 3 verified: $python_version"

    # Verify pip
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing installation..."

    # Check if pdf2txt.py command exists
    if command -v pdf2txt.py >/dev/null 2>&1; then
        log "Found existing pdfminer installation"

        # Try to get version using pip
        if pip3 show pdfminer.six >/dev/null 2>&1; then
            local installed_version
            installed_version=$(pip3 show pdfminer.six | grep "^Version:" | awk '{print $2}')
            log "Installed version: $installed_version"

            if [ "$installed_version" = "$TOOL_VERSION" ]; then
                log "Correct version already installed"
                return 0
            else
                log "Different version installed ($installed_version), will reinstall"
                return 1
            fi
        else
            log "Cannot determine version, will proceed with installation"
            return 1
        fi
    else
        log "pdfminer not found"
        return 1
    fi
}

install_tool() {
    log "Installing $TOOL_NAME version $TOOL_VERSION..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    pip3 install --no-cache-dir --upgrade pip

    # Install pdfminer.six with pinned version
    log "Installing pdfminer.six==$TOOL_VERSION..."
    pip3 install --no-cache-dir "pdfminer.six==$TOOL_VERSION"

    # Verify the binary is in PATH
    if ! command -v pdf2txt.py >/dev/null 2>&1; then
        # Try to find it in common locations
        local python_bin_dir
        python_bin_dir=$(python3 -c "import site; print(site.USER_BASE + '/bin')" 2>/dev/null || echo "/usr/local/bin")

        if [ -f "$python_bin_dir/pdf2txt.py" ]; then
            log "Found pdf2txt.py in $python_bin_dir"
            # Create symlink if needed
            if [ ! -L /usr/local/bin/pdf2txt.py ]; then
                ln -sf "$python_bin_dir/pdf2txt.py" /usr/local/bin/pdf2txt.py
            fi
        fi
    fi

    log "Installation completed"
}

validate() {
    log "Validating installation..."

    # Check if pdf2txt.py is available
    if ! command -v pdf2txt.py >/dev/null 2>&1; then
        error "Validation failed: pdf2txt.py command not found in PATH"
        error "Please ensure /usr/local/bin or Python's bin directory is in PATH"
        exit 1
    fi

    # Get version from pip
    if ! pip3 show pdfminer.six >/dev/null 2>&1; then
        error "Validation failed: pdfminer.six package not found"
        exit 1
    fi

    local installed_version
    installed_version=$(pip3 show pdfminer.six | grep "^Version:" | awk '{print $2}')

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Validation failed: Expected version $TOOL_VERSION, got $installed_version"
        exit 1
    fi

    log "Validation successful: pdfminer.six version $installed_version"

    # Test that the tool actually works
    if pdf2txt.py --version >/dev/null 2>&1 || pdf2txt.py -h >/dev/null 2>&1; then
        log "Tool execution test passed"
    else
        log "Note: pdf2txt.py may require additional arguments to run"
    fi

    return 0
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting $TOOL_NAME $TOOL_VERSION installation..."

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

# Execute main function
main "$@"
