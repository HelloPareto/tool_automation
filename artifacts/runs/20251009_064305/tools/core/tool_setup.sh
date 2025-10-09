#!/bin/bash
#
# LibreOffice Core Installation Script
# Tool: core (LibreOffice)
# Version: latest (7.3.7 from Ubuntu 22.04 repositories)
# Validation: core --version
#
# This script installs LibreOffice and creates a 'core' command wrapper
# to match the specified validation command.
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Installation constants
readonly TOOL_NAME="core"
readonly LIBREOFFICE_VERSION="7.3.7"
readonly INSTALL_MARKER="/usr/local/bin/core"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]] && ! command -v sudo &> /dev/null; then
        log_error "This script requires root privileges or sudo. Please run with sudo or as root."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # LibreOffice has minimal prerequisites on Ubuntu 22.04
    # Just need apt-get and basic system utilities which are in the base image

    if ! command -v apt-get &> /dev/null; then
        log_warn "apt-get not found (required for installation)"
        all_present=false
    fi

    if ! command -v wget &> /dev/null; then
        log_warn "wget not found (should be in base image)"
        all_present=false
    fi

    if ! command -v gpg &> /dev/null; then
        log_warn "gpg not found (needed for package verification)"
        all_present=false
    fi

    if [[ "$all_present" == "true" ]]; then
        log "All prerequisites are present"
        return 0
    else
        log_warn "Some prerequisites are missing"
        return 1
    fi
}

# Function to install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    if [[ $EUID -eq 0 ]]; then
        apt-get update -qq
    else
        sudo apt-get update -qq
    fi

    # Install prerequisites if missing
    local packages_to_install=()

    if ! command -v wget &> /dev/null; then
        packages_to_install+=(wget)
    fi

    if ! command -v gpg &> /dev/null; then
        packages_to_install+=(gnupg)
    fi

    if ! command -v curl &> /dev/null; then
        packages_to_install+=(curl)
    fi

    # Install ca-certificates for HTTPS
    packages_to_install+=(ca-certificates)

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log "Installing packages: ${packages_to_install[*]}"
        if [[ $EUID -eq 0 ]]; then
            apt-get install -y -qq "${packages_to_install[@]}"
        else
            sudo apt-get install -y -qq "${packages_to_install[@]}"
        fi
    fi

    # Clean up
    if [[ $EUID -eq 0 ]]; then
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    else
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
    fi

    log "Prerequisites installed successfully"
}

# Function to verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    local verification_failed=false

    if ! command -v apt-get &> /dev/null; then
        log_error "apt-get verification failed"
        verification_failed=true
    fi

    if ! command -v wget &> /dev/null; then
        log_error "wget verification failed"
        verification_failed=true
    fi

    if [[ "$verification_failed" == "true" ]]; then
        log_error "Prerequisite verification failed. Cannot proceed with installation."
        exit 1
    fi

    log "All prerequisites verified successfully"
}

# Function to check existing installation
check_existing_installation() {
    log "Checking for existing LibreOffice installation..."

    # Check if libreoffice is installed
    if command -v libreoffice &> /dev/null; then
        local installed_version
        installed_version=$(libreoffice --version 2>/dev/null | grep -oP 'LibreOffice \K[0-9.]+' || echo "unknown")
        log "Found existing LibreOffice version: $installed_version"

        # Check if core wrapper exists
        if [[ -f "$INSTALL_MARKER" ]] || command -v core &> /dev/null; then
            log "LibreOffice and 'core' command wrapper already installed"
            return 0
        else
            log "LibreOffice installed but 'core' wrapper missing, will create it"
            create_core_wrapper
            return 0
        fi
    fi

    log "LibreOffice not found, proceeding with installation"
    return 1
}

# Function to create core command wrapper
create_core_wrapper() {
    log "Creating 'core' command wrapper..."

    # Create a wrapper script that calls libreoffice
    if [[ $EUID -eq 0 ]]; then
        cat > "$INSTALL_MARKER" << 'EOF'
#!/bin/bash
# Wrapper script for LibreOffice to provide "core" command
# This satisfies the validation requirement: core --version

if [[ "$1" == "--version" ]]; then
    libreoffice --version
else
    libreoffice "$@"
fi
EOF
        chmod 755 "$INSTALL_MARKER"
    else
        sudo tee "$INSTALL_MARKER" > /dev/null << 'EOF'
#!/bin/bash
# Wrapper script for LibreOffice to provide "core" command
# This satisfies the validation requirement: core --version

if [[ "$1" == "--version" ]]; then
    libreoffice --version
else
    libreoffice "$@"
fi
EOF
        sudo chmod 755 "$INSTALL_MARKER"
    fi

    log "'core' wrapper created at $INSTALL_MARKER"
}

# Function to install LibreOffice
install_tool() {
    log "Installing LibreOffice..."

    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    if [[ $EUID -eq 0 ]]; then
        apt-get update -qq
    else
        sudo apt-get update -qq
    fi

    # Install LibreOffice
    # Using the full libreoffice metapackage which includes all components
    log "Installing LibreOffice package..."
    if [[ $EUID -eq 0 ]]; then
        apt-get install -y -qq \
            libreoffice \
            libreoffice-core \
            libreoffice-common
    else
        sudo apt-get install -y -qq \
            libreoffice \
            libreoffice-core \
            libreoffice-common
    fi

    # Verify libreoffice binary exists
    if ! command -v libreoffice &> /dev/null; then
        log_error "LibreOffice installation failed - libreoffice command not found"
        exit 1
    fi

    log "LibreOffice installed successfully"

    # Create the core wrapper
    create_core_wrapper

    # Clean up apt cache
    log "Cleaning up package cache..."
    if [[ $EUID -eq 0 ]]; then
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    else
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
    fi

    log "Installation completed"
}

# Function to validate installation
validate() {
    log "Validating installation..."

    # Check if core command exists
    if ! command -v core &> /dev/null; then
        log_error "Validation failed: 'core' command not found in PATH"
        log_error "Expected location: $INSTALL_MARKER"
        exit 1
    fi

    # Run core --version
    log "Running: core --version"
    local version_output
    if ! version_output=$(core --version 2>&1); then
        log_error "Validation failed: 'core --version' command failed"
        log_error "Output: $version_output"
        exit 1
    fi

    # Check if output contains LibreOffice version
    if [[ ! "$version_output" =~ LibreOffice ]]; then
        log_error "Validation failed: Unexpected output from 'core --version'"
        log_error "Output: $version_output"
        exit 1
    fi

    # Display version
    log "Validation successful!"
    log "Version output: $version_output"

    # Also verify libreoffice command works
    if command -v libreoffice &> /dev/null; then
        local lo_version
        lo_version=$(libreoffice --version 2>/dev/null || echo "unknown")
        log "LibreOffice version: $lo_version"
    fi

    return 0
}

# Main installation flow
main() {
    log "========================================"
    log "LibreOffice Core Installation"
    log "Tool: $TOOL_NAME"
    log "Target Version: $LIBREOFFICE_VERSION (Ubuntu 22.04 repository)"
    log "========================================"

    # Check root/sudo
    check_root

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "Tool is already installed, validating..."
        validate
        log "Installation verification complete - no changes needed"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "========================================"
    log "Installation completed successfully!"
    log "========================================"
    log ""
    log "Usage: core --version"
    log "       libreoffice [options] [file...]"
}

# Execute main function
main "$@"
