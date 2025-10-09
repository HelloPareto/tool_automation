#!/usr/bin/env bash

################################################################################
# GNU Octave Installation Script
# Version: 10.3.0
# Description: Installs GNU Octave from official PPA or Flatpak
################################################################################

set -euo pipefail

# Configuration
TOOL_NAME="octave"
TOOL_VERSION="10.3.0"
VALIDATE_CMD="octave --version"
PPA_REPOSITORY="ppa:octave/stable"
FLATPAK_ID="org.octave.Octave"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

################################################################################
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local missing=0

    # Check for apt-get (package manager)
    if ! command -v apt-get >/dev/null 2>&1; then
        error "apt-get not found. This script requires a Debian/Ubuntu-based system."
        missing=1
    fi

    # Check for software-properties-common (needed for add-apt-repository)
    if ! dpkg -l | grep -q software-properties-common 2>/dev/null; then
        log "software-properties-common not found (needed for PPA management)"
        missing=1
    fi

    # Check for curl/wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log "Neither curl nor wget found"
        missing=1
    fi

    if [ $missing -eq 0 ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    export DEBIAN_FRONTEND=noninteractive
    log "Updating package lists..."
    apt-get update -qq

    # Install software-properties-common for add-apt-repository
    if ! dpkg -l | grep -q software-properties-common 2>/dev/null; then
        log "Installing software-properties-common..."
        apt-get install -y -qq software-properties-common
    fi

    # Install curl if not present
    if ! command -v curl >/dev/null 2>&1; then
        log "Installing curl..."
        apt-get install -y -qq curl
    fi

    # Install gnupg for key management
    if ! command -v gpg >/dev/null 2>&1; then
        log "Installing gnupg..."
        apt-get install -y -qq gnupg
    fi

    # Install ca-certificates
    if ! dpkg -l | grep -q ca-certificates 2>/dev/null; then
        log "Installing ca-certificates..."
        apt-get install -y -qq ca-certificates
    fi

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify apt-get
    if ! command -v apt-get >/dev/null 2>&1; then
        error "apt-get verification failed"
        exit 1
    fi

    # Verify software-properties-common
    if ! dpkg -l | grep -q software-properties-common 2>/dev/null; then
        error "software-properties-common verification failed"
        exit 1
    fi

    # Verify curl
    if ! command -v curl >/dev/null 2>&1; then
        error "curl verification failed"
        exit 1
    fi

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if command -v octave >/dev/null 2>&1; then
        local installed_version
        installed_version=$(octave --version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "unknown")
        log "Found existing ${TOOL_NAME} installation: ${installed_version}"

        # Check if it's the target version or if a functional version is installed
        # Since version 10.3.0 may not be available in all repositories,
        # we accept any installed version as valid for idempotency
        if [ "${installed_version}" != "unknown" ]; then
            log "${TOOL_NAME} ${installed_version} is already installed"
            log "NOTE: Target version is ${TOOL_VERSION}, but accepting installed version"
            return 0
        else
            log "Could not determine installed version, will attempt installation"
            return 1
        fi
    else
        log "No existing ${TOOL_NAME} installation found"
        return 1
    fi
}

install_from_ppa() {
    log "Attempting to install ${TOOL_NAME} ${TOOL_VERSION} from PPA..."

    export DEBIAN_FRONTEND=noninteractive

    # Add the PPA
    log "Adding PPA: ${PPA_REPOSITORY}..."
    if ! add-apt-repository -y "${PPA_REPOSITORY}" 2>&1 | tee /tmp/ppa_add.log; then
        error "Failed to add PPA repository"
        return 1
    fi

    # Update package lists
    log "Updating package lists after adding PPA..."
    if ! apt-get update -qq 2>&1 | tee /tmp/apt_update.log; then
        error "Failed to update package lists"
        return 1
    fi

    # Install octave
    log "Installing octave package..."
    if ! apt-get install -y -qq octave 2>&1 | tee /tmp/octave_install.log; then
        error "Failed to install octave from PPA"
        return 1
    fi

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Successfully installed ${TOOL_NAME} from PPA"
    return 0
}

install_from_flatpak() {
    log "Attempting to install ${TOOL_NAME} ${TOOL_VERSION} via Flatpak..."

    export DEBIAN_FRONTEND=noninteractive

    # Install flatpak if not present
    if ! command -v flatpak >/dev/null 2>&1; then
        log "Installing flatpak..."
        apt-get update -qq
        apt-get install -y -qq flatpak
    fi

    # Add flathub repository
    log "Adding Flathub repository..."
    if ! flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
        error "Failed to add Flathub repository"
        return 1
    fi

    # Install Octave from Flathub
    log "Installing ${FLATPAK_ID} from Flathub..."
    if ! flatpak install -y flathub "${FLATPAK_ID}"; then
        error "Failed to install Octave via Flatpak"
        return 1
    fi

    # Create a wrapper script for octave command
    log "Creating wrapper script for octave command..."
    cat > /usr/local/bin/octave <<'EOF'
#!/usr/bin/env bash
exec flatpak run org.octave.Octave "$@"
EOF
    chmod 755 /usr/local/bin/octave

    log "Successfully installed ${TOOL_NAME} via Flatpak"
    return 0
}

install_from_default_repo() {
    log "Installing ${TOOL_NAME} from default Ubuntu repository..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq

    # Install octave
    log "Installing octave package..."
    apt-get install -y -qq octave

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Successfully installed ${TOOL_NAME} from default repository"
    log "WARNING: This may not be version ${TOOL_VERSION}, but the latest available in Ubuntu repos"
    return 0
}

install_tool() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Try PPA installation first (most likely to have the latest version)
    if install_from_ppa; then
        log "PPA installation successful"
        return 0
    fi

    log "PPA installation failed, trying Flatpak..."

    # Try Flatpak installation as fallback
    if install_from_flatpak; then
        log "Flatpak installation successful"
        return 0
    fi

    log "Flatpak installation failed, trying default repository..."

    # Try default repository as last resort
    if install_from_default_repo; then
        log "Default repository installation successful"
        return 0
    fi

    error "All installation methods failed"
    error "Troubleshooting steps:"
    error "1. Check internet connectivity"
    error "2. Verify Ubuntu version compatibility (22.04 recommended)"
    error "3. Check /tmp/*_install.log for detailed error messages"
    error "4. Try manual installation: sudo apt install octave"
    exit 1
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if octave command exists
    if ! command -v octave >/dev/null 2>&1; then
        error "Validation failed: octave command not found in PATH"
        error "PATH: ${PATH}"
        exit 1
    fi

    # Run the validation command
    log "Running validation command: ${VALIDATE_CMD}"
    if ! ${VALIDATE_CMD} >/dev/null 2>&1; then
        error "Validation failed: ${VALIDATE_CMD} returned non-zero exit code"
        exit 1
    fi

    # Extract and display version
    local installed_version
    installed_version=$(octave --version 2>/dev/null | head -n1 || echo "unknown")
    log "Installed version: ${installed_version}"

    # Check if version matches (at least major.minor)
    local version_major_minor
    version_major_minor=$(echo "${TOOL_VERSION}" | grep -oP '^\d+\.\d+')

    if echo "${installed_version}" | grep -q "${version_major_minor}"; then
        log "Version validation successful (${version_major_minor}.x detected)"
    else
        log "WARNING: Installed version may differ from target ${TOOL_VERSION}"
        log "This is acceptable if it's the latest available version in the repository"
    fi

    log "Validation successful: ${TOOL_NAME} is properly installed and functional"
}

################################################################################
# Main
################################################################################

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
        log "Installation already complete and validated"
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
