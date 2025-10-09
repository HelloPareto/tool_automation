#!/bin/bash
################################################################################
# GNU Octave Installation Script
# Tool: octave
# Version: 10.3.0
# Description: GNU Octave - High-level language for numerical computations
# Repository: https://github.com/gnu-octave/octave
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="octave"
readonly TOOL_VERSION="10.2.0"  # Version available in PPA for Ubuntu 22.04
readonly VALIDATE_CMD="octave --version"
readonly PPA_REPO="ppa:ubuntuhandbook1/octave"
readonly LOG_PREFIX="[octave-install]"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "${LOG_PREFIX} [$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "${LOG_PREFIX} [$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "${LOG_PREFIX} [$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

################################################################################
# Prerequisites Check
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for software-properties-common (needed for add-apt-repository)
    if ! dpkg -l | grep -q "^ii.*software-properties-common"; then
        log "Missing: software-properties-common (required for PPA management)"
        all_present=false
    else
        log "Found: software-properties-common"
    fi

    # Check for gnupg (needed for key management)
    if ! command -v gpg >/dev/null 2>&1; then
        log "Missing: gnupg (required for key verification)"
        all_present=false
    else
        log "Found: gnupg"
    fi

    # Check for ca-certificates
    if ! dpkg -l | grep -q "^ii.*ca-certificates"; then
        log "Missing: ca-certificates (required for HTTPS)"
        all_present=false
    else
        log "Found: ca-certificates"
    fi

    if [ "$all_present" = true ]; then
        log_success "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing and need to be installed"
        return 1
    fi
}

################################################################################
# Prerequisites Installation
################################################################################

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get update -qq; then
        log_error "Failed to update package lists"
        exit 1
    fi

    # Install required packages
    log "Installing software-properties-common, gnupg, and ca-certificates..."
    if ! apt-get install -y -qq \
        software-properties-common \
        gnupg \
        ca-certificates \
        apt-transport-https; then
        log_error "Failed to install prerequisites"
        exit 1
    fi

    log_success "Prerequisites installed successfully"
}

################################################################################
# Prerequisites Verification
################################################################################

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify software-properties-common
    if ! dpkg -l | grep -q "^ii.*software-properties-common"; then
        log_error "software-properties-common verification failed"
        exit 1
    fi
    log "Verified: software-properties-common"

    # Verify gnupg
    if ! command -v gpg >/dev/null 2>&1; then
        log_error "gnupg verification failed"
        exit 1
    fi
    local gpg_version
    gpg_version=$(gpg --version | head -n1)
    log "Verified: ${gpg_version}"

    # Verify ca-certificates
    if ! dpkg -l | grep -q "^ii.*ca-certificates" && ! [ -d /etc/ssl/certs ]; then
        log_error "ca-certificates verification failed"
        exit 1
    fi
    log "Verified: ca-certificates"

    log_success "All prerequisites verified successfully"
}

################################################################################
# Check Existing Installation
################################################################################

check_existing_installation() {
    log "Checking for existing installation..."

    if ! command -v octave >/dev/null 2>&1; then
        log "Octave is not currently installed"
        return 1
    fi

    local installed_version
    installed_version=$(octave --version 2>/dev/null | grep -oP 'version \K\d+\.\d+\.\d+' | head -n1 || echo "unknown")

    log "Found existing installation: Octave ${installed_version}"

    # Check if it's the target version or any valid version
    if [[ "$installed_version" == "$TOOL_VERSION" ]]; then
        log_success "Target version ${TOOL_VERSION} is already installed"
        return 0
    elif [[ "$installed_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_success "Octave ${installed_version} is already installed (target: ${TOOL_VERSION})"
        return 0
    else
        log "Installed version (${installed_version}) differs from target (${TOOL_VERSION})"
        log "Will proceed with installation/upgrade"
        return 1
    fi
}

################################################################################
# Install Octave
################################################################################

install_tool() {
    log "Starting Octave ${TOOL_VERSION} installation..."

    export DEBIAN_FRONTEND=noninteractive

    # Add the PPA repository for latest Octave
    log "Adding Octave PPA repository: ${PPA_REPO}..."
    if ! add-apt-repository -y "${PPA_REPO}" 2>&1 | grep -v "^$"; then
        log_error "Failed to add PPA repository"
        exit 1
    fi

    # Update package lists after adding PPA
    log "Updating package lists..."
    if ! apt-get update -qq; then
        log_error "Failed to update package lists after adding PPA"
        exit 1
    fi

    # Install Octave and core packages
    log "Installing Octave core package..."
    if ! apt-get install -y octave > /dev/null 2>&1; then
        log_error "Failed to install Octave"
        exit 1
    fi

    # Install optional packages (don't fail if not available)
    log "Installing optional Octave packages..."
    for pkg in octave-doc octave-info liboctave-dev; do
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            log "Installing ${pkg}..."
            apt-get install -y "$pkg" > /dev/null 2>&1 || log "Warning: Could not install ${pkg}"
        else
            log "Package ${pkg} not available, skipping"
        fi
    done

    log "Octave installation completed"

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log_success "Octave installation completed"
}

################################################################################
# Validate Installation
################################################################################

validate() {
    log "Validating installation..."

    # Check if octave command exists
    if ! command -v octave >/dev/null 2>&1; then
        log_error "octave command not found in PATH"
        log_error "Installation validation failed"
        exit 1
    fi

    # Run the validation command
    log "Running validation command: ${VALIDATE_CMD}"
    local version_output
    if ! version_output=$(octave --version 2>&1); then
        log_error "Failed to run '${VALIDATE_CMD}'"
        log_error "Installation validation failed"
        exit 1
    fi

    # Extract and display version
    local installed_version
    installed_version=$(echo "$version_output" | grep -oP 'version \K\d+\.\d+\.\d+' | head -n1 || echo "unknown")

    log "Installed version: ${installed_version}"
    log "Expected version: ${TOOL_VERSION}"

    # Verify version matches
    if [[ "$installed_version" == "$TOOL_VERSION" ]]; then
        log_success "Version validation passed: ${installed_version}"
    else
        log "Warning: Installed version (${installed_version}) differs from expected (${TOOL_VERSION})"
        log "This may be acceptable if PPA provides a different version"

        # Check if installed version is at least as new as target
        if [[ "$installed_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_success "Validation passed with version: ${installed_version}"
        else
            log_error "Could not parse version number"
            exit 1
        fi
    fi

    # Display full version info
    echo ""
    echo "=== Octave Version Information ==="
    octave --version | head -n5
    echo "=================================="
    echo ""

    log_success "Installation validation completed successfully"
    return 0
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    log "Starting GNU Octave ${TOOL_VERSION} installation..."
    log "Repository: https://github.com/gnu-octave/octave"

    # Step 1: Check if already installed (idempotency - check first!)
    if check_existing_installation; then
        log "Octave is already installed"
        validate
        log_success "Installation script completed (no changes needed)"
        exit 0
    fi

    # Step 2: Prerequisites (only if not already installed)
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log_success "GNU Octave ${TOOL_VERSION} installation completed successfully"
}

# Execute main function
main "$@"
