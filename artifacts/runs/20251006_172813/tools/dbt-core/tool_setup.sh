#!/bin/bash

# dbt-core v1.11.0b2 Installation Script
# This script installs dbt-core with all prerequisites
# Follows Solutions Team Install Standards

set -euo pipefail

# Configuration
TOOL_NAME="dbt-core"
TOOL_VERSION="1.11.0b2"
PYTHON_MIN_VERSION="3.8"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if Python meets minimum version requirement
check_python_version() {
    local version=$1
    local required=$2

    # Convert version strings to comparable integers
    local version_int
    version_int=$(echo "$version" | awk -F. '{printf "%d%02d%02d", $1, $2, $3}')
    local required_int
    required_int=$(echo "$required.0" | awk -F. '{printf "%d%02d%02d", $1, $2, $3}')

    [ "$version_int" -ge "$required_int" ]
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Python3
    if command -v python3 &> /dev/null; then
        local py_version
        py_version=$(python3 --version 2>&1 | awk '{print $2}')
        if check_python_version "$py_version" "$PYTHON_MIN_VERSION"; then
            log "✓ Python3 found: $py_version (>= $PYTHON_MIN_VERSION required)"
        else
            log "✗ Python3 version $py_version is too old (>= $PYTHON_MIN_VERSION required)"
            all_present=false
        fi
    else
        log "✗ Python3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "✓ pip3 found: $pip_version"
    else
        log "✗ pip3 not found"
        all_present=false
    fi

    # Check for venv module
    if python3 -c "import venv" &> /dev/null; then
        log "✓ Python venv module available"
    else
        log "✗ Python venv module not found"
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
    export DEBIAN_FRONTEND=noninteractive
    apt-get update

    # Install Python3, pip, and venv if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python3 and pip..."
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv \
            python3-dev \
            build-essential
    else
        # Ensure venv and dev packages are installed
        log "Ensuring Python development packages are installed..."
        apt-get install -y \
            python3-venv \
            python3-dev \
            build-essential
    fi

    # Upgrade pip to latest version
    log "Upgrading pip to latest version..."
    python3 -m pip install --upgrade pip

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version &> /dev/null; then
        error "Python3 verification failed"
        exit 1
    fi
    local py_version
    py_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "✓ Python3 verified: $py_version"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "✓ pip3 verified: $pip_version"

    # Verify venv
    if ! python3 -c "import venv" &> /dev/null; then
        error "Python venv module verification failed"
        exit 1
    fi
    log "✓ Python venv module verified"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed
check_existing_installation() {
    log "Checking for existing installation..."

    # Try to import dbt_core and check version
    if python3 -c "import dbt.version; print(dbt.version.__version__)" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import dbt.version; print(dbt.version.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "✓ $TOOL_NAME version $TOOL_VERSION is already installed"
            return 0
        else
            log "✗ Different version found: $installed_version (expected: $TOOL_VERSION)"
            return 1
        fi
    else
        log "✗ $TOOL_NAME is not installed"
        return 1
    fi
}

# Install dbt-core
install_tool() {
    log "Installing $TOOL_NAME version $TOOL_VERSION..."

    # Install dbt-core with pinned version
    # Using --no-cache-dir to reduce disk space usage
    log "Running: pip3 install dbt-core==$TOOL_VERSION"
    pip3 install --no-cache-dir "dbt-core==$TOOL_VERSION"

    log "$TOOL_NAME installation completed"
}

# Validate installation
validate() {
    log "Validating installation..."

    # Run the validation command
    if ! python3 -c "import dbt.version; print(dbt.version.__version__)" &> /dev/null; then
        error "Validation failed: Cannot import dbt.version module"
        error "Please check if dbt-core was installed correctly"
        exit 1
    fi

    local installed_version
    installed_version=$(python3 -c "import dbt.version; print(dbt.version.__version__)")

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Validation failed: Version mismatch"
        error "Expected: $TOOL_VERSION"
        error "Got: $installed_version"
        exit 1
    fi

    log "✓ Validation successful: $TOOL_NAME version $installed_version"

    # Additional validation: Check if dbt command is available
    if command -v dbt &> /dev/null; then
        local dbt_cmd_version
        dbt_cmd_version=$(dbt --version 2>&1 | grep -i "core" | awk '{print $NF}' || echo "unknown")
        log "✓ dbt command available: $dbt_cmd_version"
    else
        log "⚠ Warning: dbt command not found in PATH, but Python module is correctly installed"
    fi
}

# Main installation flow
main() {
    log "Starting $TOOL_NAME v$TOOL_VERSION installation..."
    log "==========================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "==========================================="
        log "Installation already complete (idempotent check passed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "==========================================="
    log "Installation completed successfully"
}

# Run main function
main
