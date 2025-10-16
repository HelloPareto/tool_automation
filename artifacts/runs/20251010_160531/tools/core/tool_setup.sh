#!/bin/bash
# LibreOffice Core Installation Script
# Version: 25.8.2
# Description: Installs LibreOffice from official pre-built deb packages

set -euo pipefail
IFS=$'\n\t'

# Initialize variables safely
tmp_dir="${tmp_dir:-$(mktemp -d)}"
trap 'rm -rf "$tmp_dir"' EXIT

# Configuration
TOOL_VERSION="25.8.2"
DOWNLOAD_URL="https://download.documentfoundation.org/libreoffice/stable/${TOOL_VERSION}/deb/x86_64/LibreOffice_${TOOL_VERSION}_Linux_x86-64_deb.tar.gz"
EXPECTED_SHA256="d703ce5d6760684061f7d22e2b8df91320c2fe3601a8472975b4b05b22af43ba"
SKIP_PREREQS="${SKIP_PREREQS:-0}"
RESPECT_SHARED_DEPS="${RESPECT_SHARED_DEPS:-0}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error handling
error_exit() {
    log "ERROR: $1"
    log "Installation failed. Please check the error message above."
    exit 1
}

# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            log "Script requires root privileges. Using sudo..."
            SUDO="sudo"
        else
            error_exit "This script must be run as root or sudo must be available"
        fi
    else
        SUDO=""
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        log "Missing prerequisite: curl"
        missing_prereqs=1
    fi

    # Check for tar
    if ! command -v tar >/dev/null 2>&1; then
        log "Missing prerequisite: tar"
        missing_prereqs=1
    fi

    # Check for dpkg
    if ! command -v dpkg >/dev/null 2>&1; then
        log "Missing prerequisite: dpkg"
        missing_prereqs=1
    fi

    # Check for sha256sum
    if ! command -v sha256sum >/dev/null 2>&1; then
        log "Missing prerequisite: sha256sum (coreutils)"
        missing_prereqs=1
    fi

    # Check for LibreOffice runtime libraries
    if ! dpkg -l | grep -q libxinerama1; then
        log "Missing LibreOffice runtime dependencies"
        missing_prereqs=1
    fi

    if [[ $missing_prereqs -eq 0 ]]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Respect shared dependencies flag
    if [[ $SKIP_PREREQS -eq 1 ]] || [[ $RESPECT_SHARED_DEPS -eq 1 ]]; then
        log "Skipping prerequisite installation (SKIP_PREREQS or RESPECT_SHARED_DEPS set)"
        return 0
    fi

    check_root

    # Update package lists
    log "Updating package lists..."
    $SUDO apt-get update || error_exit "Failed to update package lists"

    # Install required packages
    log "Installing curl, tar, coreutils..."
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
        curl \
        tar \
        coreutils \
        ca-certificates || error_exit "Failed to install prerequisites"

    # Install LibreOffice runtime dependencies
    log "Installing LibreOffice runtime dependencies..."
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
        libxinerama1 \
        libgl1 \
        libglu1-mesa \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libglib2.0-0 \
        libsm6 \
        libice6 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        fontconfig \
        libfreetype6 \
        libxml2 \
        libxslt1.1 \
        libgssapi-krb5-2 \
        libkrb5-3 \
        libcom-err2 \
        libk5crypto3 \
        libcurl4 \
        libhyphen0 \
        libhunspell-1.7-0 \
        libboost-locale1.74.0 \
        libboost-date-time1.74.0 \
        libboost-filesystem1.74.0 \
        libicu70 \
        libnss3 \
        libnspr4 || error_exit "Failed to install LibreOffice dependencies"

    log "Prerequisites installed successfully"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify curl
    if ! curl --version >/dev/null 2>&1; then
        error_exit "curl verification failed"
    fi
    log "curl: $(curl --version | head -n1)"

    # Verify tar
    if ! tar --version >/dev/null 2>&1; then
        error_exit "tar verification failed"
    fi
    log "tar: $(tar --version | head -n1)"

    # Verify dpkg
    if ! dpkg --version >/dev/null 2>&1; then
        error_exit "dpkg verification failed"
    fi
    log "dpkg: $(dpkg --version | head -n1)"

    # Verify sha256sum
    if ! sha256sum --version >/dev/null 2>&1; then
        error_exit "sha256sum verification failed"
    fi
    log "sha256sum: $(sha256sum --version | head -n1)"

    log "All prerequisites verified successfully"
}

