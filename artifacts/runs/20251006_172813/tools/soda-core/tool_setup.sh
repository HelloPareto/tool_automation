#!/bin/bash
################################################################################
# Soda Core Installation Script
# Version: v3.5.6
# Package Manager: pip
# Description: Idempotent installation script for soda-core
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="soda-core"
readonly TOOL_VERSION="3.5.6"
readonly PYTHON_MIN_VERSION="3.7"

# Logging function with timestamps
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
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 &> /dev/null; then
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

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python 3 and pip if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python 3, pip, and venv..."
        apt-get install -y python3 python3-pip python3-venv

        # Clean up apt cache
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    else
        log "Python 3 and pip are already installed"
    fi
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        error "Python 3 verification failed"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python 3 verified: $python_version"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    # Check Python version meets minimum requirement
    local python_major
    local python_minor
    python_major=$(echo "$python_version" | cut -d. -f1)
    python_minor=$(echo "$python_version" | cut -d. -f2)

    local required_major
    local required_minor
    required_major=$(echo "$PYTHON_MIN_VERSION" | cut -d. -f1)
    required_minor=$(echo "$PYTHON_MIN_VERSION" | cut -d. -f2)

    if [ "$python_major" -lt "$required_major" ] || \
       { [ "$python_major" -eq "$required_major" ] && [ "$python_minor" -lt "$required_minor" ]; }; then
        error "Python version $python_version is below minimum required version $PYTHON_MIN_VERSION"
        exit 1
    fi

    log "Prerequisites verified successfully"
}

# Check if tool is already installed with correct version
check_existing_installation() {
    log "Checking for existing installation..."

    # Check using pip show
    if pip3 show soda-core &>/dev/null; then
        local installed_version
        installed_version=$(pip3 show soda-core | grep "^Version:" | awk '{print $2}')

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "$TOOL_NAME version $installed_version is already installed"
            return 0
        else
            log "$TOOL_NAME is installed but version is $installed_version (expected: $TOOL_VERSION)"
            return 1
        fi
    else
        log "$TOOL_NAME is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing $TOOL_NAME version $TOOL_VERSION..."

    # Upgrade pip to avoid potential issues
    log "Upgrading pip..."
    pip3 install --upgrade pip

    # Install soda-core with pinned version
    log "Installing $TOOL_NAME==$TOOL_VERSION via pip..."
    pip3 install "soda-core==$TOOL_VERSION"

    log "$TOOL_NAME installation completed"
}

# Validate the installation
validate() {
    log "Validating installation..."

    # Test that we can import the package
    if ! python3 -c "import soda.core" 2>/dev/null; then
        error "Failed to import soda.core package"
        exit 1
    fi
    log "Successfully imported soda.core package"

    # Verify version using pip show
    local validation_output
    if validation_output=$(pip3 show soda-core | grep "^Version:" | awk '{print $2}' 2>&1); then
        log "Installed version: $validation_output"

        # Check if the version matches
        if [ "$validation_output" = "$TOOL_VERSION" ]; then
            log "Validation successful: $TOOL_NAME version $validation_output"
            return 0
        else
            error "Version mismatch: expected $TOOL_VERSION, got $validation_output"
            exit 1
        fi
    else
        error "Validation failed: could not determine installed version"
        exit 1
    fi
}

# Main installation flow
main() {
    log "Starting $TOOL_NAME v$TOOL_VERSION installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation already complete, no changes needed"
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
