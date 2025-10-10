#!/usr/bin/env bash
################################################################################
# GNU Octave Installation Script
# Tool: octave
# Version: latest (via Snap)
# Validation: octave --version
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="octave"
readonly SNAP_PACKAGE="octave"
readonly SNAP_CHANNEL="stable"

# Flags
SKIP_PREREQS=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
    esac
done

# Check for RESPECT_SHARED_DEPS environment variable
if [[ "${RESPECT_SHARED_DEPS:-0}" == "1" ]]; then
    SKIP_PREREQS=true
fi

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >&2
}

################################################################################
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local missing=0

    # Check for snapd
    if ! command -v snap &> /dev/null; then
        log "Missing: snapd"
        missing=1
    else
        log "Found: snapd (snap version $(snap version | grep 'snap ' | awk '{print $2}'))"
    fi

    # Check for wget or curl
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log "Missing: wget or curl"
        missing=1
    else
        if command -v wget &> /dev/null; then
            log "Found: wget"
        else
            log "Found: curl"
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        log "Some prerequisites are missing"
        return 1
    fi

    log "All prerequisites satisfied"
    return 0
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Ensure we're running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo to install prerequisites"
        exit 1
    fi

    # Update package index
    log "Updating package index..."
    apt-get update

    # Install snapd if missing
    if ! command -v snap &> /dev/null; then
        log "Installing snapd..."
        apt-get install -y snapd

        # Start snapd service
        log "Starting snapd service..."
        systemctl enable --now snapd.socket || true
        systemctl start snapd || true

        # Wait for snapd to be ready
        log "Waiting for snapd to initialize..."
        sleep 5
    fi

    # Install wget if missing (and curl also missing)
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log "Installing wget..."
        apt-get install -y wget
    fi

    log_success "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify snapd
    if ! snap version &> /dev/null; then
        log_error "Snapd verification failed"
        log_error "Please ensure snapd is properly installed and running"
        exit 1
    fi

    local snap_version
    snap_version=$(snap version | grep 'snap ' | awk '{print $2}')
    log "Verified: snapd version ${snap_version}"

    # Verify wget or curl
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log_error "Neither wget nor curl is available"
        exit 1
    fi

    log_success "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if snap package is installed
    if snap list 2>/dev/null | grep -q "^${SNAP_PACKAGE} "; then
        log "Found existing Snap installation of ${TOOL_NAME}"
        return 0
    fi

    # Check if octave is available in PATH (non-snap installation)
    if command -v octave &> /dev/null; then
        local octave_path
        octave_path=$(command -v octave)
        if [[ ! "$octave_path" =~ /snap/ ]]; then
            log "Found existing system installation of ${TOOL_NAME} at ${octave_path}"
            return 0
        fi
    fi

    log "No existing installation found"
    return 1
}

install_tool() {
    log "Installing ${TOOL_NAME} via Snap..."

    # Install Octave from Snap
    log "Installing ${SNAP_PACKAGE} from ${SNAP_CHANNEL} channel..."
    snap install "${SNAP_PACKAGE}" --channel="${SNAP_CHANNEL}" --classic

    # Wait for snap to be fully available
    sleep 2

    log_success "${TOOL_NAME} installed successfully"
}

################################################################################
# Validation
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Try snap run first
    if snap list 2>/dev/null | grep -q "^${SNAP_PACKAGE} "; then
        log "Testing snap installation..."
        if snap run "${SNAP_PACKAGE}" --version &> /dev/null; then
            local version_output
            version_output=$(snap run "${SNAP_PACKAGE}" --version 2>&1 | head -n 1)
            log_success "Validation successful: ${version_output}"
            return 0
        fi
    fi

    # Try direct octave command
    if command -v octave &> /dev/null; then
        log "Testing octave command..."
        if octave --version &> /dev/null; then
            local version_output
            version_output=$(octave --version 2>&1 | head -n 1)
            log_success "Validation successful: ${version_output}"
            return 0
        fi
    fi

    log_error "Validation failed: Unable to execute 'octave --version'"
    log_error "Troubleshooting steps:"
    log_error "  1. Check if snap is installed: snap list | grep octave"
    log_error "  2. Try running manually: snap run octave --version"
    log_error "  3. Check snap logs: snap logs octave"
    log_error "  4. Verify snapd service: systemctl status snapd"
    exit 1
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    log "Starting ${TOOL_NAME} latest installation..."

    # Step 1: Prerequisites
    if [[ "${SKIP_PREREQS}" == "false" ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        fi
    else
        log "Skipping prerequisite installation (--skip-prereqs or RESPECT_SHARED_DEPS=1)"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Tool already installed, validating..."
        validate
        log_success "${TOOL_NAME} is already installed and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log_success "Installation completed successfully"
    log "You can now run: octave --version"
    log "Or use: snap run octave"
}

# Execute main function
main "$@"
