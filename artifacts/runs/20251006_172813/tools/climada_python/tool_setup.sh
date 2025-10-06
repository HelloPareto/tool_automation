#!/usr/bin/env bash
#
# Installation script for climada_python v6.1.0
# This script installs climada_python and all prerequisites
# It is idempotent and can be safely run multiple times
#

set -euo pipefail

# Script configuration
readonly TOOL_NAME="climada_python"
readonly TOOL_VERSION="v6.1.0"
readonly PACKAGE_NAME="climada"
readonly PACKAGE_VERSION="6.1.0"
# Note: The original validation command provided was incorrect as climada doesn't expose __version__
# Using importlib.metadata instead, which is the standard way to get package version
readonly VALIDATE_CMD="python3 -c 'import importlib.metadata; print(importlib.metadata.version(\"climada\"))'"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking for required prerequisites..."

    local all_present=0

    # Check for Python 3
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log "Python 3 is not installed"
        all_present=1
    fi

    # Check for pip3
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: $pip_version"
    else
        log "pip3 is not installed"
        all_present=1
    fi

    # Check for build essentials (required for some Python packages with C extensions)
    if command -v gcc &> /dev/null; then
        log "Found gcc (build tools available)"
    else
        log "Build tools (gcc) not found - may be needed for dependencies"
        all_present=1
    fi

    return $all_present
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update package lists
    if command -v apt-get &> /dev/null; then
        log "Updating apt package lists..."
        apt-get update -qq

        # Install Python 3 and pip if not present
        if ! command -v python3 &> /dev/null; then
            log "Installing Python 3..."
            apt-get install -y python3 python3-venv python3-dev
        fi

        # Install pip separately to ensure it's installed
        if ! command -v pip3 &> /dev/null; then
            log "Installing pip3..."
            apt-get install -y python3-pip
        fi

        # Install build essentials for compiling Python extensions
        if ! command -v gcc &> /dev/null; then
            log "Installing build-essential for compiling extensions..."
            apt-get install -y build-essential
        fi

        # Install additional system dependencies commonly needed by scientific Python packages
        log "Installing system dependencies for scientific Python packages..."
        # Note: Installing GDAL and scientific libraries required by climada
        apt-get install -y \
            gfortran \
            libgeos-dev \
            libproj-dev \
            libhdf5-dev \
            libnetcdf-dev \
            libgdal-dev \
            gdal-bin

        # Clean up apt cache
        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum &> /dev/null; then
        log "Using yum package manager..."

        if ! command -v python3 &> /dev/null; then
            log "Installing Python 3..."
            yum install -y python3 python3-pip python3-devel
        fi

        if ! command -v gcc &> /dev/null; then
            log "Installing development tools..."
            yum groupinstall -y "Development Tools"
        fi

        log "Installing system dependencies..."
        yum install -y \
            gcc-gfortran \
            geos-devel \
            proj-devel \
            hdf5-devel \
            netcdf-devel \
            gdal-devel

        yum clean all

    else
        error "No supported package manager found (apt-get or yum)"
        error "Please install Python 3, pip, and build-essential manually"
        exit 1
    fi

    # Upgrade pip to latest version
    log "Upgrading pip to latest version..."
    if command -v pip3 &> /dev/null; then
        python3 -m pip install --upgrade pip setuptools wheel
    else
        error "pip3 is still not available after installation attempt"
        exit 1
    fi
}

# Verify prerequisites are working
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

    # Verify gcc (non-critical, just log)
    if command -v gcc &> /dev/null; then
        local gcc_version
        gcc_version=$(gcc --version 2>&1 | head -n1 | awk '{print $NF}')
        log "gcc verified: $gcc_version"
    else
        log "Warning: gcc not found, but continuing..."
    fi

    log "All critical prerequisites verified successfully"
}

# Check if tool is already installed
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Try to import climada and get version using importlib.metadata
    if python3 -c "import importlib.metadata; print(importlib.metadata.version('climada'))" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('climada'))" 2>&1)

        if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
            log "${TOOL_NAME} version ${PACKAGE_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, but need version ${PACKAGE_VERSION}"
            log "Will proceed with installation/upgrade"
            return 1
        fi
    else
        log "${TOOL_NAME} is not currently installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # First, determine the GDAL version available on the system
    local gdal_version
    if command -v gdal-config &> /dev/null; then
        gdal_version=$(gdal-config --version 2>&1)
        log "System GDAL version: ${gdal_version}"

        # Install GDAL Python bindings matching the system GDAL version
        log "Installing GDAL Python bindings version ${gdal_version}..."
        python3 -m pip install --no-cache-dir "GDAL==${gdal_version}"
    fi

    # Install climada using pip with pinned version
    log "Running: pip3 install ${PACKAGE_NAME}==${PACKAGE_VERSION}"

    # Use --no-cache-dir to avoid caching issues and reduce size
    # Use --no-warn-script-location to suppress warnings about script locations
    python3 -m pip install --no-cache-dir "${PACKAGE_NAME}==${PACKAGE_VERSION}"

    log "${TOOL_NAME} installation completed"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Run the validation command
    log "Running validation command: ${VALIDATE_CMD}"

    # Capture the output and error for debugging
    local validation_output
    if ! validation_output=$(eval "${VALIDATE_CMD}" 2>&1); then
        error "Validation failed: Unable to import climada module"
        error "Import error details: ${validation_output}"
        error "Please check the installation logs above for errors"
        exit 1
    fi

    local installed_version
    installed_version=$(echo "${validation_output}" | tail -1)

    if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} version ${installed_version} is correctly installed"
    else
        error "Validation failed: Expected version ${PACKAGE_VERSION}, but found ${installed_version}"
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
    else
        log "All prerequisites are already installed"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation already complete, no action needed"
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
