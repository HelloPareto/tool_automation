#!/usr/bin/env bash
#
# Installation script for altair v5.5.0
# Package Manager: pip
# Validation: python -c 'import altair; print(altair.__version__)'
#
# This script follows Solutions Team installation standards:
# - Idempotent (safe to run multiple times)
# - Version pinned
# - Non-interactive
# - Prerequisite detection and installation
# - Proper validation and error handling

set -euo pipefail

# Configuration
TOOL_NAME="altair"
TOOL_VERSION="5.5.0"
VALIDATE_CMD="python3 -c 'import altair; print(altair.__version__)'"

# Logging functions
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

    # Check Python 3
    if command -v python3 &> /dev/null; then
        log "✓ Python 3 found: $(python3 --version 2>&1)"
    else
        log "✗ Python 3 not found"
        all_present=false
    fi

    # Check pip
    if command -v pip3 &> /dev/null; then
        log "✓ pip3 found: $(pip3 --version 2>&1 | head -n1)"
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

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python 3 and pip if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python 3, pip, and venv..."
        apt-get install -y \
            python3 \
            python3-pip \
            python3-venv
    fi

    # Clean up
    log "Cleaning up apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        error "Python 3 verification failed"
        exit 1
    fi
    log "✓ Python 3 verified: $(python3 --version 2>&1)"

    # Verify pip
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        exit 1
    fi
    log "✓ pip3 verified: $(pip3 --version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed at the correct version
check_existing_installation() {
    log "Checking if ${TOOL_NAME} ${TOOL_VERSION} is already installed..."

    if python3 -c "import altair" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c 'import altair; print(altair.__version__)' 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "✓ ${TOOL_NAME} ${TOOL_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, but need ${TOOL_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Install altair with pinned version
    # Using --no-cache-dir to avoid caching issues and reduce disk usage
    log "Running: pip3 install altair==${TOOL_VERSION}"
    pip3 install --no-cache-dir "altair==${TOOL_VERSION}"

    log "${TOOL_NAME} installation completed"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if altair can be imported
    if ! python3 -c "import altair" 2>/dev/null; then
        error "Validation failed: Cannot import altair module"
        error "Remediation: Check if pip installation completed successfully"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c 'import altair; print(altair.__version__)' 2>/dev/null || echo "")

    if [ -z "$installed_version" ]; then
        error "Validation failed: Cannot determine altair version"
        error "Remediation: Reinstall altair with 'pip3 install altair==${TOOL_VERSION}'"
        exit 1
    fi

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Validation failed: Expected version ${TOOL_VERSION}, but got ${installed_version}"
        error "Remediation: Reinstall with 'pip3 install --force-reinstall altair==${TOOL_VERSION}'"
        exit 1
    fi

    log "✓ Validation successful: ${TOOL_NAME} ${installed_version}"
    return 0
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."

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

# Run main function
main
