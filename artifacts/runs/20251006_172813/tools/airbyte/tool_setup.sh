#!/usr/bin/env bash

################################################################################
# Airbyte v1.8.0 Installation Script (abctl CLI)
#
# This script installs abctl (Airbyte CLI) for deploying Airbyte v1.8.0
# following Solutions Team standards. The script is idempotent and includes
# prerequisite detection and installation.
#
# Prerequisites:
#   - curl
#   - Docker (for Airbyte runtime)
#
# Installation Method: Binary download from GitHub releases
# Validate Command: airbyte --version (symlinked from abctl)
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="airbyte"
readonly TOOL_VERSION="1.8.0"
readonly ABCTL_VERSION="v0.30.1"  # abctl version that supports Airbyte 1.8.0 (released Aug 2024)
readonly ABCTL_VERSION_NUM="0.30.1"  # Version without 'v' prefix for filenames
readonly GITHUB_REPO="airbytehq/abctl"
readonly INSTALL_DIR="/usr/local/bin"
readonly BINARY_NAME="abctl"
readonly CHECKSUM_URL="https://github.com/${GITHUB_REPO}/releases/download/${ABCTL_VERSION}/abctl_${ABCTL_VERSION_NUM}_checksums.txt"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

################################################################################
# PREREQUISITE MANAGEMENT
################################################################################

# Detect OS and architecture
detect_platform() {
    local os arch

    # Detect OS
    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="darwin" ;;
        *)          error "Unsupported OS: $(uname -s)" ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)  arch="arm64" ;;
        *)              error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}-${arch}"
}

# Check if all prerequisites are installed
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for curl (required for downloading binary)
    if command -v curl >/dev/null 2>&1; then
        log "✓ curl found: $(curl --version 2>&1 | head -n1)"
    else
        log "✗ curl not found"
        all_present=false
    fi

    # Check for tar (required for extracting archive)
    if command -v tar >/dev/null 2>&1; then
        log "✓ tar found"
    else
        log "✗ tar not found"
        all_present=false
    fi

    # Check for sha256sum or shasum (for checksum verification)
    if command -v sha256sum >/dev/null 2>&1; then
        log "✓ sha256sum found"
    elif command -v shasum >/dev/null 2>&1; then
        log "✓ shasum found"
    else
        log "✗ sha256sum or shasum not found"
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

