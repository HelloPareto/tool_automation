#!/bin/bash
################################################################################
# LibreOffice Core Installation Script
# Tool: core
# Version: latest (using stable release from apt repository)
# Description: Read-only LibreOffice core repo - installs LibreOffice office suite
#              and creates 'core' command wrapper for validation
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_VERSION="latest"
readonly INSTALL_DIR="/usr/local/bin"
readonly LOG_PREFIX="[LibreOffice-Core-Install]"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "${LOG_PREFIX} [$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "${LOG_PREFIX} [$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

################################################################################
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check if apt-get is available (Debian/Ubuntu system)
    if ! command -v apt-get &> /dev/null; then
        error "apt-get not found. This script requires a Debian/Ubuntu-based system."
        return 1
    fi

    # Check if dpkg is available
    if ! command -v dpkg &> /dev/null; then
        error "dpkg not found. This script requires a Debian/Ubuntu-based system."
        return 1
    fi

    # Check for basic utilities (should be present in base image)
    local required_utils=("wget" "curl" "sudo")
    for util in "${required_utils[@]}"; do
        if ! command -v "$util" &> /dev/null; then
            log "Required utility '$util' not found - will be installed"
            all_present=false
        else
            log "Found: $util ($(command -v "$util"))"
        fi
    done

    if [ "$all_present" = true ]; then
        log "All prerequisites are already installed"
        return 0
    else
        log "Some prerequisites are missing and need to be installed"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Update apt cache
    log "Updating apt package cache..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq

    # Install basic utilities if missing
    local packages_to_install=()

    if ! command -v wget &> /dev/null; then
        packages_to_install+=("wget")
    fi

    if ! command -v curl &> /dev/null; then
        packages_to_install+=("curl")
    fi

    if ! command -v sudo &> /dev/null; then
        packages_to_install+=("sudo")
    fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log "Installing missing utilities: ${packages_to_install[*]}"
        apt-get install -y -qq "${packages_to_install[@]}"
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify apt-get
    if ! apt-get --version &> /dev/null; then
        error "apt-get verification failed"
        exit 1
    fi

    # Verify dpkg
    if ! dpkg --version &> /dev/null; then
        error "dpkg verification failed"
        exit 1
    fi

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing LibreOffice installation..."

    # Check if libreoffice is installed and get version
    if command -v libreoffice &> /dev/null; then
        local installed_version
        installed_version=$(libreoffice --version 2>&1 | head -n1 || echo "unknown")
        log "Found existing LibreOffice installation: $installed_version"

        # Check if core wrapper exists
        if [ -f "${INSTALL_DIR}/core" ]; then
            log "Found existing 'core' command wrapper"
            return 0
        else
            log "LibreOffice is installed but 'core' wrapper is missing - will create it"
            create_core_wrapper
            return 0
        fi
    fi

    log "No existing installation found"
    return 1
}

get_latest_version() {
    log "Determining latest available LibreOffice version from apt repository..."

    # Update apt cache to get latest package information
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq

    # Get the version that apt would install
    local latest_version
    latest_version=$(apt-cache policy libreoffice 2>/dev/null | grep Candidate | awk '{print $2}' || echo "unknown")

    if [ "$latest_version" = "unknown" ] || [ -z "$latest_version" ]; then
        error "Could not determine latest LibreOffice version from apt repository"
        return 1
    fi

    log "Latest available version: $latest_version"
    echo "$latest_version"
}

install_tool() {
    log "Installing LibreOffice..."

    # Get latest version information
    local version_to_install
    version_to_install=$(get_latest_version)

    if [ -z "$version_to_install" ]; then
        error "Failed to determine version to install"
        exit 1
    fi

    log "Installing LibreOffice version: $version_to_install"

    # Install LibreOffice using apt-get
    # Using --no-install-recommends to minimize installation size
    # Installing libreoffice-core and libreoffice-common for basic functionality
    export DEBIAN_FRONTEND=noninteractive

    log "Installing libreoffice package..."
    if ! apt-get install -y -qq \
        libreoffice-core \
        libreoffice-common \
        libreoffice-writer \
        libreoffice; then
        error "Failed to install LibreOffice"
        exit 1
    fi

    log "LibreOffice installation completed"

    # Create the 'core' command wrapper
    create_core_wrapper

    # Clean up apt cache
    log "Cleaning up apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Installation completed successfully"
}

create_core_wrapper() {
    log "Creating 'core' command wrapper..."

    # Verify libreoffice command exists
    if ! command -v libreoffice &> /dev/null; then
        error "libreoffice command not found - cannot create wrapper"
        exit 1
    fi

    # Create wrapper script that forwards to libreoffice
    cat > "${INSTALL_DIR}/core" <<'EOF'
#!/bin/bash
# LibreOffice Core wrapper script
# Forwards all commands to the libreoffice binary

exec libreoffice "$@"
EOF

    # Make wrapper executable
    chmod 755 "${INSTALL_DIR}/core"

    # Verify wrapper was created
    if [ ! -f "${INSTALL_DIR}/core" ]; then
        error "Failed to create core wrapper at ${INSTALL_DIR}/core"
        exit 1
    fi

    log "Core wrapper created successfully at ${INSTALL_DIR}/core"
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating installation..."

    # Check if core command exists
    if ! command -v core &> /dev/null; then
        error "core command not found in PATH"
        error "Please ensure ${INSTALL_DIR} is in your PATH"
        exit 1
    fi

    # Run version check
    log "Running: core --version"
    local version_output
    if ! version_output=$(core --version 2>&1); then
        error "Failed to run 'core --version'"
        error "Output: $version_output"
        exit 1
    fi

    # Display version information
    log "Version check successful:"
    echo "$version_output" | head -n 5

    # Verify the output contains LibreOffice version information
    if echo "$version_output" | grep -qi "libreoffice"; then
        log "LibreOffice core installation validated successfully"
        return 0
    else
        error "Version output does not contain expected LibreOffice information"
        error "Output: $version_output"
        exit 1
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting LibreOffice core ${TOOL_VERSION} installation..."
    log "Script will install LibreOffice and create 'core' command wrapper"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "LibreOffice core is already installed - verifying..."
        validate
        log "Installation verified - no changes needed (idempotent)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "=============================================="
    log "LibreOffice core installation completed successfully"
    log "=============================================="
    log "Usage: core --version"
    log "       core --help"
    log "       core --writer (to start Writer)"
    log "       core --calc (to start Calc)"
    log "=============================================="
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
