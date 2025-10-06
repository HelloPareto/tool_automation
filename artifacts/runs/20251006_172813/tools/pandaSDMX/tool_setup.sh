#!/bin/bash
# pandaSDMX Installation Script
# Version: 1.6.0
# Package Manager: pip
# Description: Installs pandaSDMX, a Python library for SDMX data access

set -euo pipefail

# Configuration
TOOL_NAME="pandasdmx"
TOOL_VERSION="1.6.0"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking for required prerequisites..."
    local all_present=true

    if ! command -v python3 &> /dev/null; then
        log "Python3 is not installed"
        all_present=false
    else
        log "Python3 found: $(python3 --version)"
    fi

    if ! command -v pip3 &> /dev/null; then
        log "pip3 is not installed"
        all_present=false
    else
        log "pip3 found: $(pip3 --version)"
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

    # Detect OS
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"
            export DEBIAN_FRONTEND=noninteractive

            log "Updating package lists..."
            apt-get update -qq

            log "Installing Python3 and pip3..."
            apt-get install -y python3 python3-pip python3-venv python3-dev

            log "Cleaning up apt cache..."
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;
        centos|rhel|fedora)
            log "Detected Red Hat based system"
            log "Installing Python3 and pip3..."
            yum install -y python3 python3-pip python3-devel
            yum clean all
            ;;
        alpine)
            log "Detected Alpine Linux"
            log "Installing Python3 and pip3..."
            apk add --no-cache python3 py3-pip python3-dev
            ;;
        *)
            error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    if ! python3 --version &> /dev/null; then
        error "Python3 verification failed. Python3 is not working correctly."
        exit 1
    fi

    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed. pip3 is not working correctly."
        exit 1
    fi

    log "Python3 version: $(python3 --version)"
    log "pip3 version: $(pip3 --version)"
    log "Prerequisites verified successfully"
}

# Check if tool is already installed
check_existing_installation() {
    log "Checking if ${TOOL_NAME} is already installed..."

    if python3 -c "import pandasdmx" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pandasdmx; print(pandasdmx.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Proceeding with installation to ensure correct version..."
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    python3 -m pip install --upgrade pip --quiet

    # Install the specific version of pandasdmx
    log "Installing ${TOOL_NAME}==${TOOL_VERSION}..."
    python3 -m pip install "${TOOL_NAME}==${TOOL_VERSION}" --no-cache-dir

    log "${TOOL_NAME} installation completed"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    if ! python3 -c "import pandasdmx" &> /dev/null; then
        error "Validation failed: Cannot import pandasdmx module"
        error "Remediation: Check Python environment and reinstall with: pip3 install ${TOOL_NAME}==${TOOL_VERSION}"
        exit 1
    fi

    local installed_version
    installed_version=$(python3 -c 'import pandasdmx; print(pandasdmx.__version__)' 2>/dev/null || echo "")

    if [ -z "$installed_version" ]; then
        error "Validation failed: Cannot determine installed version"
        error "Remediation: Reinstall the package with: pip3 install ${TOOL_NAME}==${TOOL_VERSION}"
        exit 1
    fi

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Validation failed: Version mismatch"
        error "Expected: ${TOOL_VERSION}, Got: ${installed_version}"
        error "Remediation: Reinstall with: pip3 install ${TOOL_NAME}==${TOOL_VERSION} --force-reinstall"
        exit 1
    fi

    log "Validation successful: ${TOOL_NAME} version ${installed_version} is correctly installed"
    return 0
}

# Main installation workflow
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
        log "Installation verified - ${TOOL_NAME} ${TOOL_VERSION} is already present and working"
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
