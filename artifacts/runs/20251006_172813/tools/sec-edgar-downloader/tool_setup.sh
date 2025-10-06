#!/usr/bin/env bash

# sec-edgar-downloader 5.0.3 Installation Script
# Installs sec-edgar-downloader Python package with proper prerequisite handling
# Follows Solutions Team Install Standards

set -euo pipefail

# Configuration
readonly TOOL_NAME="sec-edgar-downloader"
readonly TOOL_VERSION="5.0.3"
readonly PACKAGE_NAME="sec-edgar-downloader"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking for required prerequisites..."

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
        log "All prerequisites are already installed"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        log "Using apt-get package manager"
        export DEBIAN_FRONTEND=noninteractive

        # Update package lists
        log "Updating package lists..."
        apt-get update || error "Failed to update package lists"

        # Install Python 3 and pip
        log "Installing Python 3 and pip..."
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv \
            python3-dev \
            || error "Failed to install Python prerequisites"

        # Clean up
        log "Cleaning up package manager cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum &> /dev/null; then
        log "Using yum package manager"

        # Install Python 3 and pip
        log "Installing Python 3 and pip..."
        yum install -y python3 python3-pip python3-devel || error "Failed to install Python prerequisites"

        # Clean up
        log "Cleaning up package manager cache..."
        yum clean all

    elif command -v apk &> /dev/null; then
        log "Using apk package manager"

        # Update package lists
        log "Updating package lists..."
        apk update || error "Failed to update package lists"

        # Install Python 3 and pip
        log "Installing Python 3 and pip..."
        apk add --no-cache python3 py3-pip python3-dev || error "Failed to install Python prerequisites"

    else
        error "No supported package manager found (apt-get, yum, or apk). Please install Python 3 and pip manually."
    fi

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! command -v python3 &> /dev/null; then
        error "Python 3 verification failed: python3 command not found after installation"
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python 3 verified: $python_version"

    # Verify pip3
    if ! command -v pip3 &> /dev/null; then
        error "pip3 verification failed: pip3 command not found after installation"
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    # Ensure pip is up to date
    log "Upgrading pip to latest version..."
    pip3 install --upgrade pip || log "Warning: Failed to upgrade pip, continuing with existing version"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed (idempotency)
check_existing_installation() {
    log "Checking for existing installation of $TOOL_NAME..."

    # Try to import the module and check version
    if python3 -c "import sec_edgar_downloader; print(sec_edgar_downloader.__version__)" 2>/dev/null | grep -q "$TOOL_VERSION"; then
        log "$TOOL_NAME $TOOL_VERSION is already installed"
        return 0
    elif python3 -c "import sec_edgar_downloader" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import sec_edgar_downloader; print(sec_edgar_downloader.__version__)" 2>/dev/null || echo "unknown")
        log "$TOOL_NAME is installed but version is $installed_version (expected $TOOL_VERSION)"
        log "Will reinstall to match required version"
        return 1
    else
        log "$TOOL_NAME is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing $TOOL_NAME $TOOL_VERSION..."

    # Install using pip with pinned version
    log "Running: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
    pip3 install "${PACKAGE_NAME}==${TOOL_VERSION}" || error "Failed to install $TOOL_NAME $TOOL_VERSION"

    log "$TOOL_NAME installation completed"
}

# Validate the installation
validate() {
    log "Validating $TOOL_NAME installation..."

    # Run the validation command
    local validation_output
    validation_output=$(python3 -c 'import sec_edgar_downloader; print(sec_edgar_downloader.__version__)' 2>&1) || error "Validation command failed: Unable to import sec_edgar_downloader"

    # Check if the output matches the expected version
    if echo "$validation_output" | grep -q "$TOOL_VERSION"; then
        log "Validation successful: $TOOL_NAME $TOOL_VERSION is correctly installed"
        log "Installed version: $validation_output"
        return 0
    else
        error "Validation failed: Expected version $TOOL_VERSION but got $validation_output"
    fi
}

# Main installation flow
main() {
    log "Starting $TOOL_NAME $TOOL_VERSION installation..."
    log "=========================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "=========================================="
        log "Installation completed successfully (already installed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "Installation completed successfully"
}

# Run main function
main "$@"