# Check existing installation
check_existing_installation() {
    log "Checking for existing LibreOffice installation..."

    # Check if LibreOffice is already installed and accessible
    if command -v libreoffice >/dev/null 2>&1; then
        local installed_version
        installed_version=$(libreoffice --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "unknown")
        log "LibreOffice is already installed (version: $installed_version)"

        # Check if it's the exact version we want
        if [[ "$installed_version" == "$TOOL_VERSION"* ]]; then
            log "Target version $TOOL_VERSION is already installed"
            return 0
        else
            log "Different version installed, will proceed with installation"
            return 1
        fi
    fi

    log "LibreOffice is not installed"
    return 1
}

# Install the tool
install_tool() {
    log "Installing LibreOffice $TOOL_VERSION..."

    check_root

    # Download the package
    log "Downloading LibreOffice from $DOWNLOAD_URL..."
    local download_path="$tmp_dir/libreoffice.tar.gz"

    if ! curl -L -f -o "$download_path" "$DOWNLOAD_URL"; then
        error_exit "Failed to download LibreOffice from $DOWNLOAD_URL"
    fi

    log "Download completed"

    # Verify checksum
    log "Verifying SHA256 checksum..."
    local actual_sha256
    actual_sha256=$(sha256sum "$download_path" | awk '{print $1}')

    if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
        error_exit "SHA256 checksum mismatch! Expected: $EXPECTED_SHA256, Got: $actual_sha256"
    fi

    log "Checksum verified successfully"

    # Extract the archive
    log "Extracting archive..."
    if ! tar -xzf "$download_path" -C "$tmp_dir"; then
        error_exit "Failed to extract archive"
    fi

    log "Archive extracted successfully"

    # Find the DEBS directory
    local debs_dir
    debs_dir=$(find "$tmp_dir" -type d -name "DEBS" | head -n1)

    if [[ -z "$debs_dir" ]]; then
        error_exit "Could not find DEBS directory in extracted archive"
    fi

    log "Found DEBS directory: $debs_dir"

    # Install all .deb packages
    log "Installing LibreOffice packages..."

    # Install main packages first
    if ! $SUDO dpkg -i "$debs_dir"/*.deb 2>/dev/null; then
        log "Some packages failed to install, running apt-get install -f to fix dependencies..."
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -f -y || error_exit "Failed to fix dependencies"

        # Retry installation
        if ! $SUDO dpkg -i "$debs_dir"/*.deb 2>/dev/null; then
            log "Still have issues, trying to install dependencies again..."
            DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -f -y
        fi
    fi

    log "LibreOffice packages installed successfully"

    # Find LibreOffice installation directory
    local libreoffice_dir
    libreoffice_dir=$(find /opt -maxdepth 1 -name "libreoffice*" -type d 2>/dev/null | head -n1)

    if [[ -z "$libreoffice_dir" ]]; then
        error_exit "Could not find LibreOffice installation directory in /opt"
    fi

    log "Found LibreOffice directory: $libreoffice_dir"

    # Create symlinks for libreoffice and soffice in /usr/bin
    if [[ -f "$libreoffice_dir/program/soffice" ]]; then
        log "Creating libreoffice symlink in /usr/bin..."
        $SUDO ln -sf "$libreoffice_dir/program/soffice" /usr/bin/libreoffice || error_exit "Failed to create libreoffice symlink"
        $SUDO ln -sf "$libreoffice_dir/program/soffice" /usr/bin/soffice || error_exit "Failed to create soffice symlink"
    else
        error_exit "Could not find soffice binary in $libreoffice_dir/program"
    fi

    # Create symlink for 'core' command
    log "Creating 'core' symlink..."
    $SUDO ln -sf /usr/bin/libreoffice /usr/local/bin/core || error_exit "Failed to create core symlink"

    # Runtime linkage verification
    log "Verifying runtime linkage..."
    local libreoffice_binary
    libreoffice_binary=$(command -v libreoffice || echo "/usr/bin/libreoffice")

    if [[ -f "$libreoffice_binary" ]]; then
        # Check if it's a shell script or binary
        if file "$libreoffice_binary" | grep -q "shell script"; then
            log "LibreOffice binary is a shell script wrapper, skipping ldd check"
        else
            # Check for missing shared libraries
            if command -v ldd >/dev/null 2>&1; then
                local missing_libs
                missing_libs=$(ldd "$libreoffice_binary" 2>/dev/null | grep "not found" || true)

                if [[ -n "$missing_libs" ]]; then
                    log "Warning: Missing shared libraries detected:"
                    log "$missing_libs"
                    log "Attempting to install missing libraries..."

                    # Parse and install missing libraries
                    while IFS= read -r line; do
                        if [[ -n "$line" ]]; then
                            local lib_name
                            lib_name=$(echo "$line" | awk '{print $1}')
                            log "Missing library: $lib_name"

                            # Map common libraries to Ubuntu packages
                            case "$lib_name" in
                                libxslt.so.*)
                                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y libxslt1.1 || true
                                    ;;
                                libxml2.so.*)
                                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y libxml2 || true
                                    ;;
                                libcurl.so.*)
                                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y libcurl4 || true
                                    ;;
                                libssl.so.*)
                                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y libssl3 || true
                                    ;;
                                libcrypto.so.*)
                                    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y libssl3 || true
                                    ;;
                                *)
                                    log "Unknown library: $lib_name - may need manual installation"
                                    ;;
                            esac
                        fi
                    done <<< "$missing_libs"

                    # Run ldconfig to update library cache
                    $SUDO ldconfig || log "Warning: ldconfig failed"

                    # Re-check for missing libraries
                    missing_libs=$(ldd "$libreoffice_binary" 2>/dev/null | grep "not found" || true)
                    if [[ -n "$missing_libs" ]]; then
                        log "Warning: Some libraries are still missing after installation attempt"
                    else
                        log "All missing libraries resolved"
                    fi
                fi
            fi
        fi
    fi

    log "LibreOffice installation completed successfully"
}

# Validate installation
validate() {
    log "Validating LibreOffice installation..."

    # Check if 'core' command exists (our symlink)
    if ! command -v core >/dev/null 2>&1; then
        # Try libreoffice command instead
        if ! command -v libreoffice >/dev/null 2>&1; then
            error_exit "LibreOffice is not in PATH. Installation may have failed."
        else
            log "Warning: 'core' command not found, but 'libreoffice' is available"
            log "Creating core symlink..."
            check_root
            $SUDO ln -sf /usr/bin/libreoffice /usr/local/bin/core || error_exit "Failed to create core symlink"
        fi
    fi

    # Get version using core command
    local version_output
    if command -v core >/dev/null 2>&1; then
        version_output=$(core --version 2>&1 || echo "")
    else
        version_output=$(libreoffice --version 2>&1 || echo "")
    fi

    if [[ -z "$version_output" ]]; then
        error_exit "Failed to get LibreOffice version"
    fi

    log "Validation successful: $version_output"

    # Extract version number
    local installed_version
    installed_version=$(echo "$version_output" | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "unknown")

    if [[ "$installed_version" == "$TOOL_VERSION"* ]]; then
        log "Version matches: $TOOL_VERSION"
    else
        log "Warning: Version mismatch. Expected: $TOOL_VERSION, Got: $installed_version"
    fi

    return 0
}

# Main installation flow
main() {
    log "Starting LibreOffice $TOOL_VERSION installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "LibreOffice is already installed, validating..."
        validate
        log "Installation verified, nothing to do"
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