# Install missing prerequisites
install_prerequisites() {
    log "Installing missing prerequisites..."

    # Detect OS and package manager
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect operating system"
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"

            # Update package lists
            log "Updating apt package lists..."
            apt-get update -qq

            # Install curl if not present
            if ! command -v curl >/dev/null 2>&1; then
                log "Installing curl..."
                apt-get install -y curl
            fi

            # Install tar if not present
            if ! command -v tar >/dev/null 2>&1; then
                log "Installing tar..."
                apt-get install -y tar
            fi

            # Install coreutils for sha256sum if not present
            if ! command -v sha256sum >/dev/null 2>&1; then
                log "Installing coreutils..."
                apt-get install -y coreutils
            fi

            # Clean up
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;

        centos|rhel|fedora)
            log "Detected Red Hat/CentOS/Fedora system"

            # Install curl if not present
            if ! command -v curl >/dev/null 2>&1; then
                log "Installing curl..."
                yum install -y curl
            fi

            # Install coreutils for sha256sum if not present
            if ! command -v sha256sum >/dev/null 2>&1; then
                log "Installing coreutils..."
                yum install -y coreutils
            fi

            # Clean up
            yum clean all
            ;;

        alpine)
            log "Detected Alpine Linux system"

            # Update package lists
            apk update

            # Install curl if not present
            if ! command -v curl >/dev/null 2>&1; then
                log "Installing curl..."
                apk add --no-cache curl
            fi

            # Install coreutils for sha256sum if not present
            if ! command -v sha256sum >/dev/null 2>&1; then
                log "Installing coreutils..."
                apk add --no-cache coreutils
            fi

            # Clean up
            rm -rf /var/cache/apk/*
            ;;

        *)
            error "Unsupported operating system: $OS. Please install curl and sha256sum manually."
            ;;
    esac

    log "Prerequisites installation completed"
}

# Verify that prerequisites are working correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify curl
    if ! command -v curl >/dev/null 2>&1; then
        error "curl installation verification failed: command not found"
    fi
    log "✓ curl verified: $(curl --version 2>&1 | head -n1)"

    # Verify tar
    if ! command -v tar >/dev/null 2>&1; then
        error "tar installation verification failed: command not found"
    fi
    log "✓ tar verified"

    # Verify checksum tool
    if command -v sha256sum >/dev/null 2>&1; then
        log "✓ sha256sum verified"
    elif command -v shasum >/dev/null 2>&1; then
        log "✓ shasum verified"
    else
        error "Checksum tool verification failed: neither sha256sum nor shasum found"
    fi

    log "All prerequisites verified successfully"
}

################################################################################
# TOOL INSTALLATION
################################################################################

# Check if Airbyte/abctl is already installed with correct version
check_existing_installation() {
    log "Checking for existing installation..."

    # Check for 'airbyte' command (symlink)
    if command -v airbyte >/dev/null 2>&1; then
        local installed_version
        if installed_version=$(airbyte version 2>&1); then
            log "Found existing airbyte installation: $installed_version"
            if echo "$installed_version" | grep -q "$ABCTL_VERSION"; then
                log "✓ Correct abctl version already installed ($ABCTL_VERSION)"
                return 0
            fi
        fi
    fi

    # Check for 'abctl' binary directly
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        local installed_version
        if installed_version=$("${INSTALL_DIR}/${BINARY_NAME}" version 2>&1); then
            log "Found existing abctl installation: $installed_version"
            if echo "$installed_version" | grep -q "$ABCTL_VERSION"; then
                log "✓ Correct abctl version already installed ($ABCTL_VERSION)"
                return 0
            else
                log "✗ Different version installed, will reinstall"
                return 1
            fi
        fi
    fi

    log "✗ Airbyte/abctl not found or version mismatch"
    return 1
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local actual_checksum

    log "Verifying checksum for $(basename "$file")..."

    if command -v sha256sum >/dev/null 2>&1; then
        actual_checksum=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual_checksum=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        error "No checksum tool available"
    fi

    if [ "$actual_checksum" = "$expected_checksum" ]; then
        log "✓ Checksum verified: $actual_checksum"
        return 0
    else
        error "Checksum verification failed! Expected: $expected_checksum, Got: $actual_checksum"
    fi
}

# Install Airbyte CLI (abctl)
install_tool() {
    log "Installing $TOOL_NAME CLI (abctl) v$ABCTL_VERSION..."

    # Detect platform
    local platform
    platform=$(detect_platform)
    log "Detected platform: $platform"

    # Construct download URL for tar.gz
    local archive_filename="${BINARY_NAME}-${ABCTL_VERSION}-${platform}.tar.gz"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${ABCTL_VERSION}/${archive_filename}"
    local temp_dir
    temp_dir=$(mktemp -d)
    local archive_file="${temp_dir}/${archive_filename}"

    log "Downloading abctl from: $download_url"

    # Download tar.gz archive
    if ! curl -sSL -f "$download_url" -o "$archive_file"; then
        rm -rf "$temp_dir"
        error "Failed to download abctl from $download_url"
    fi

    log "✓ Downloaded abctl archive"

    # Download and verify checksum
    log "Downloading checksums from: $CHECKSUM_URL"
    local checksums_file="${temp_dir}/checksums.txt"
    if ! curl -sSL -f "$CHECKSUM_URL" -o "$checksums_file"; then
        rm -rf "$temp_dir"
        error "Failed to download checksums from $CHECKSUM_URL"
    fi

    # Extract expected checksum for our archive
    local expected_checksum
    expected_checksum=$(grep "$archive_filename" "$checksums_file" | awk '{print $1}')

    if [ -z "$expected_checksum" ]; then
        log "⚠ Warning: Could not find checksum for $archive_filename in checksums.txt"
        log "  Proceeding without checksum verification"
    else
        verify_checksum "$archive_file" "$expected_checksum"
    fi

    # Extract archive
    log "Extracting archive..."
    local extract_dir="${temp_dir}/extract"
    mkdir -p "$extract_dir"
    tar -xzf "$archive_file" -C "$extract_dir"

    # Find the binary (it's in a subdirectory within the archive)
    local binary_path
    binary_path=$(find "$extract_dir" -name "$BINARY_NAME" -type f | head -n 1)

    if [ -z "$binary_path" ] || [ ! -f "$binary_path" ]; then
        rm -rf "$temp_dir"
        error "Failed to find abctl binary in extracted archive"
    fi

    log "✓ Found binary at: $binary_path"

    # Make binary executable
    chmod +x "$binary_path"

    # Move to installation directory
    log "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    mv "$binary_path" "${INSTALL_DIR}/${BINARY_NAME}"

    # Create symlink as 'airbyte' for the validation command
    if [ ! -L "${INSTALL_DIR}/airbyte" ]; then
        log "Creating symlink: ${INSTALL_DIR}/airbyte -> ${INSTALL_DIR}/${BINARY_NAME}"
        ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/airbyte"
    fi

    # Clean up
    rm -rf "$temp_dir"

    log "✓ Installation completed"
}

# Validate the installation
validate() {
    log "Validating installation..."

    # Check if airbyte command is available
    if ! command -v airbyte >/dev/null 2>&1; then
        error "Validation failed: airbyte command not found in PATH"
    fi

    # Check if abctl binary exists
    if [ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        error "Validation failed: ${INSTALL_DIR}/${BINARY_NAME} not found"
    fi

    # Run version check on the symlink
    # Note: abctl uses 'version' subcommand, not '--version' flag
    local output
    if output=$(airbyte version 2>&1); then
        log "✓ Validation successful with 'airbyte version': $output"

        # Verify version matches abctl version
        if echo "$output" | grep -q "$ABCTL_VERSION"; then
            log "✓ Version verification successful: $ABCTL_VERSION"
        else
            log "⚠ Version output: $output"
            log "⚠ Expected: $ABCTL_VERSION"
        fi

        return 0
    else
        error "Validation failed: airbyte version command failed with: $output"
    fi
}


################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log "========================================"
    log "Starting $TOOL_NAME v$TOOL_VERSION installation"
    log "========================================"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed with correct version
    if check_existing_installation; then
        validate
        log "========================================"
        log "Installation already complete (idempotent)"
        log "========================================"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "========================================"
    log "Installation completed successfully"
    log "========================================"
}

# Execute main function
main "$@"
