#!/usr/bin/env bash

#######################################
# quarto-cl Installation Script
# Version: latest
# Package Manager: pip
# Installation Standards: Solutions Team v1.0
#######################################

set -euo pipefail

# Global variables
TOOL_NAME="quarto-cl"
PACKAGE_NAME="quarto_cli"
VERSION="latest"
VALIDATE_CMD="quarto --version"

#######################################
# Logging function with timestamp
#######################################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

#######################################
# Error handler
#######################################
error_exit() {
    log "ERROR: $1"
    exit 1
}

#######################################
# Check if prerequisites are installed
# Returns: 0 if all present, 1 if any missing
#######################################
check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check Python 3
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "✓ Python 3 found: version $python_version"
    else
        log "✗ Python 3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "✓ pip3 found: version $pip_version"
    else
        log "✗ pip3 not found"
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

#######################################
# Install missing prerequisites
#######################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Detect OS and package manager
    local OS
    if [ -f /etc/os-release ]; then
        # Extract just the ID field to avoid polluting namespace
        OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        error_exit "Cannot detect operating system"
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"
            export DEBIAN_FRONTEND=noninteractive

            log "Updating apt package index..."
            apt-get update || error_exit "Failed to update apt package index"

            log "Installing Python 3 and pip..."
            apt-get install -y \
                python3 \
                python3-pip \
                python3-venv \
                || error_exit "Failed to install Python prerequisites"

            log "Cleaning apt cache..."
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;

        centos|rhel|fedora)
            log "Detected Red Hat-based system"

            if command -v dnf &> /dev/null; then
                log "Installing Python 3 and pip using dnf..."
                dnf install -y python3 python3-pip || error_exit "Failed to install Python prerequisites"
            elif command -v yum &> /dev/null; then
                log "Installing Python 3 and pip using yum..."
                yum install -y python3 python3-pip || error_exit "Failed to install Python prerequisites"
            else
                error_exit "No package manager found (dnf/yum)"
            fi
            ;;

        alpine)
            log "Detected Alpine Linux"
            apk add --no-cache python3 py3-pip || error_exit "Failed to install Python prerequisites"
            ;;

        *)
            error_exit "Unsupported operating system: $OS"
            ;;
    esac

    log "Prerequisites installation completed"
}

#######################################
# Verify prerequisites are working
#######################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        error_exit "Python 3 verification failed - not working correctly"
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "✓ Python 3 verified: $python_version"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error_exit "pip3 verification failed - not working correctly"
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "✓ pip3 verified: $pip_version"

    log "All prerequisites verified successfully"
}

#######################################
# Check if tool is already installed
# Returns: 0 if installed with correct version, 1 otherwise
#######################################
check_existing_installation() {
    log "Checking for existing installation..."

    # Check if package is installed and quarto command is available
    if python3 -c "import $PACKAGE_NAME" &> /dev/null && command -v quarto &> /dev/null; then
        local installed_version
        installed_version=$(quarto --version 2>&1 || echo "unknown")

        if [ "$installed_version" != "unknown" ]; then
            log "✓ $TOOL_NAME is already installed: version $installed_version"

            # If version is "latest", we consider it installed
            if [ "$VERSION" = "latest" ]; then
                log "Version requirement is 'latest' - existing installation satisfies requirement"
                return 0
            fi

            # Check if installed version matches requested version
            if [ "$installed_version" = "$VERSION" ]; then
                log "Installed version matches requested version ($VERSION)"
                return 0
            else
                log "Installed version ($installed_version) differs from requested version ($VERSION)"
                return 1
            fi
        fi
    fi

    log "No existing installation found"
    return 1
}

#######################################
# Install the tool
#######################################
install_tool() {
    log "Installing $TOOL_NAME version $VERSION..."

    # Upgrade pip to avoid potential issues
    log "Upgrading pip..."
    pip3 install --upgrade pip || error_exit "Failed to upgrade pip"

    # Install the package
    if [ "$VERSION" = "latest" ]; then
        log "Installing latest version of $PACKAGE_NAME..."
        pip3 install --no-cache-dir "$PACKAGE_NAME" || error_exit "Failed to install $PACKAGE_NAME"
    else
        log "Installing $PACKAGE_NAME version $VERSION..."
        pip3 install --no-cache-dir "${PACKAGE_NAME}==${VERSION}" || error_exit "Failed to install $PACKAGE_NAME version $VERSION"
    fi

    log "$TOOL_NAME installation completed"
}

#######################################
# Validate the installation
#######################################
validate() {
    log "Validating installation..."

    # Check if package can be imported
    if ! python3 -c "import $PACKAGE_NAME" &> /dev/null; then
        error_exit "Validation failed: Cannot import $PACKAGE_NAME module"
    fi

    # Check if quarto command is available
    if ! command -v quarto &> /dev/null; then
        error_exit "Validation failed: quarto command not found in PATH"
    fi

    # Run the validation command
    local actual_version
    actual_version=$(eval "$VALIDATE_CMD" 2>&1) || error_exit "Validation command failed"

    if [ -z "$actual_version" ]; then
        error_exit "Validation failed: Version command returned empty result"
    fi

    log "✓ Validation successful: $TOOL_NAME version $actual_version"

    # If specific version was requested, verify it matches
    if [ "$VERSION" != "latest" ] && [ "$actual_version" != "$VERSION" ]; then
        error_exit "Version mismatch: Expected $VERSION, got $actual_version"
    fi

    return 0
}

#######################################
# Main execution flow
#######################################
main() {
    log "Starting $TOOL_NAME $VERSION installation..."
    log "Installation standards: Solutions Team v1.0"
    log "Package: $PACKAGE_NAME"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "Installation already complete - nothing to do"
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
