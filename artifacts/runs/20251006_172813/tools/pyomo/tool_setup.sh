#!/bin/bash
# Pyomo 6.9.4 Installation Script
# Package Manager: binary_release
# Validation Command: python3 -c 'import pyomo; print(pyomo.__version__)'

set -euo pipefail

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Tool configuration
readonly TOOL_NAME="pyomo"
readonly TOOL_VERSION="6.9.4"
readonly VALIDATE_CMD="python3 -c 'import pyomo; print(pyomo.__version__)'"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log_warning "Python3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip3: $pip_version"
    else
        log_warning "pip3 not found"
        all_present=false
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log_warning "Some prerequisites are missing"
        return 1
    fi
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    if ! apt-get update; then
        log_error "Failed to update package lists"
        exit 1
    fi

    # Install Python3 and pip3 if not present
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Installing Python3 and pip3..."
        if ! apt-get install -y python3 python3-pip python3-venv; then
            log_error "Failed to install Python3 and pip3"
            exit 1
        fi
    fi

    # Clean up apt cache
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version >/dev/null 2>&1; then
        log_error "Python3 verification failed"
        exit 1
    fi

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        log_error "pip3 verification failed"
        exit 1
    fi

    log "All prerequisites verified successfully"
    log "Python version: $(python3 --version 2>&1)"
    log "pip3 version: $(pip3 --version 2>&1)"
}

# Check if tool is already installed
check_existing_installation() {
    log "Checking for existing $TOOL_NAME installation..."

    # Try to import pyomo and check version
    if python3 -c "import pyomo" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pyomo; print(pyomo.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "$TOOL_NAME $TOOL_VERSION is already installed"
            return 0
        else
            log_warning "$TOOL_NAME is installed but version is $installed_version (expected $TOOL_VERSION)"
            return 1
        fi
    else
        log "$TOOL_NAME is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing $TOOL_NAME $TOOL_VERSION..."

    # Upgrade pip to ensure compatibility
    log "Upgrading pip to latest version..."
    if ! pip3 install --upgrade pip >/dev/null 2>&1; then
        log_warning "Failed to upgrade pip, continuing with existing version"
    fi

    # Install pyomo with pinned version
    log "Installing pyomo==$TOOL_VERSION via pip..."
    if ! pip3 install "pyomo==$TOOL_VERSION"; then
        log_error "Failed to install $TOOL_NAME $TOOL_VERSION"
        log_error "This could be due to:"
        log_error "  - Network connectivity issues"
        log_error "  - PyPI availability"
        log_error "  - Python version compatibility"
        log_error "  - Missing system dependencies"
        exit 1
    fi

    log "$TOOL_NAME $TOOL_VERSION installed successfully"
}

# Validate the installation
validate() {
    log "Validating $TOOL_NAME installation..."

    # Run validation command
    local validation_output
    if validation_output=$(eval "$VALIDATE_CMD" 2>&1); then
        log "Validation successful"
        log "Installed version: $validation_output"

        # Verify version matches expected
        if [ "$validation_output" = "$TOOL_VERSION" ]; then
            log "Version verification passed: $validation_output"
            return 0
        else
            log_error "Version mismatch: expected $TOOL_VERSION, got $validation_output"
            exit 1
        fi
    else
        log_error "Validation failed"
        log_error "Command: $VALIDATE_CMD"
        log_error "Output: $validation_output"
        log_error "Troubleshooting steps:"
        log_error "  1. Check if Python can find the pyomo package"
        log_error "  2. Verify Python path and PYTHONPATH environment variables"
        log_error "  3. Try reinstalling with: pip3 install --force-reinstall pyomo==$TOOL_VERSION"
        exit 1
    fi
}

# Main installation flow
main() {
    log "Starting $TOOL_NAME $TOOL_VERSION installation..."
    log "Package Manager: binary_release (pip)"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "Installation already complete, nothing to do"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "Installation completed successfully"
}

# Execute main function
main "$@"
