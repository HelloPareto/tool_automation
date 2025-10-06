#!/bin/bash

# SALib v1.4.7 Installation Script
# This script installs SALib (Sensitivity Analysis Library) v1.4.7
# Following Solutions Team Install Standards

set -euo pipefail

# Configuration
readonly TOOL_NAME="SALib"
readonly TOOL_VERSION="v1.4.7"
readonly PACKAGE_VERSION="1.4.7"
readonly PACKAGE_NAME="SALib"
readonly VALIDATE_CMD="python3 -c 'import SALib; print(SALib.__version__)'"

# Logging function
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
        log "✓ Python 3 found: $(python3 --version)"
    else
        log "✗ Python 3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 &> /dev/null; then
        log "✓ pip3 found: $(pip3 --version)"
    else
        log "✗ pip3 not found"
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

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect OS"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"
            export DEBIAN_FRONTEND=noninteractive

            # Update package lists
            log "Updating package lists..."
            apt-get update

            # Install Python 3 and pip if not present
            if ! command -v python3 &> /dev/null; then
                log "Installing Python 3..."
                apt-get install -y python3
            fi

            if ! command -v pip3 &> /dev/null; then
                log "Installing pip3..."
                apt-get install -y python3-pip
            fi

            # Install build tools for Python packages that may need compilation
            if ! dpkg -s build-essential &> /dev/null; then
                log "Installing build-essential for Python package compilation..."
                apt-get install -y build-essential
            fi

            # Install python3-dev for header files
            if ! dpkg -s python3-dev &> /dev/null; then
                log "Installing python3-dev..."
                apt-get install -y python3-dev
            fi

            # Clean up
            log "Cleaning up apt cache..."
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;

        centos|rhel|fedora)
            log "Detected RedHat/CentOS/Fedora system"

            # Install Python 3 and pip if not present
            if ! command -v python3 &> /dev/null; then
                log "Installing Python 3..."
                yum install -y python3
            fi

            if ! command -v pip3 &> /dev/null; then
                log "Installing pip3..."
                yum install -y python3-pip
            fi

            # Install development tools
            if ! rpm -q gcc &> /dev/null; then
                log "Installing development tools..."
                yum groupinstall -y "Development Tools"
                yum install -y python3-devel
            fi

            # Clean up
            log "Cleaning up yum cache..."
            yum clean all
            ;;

        alpine)
            log "Detected Alpine system"

            # Update package index
            apk update

            # Install Python 3 and pip if not present
            if ! command -v python3 &> /dev/null; then
                log "Installing Python 3..."
                apk add python3
            fi

            if ! command -v pip3 &> /dev/null; then
                log "Installing pip3..."
                apk add py3-pip
            fi

            # Install build dependencies
            log "Installing build dependencies..."
            apk add gcc musl-dev python3-dev

            # Clean up
            log "Cleaning up apk cache..."
            rm -rf /var/cache/apk/*
            ;;

        *)
            error "Unsupported OS: $OS"
            error "Please install Python 3 and pip3 manually"
            exit 1
            ;;
    esac

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        error "Python 3 installation verification failed"
        exit 1
    fi
    log "✓ Python 3 verified: $(python3 --version)"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 installation verification failed"
        exit 1
    fi
    log "✓ pip3 verified: $(pip3 --version)"

    log "All prerequisites verified successfully"
}

# Check if SALib is already installed
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${PACKAGE_NAME}; print(${PACKAGE_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
            log "${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${PACKAGE_VERSION}"
            log "Will reinstall to ensure correct version"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install SALib
install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    pip3 install --upgrade pip

    # Install SALib with pinned version
    log "Installing ${PACKAGE_NAME}==${PACKAGE_VERSION}..."
    pip3 install --no-cache-dir "${PACKAGE_NAME}==${PACKAGE_VERSION}"

    log "${TOOL_NAME} installation completed"
}

# Validate installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if package can be imported
    if ! python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        error "Failed to import ${PACKAGE_NAME}"
        error "Installation validation failed"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(eval "$VALIDATE_CMD" 2>/dev/null || echo "")

    if [ -z "$installed_version" ]; then
        error "Failed to retrieve ${TOOL_NAME} version"
        error "Validation command: ${VALIDATE_CMD}"
        exit 1
    fi

    if [ "$installed_version" = "$PACKAGE_VERSION" ]; then
        log "✓ Validation successful: ${TOOL_NAME} ${installed_version} is correctly installed"
        return 0
    else
        error "Version mismatch: expected ${PACKAGE_VERSION}, got ${installed_version}"
        exit 1
    fi
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."
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
        log "${TOOL_NAME} ${TOOL_VERSION} installation verified (already present)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "${TOOL_NAME} ${TOOL_VERSION} installation completed successfully"
}

# Run main function
main "$@"
