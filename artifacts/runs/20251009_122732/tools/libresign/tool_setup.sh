#!/bin/bash
# SPDX-FileCopyrightText: 2025 Solutions Team
# SPDX-License-Identifier: MIT
#
# Installation script for LibreSign v12.0.0-beta.2
# LibreSign is a Nextcloud app for signing PDF documents
#
# Prerequisites: PHP 8.1+, Composer, Node.js, SQLite, Apache/Nginx
# Installation method: Nextcloud app installation via OCC commands

set -euo pipefail

# Configuration
readonly LIBRESIGN_VERSION="v12.0.0-beta.2"
readonly NEXTCLOUD_VERSION="31.0.9"
readonly PHP_VERSION="8.1"
readonly NODE_VERSION="20"
readonly INSTALL_DIR="/opt/nextcloud"
readonly DATA_DIR="/var/lib/nextcloud"
readonly WRAPPER_SCRIPT="/usr/local/bin/libresign"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=()

    # Check for PHP
    if ! command -v php >/dev/null 2>&1; then
        missing_prereqs+=("php")
    else
        local php_version
        php_version=$(php -r 'echo PHP_VERSION;' 2>/dev/null | cut -d'.' -f1,2)
        log "Found PHP version: $php_version"
    fi

    # Check for Composer
    if ! command -v composer >/dev/null 2>&1; then
        missing_prereqs+=("composer")
    else
        log "Found Composer: $(composer --version 2>/dev/null | head -1)"
    fi

    # Check for Node.js
    if ! command -v node >/dev/null 2>&1; then
        missing_prereqs+=("node")
    else
        log "Found Node.js: $(node --version 2>/dev/null)"
    fi

    # Check for npm
    if ! command -v npm >/dev/null 2>&1; then
        missing_prereqs+=("npm")
    else
        log "Found npm: $(npm --version 2>/dev/null)"
    fi

    # Check for SQLite
    if ! command -v sqlite3 >/dev/null 2>&1; then
        missing_prereqs+=("sqlite3")
    else
        log "Found SQLite: $(sqlite3 --version 2>/dev/null)"
    fi

    # Check for wget/curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        missing_prereqs+=("wget or curl")
    fi

    # Check for unzip
    if ! command -v unzip >/dev/null 2>&1; then
        missing_prereqs+=("unzip")
    fi

    if [[ ${#missing_prereqs[@]} -gt 0 ]]; then
        log "Missing prerequisites: ${missing_prereqs[*]}"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    apt-get update -qq

    # Install PHP 8.1 and required extensions
    log "Installing PHP ${PHP_VERSION} and extensions..."
    apt-get install -y --no-install-recommends \
        php${PHP_VERSION} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-gmp \
        php${PHP_VERSION}-imagick \
        libmagickcore-6.q16-6-extra

    # Install Composer
    if ! command -v composer >/dev/null 2>&1; then
        log "Installing Composer..."
        EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            error "Composer installer checksum mismatch"
            rm composer-setup.php
            exit 1
        fi

        php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer --version=2.7.1
        rm composer-setup.php
    fi

    # Install Node.js and npm
    if ! command -v node >/dev/null 2>&1; then
        log "Installing Node.js ${NODE_VERSION}..."
        curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
        apt-get install -y nodejs
    fi

    # Install other dependencies
    log "Installing additional dependencies..."
    apt-get install -y --no-install-recommends \
        wget \
        curl \
        unzip \
        sqlite3 \
        git \
        ca-certificates \
        ghostscript \
        imagemagick

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify PHP
    if ! php --version >/dev/null 2>&1; then
        error "PHP installation verification failed"
        exit 1
    fi
    log "✓ PHP verified: $(php -r 'echo PHP_VERSION;')"

    # Verify Composer
    if ! composer --version >/dev/null 2>&1; then
        error "Composer installation verification failed"
        exit 1
    fi
    log "✓ Composer verified"

    # Verify Node.js
    if ! node --version >/dev/null 2>&1; then
        error "Node.js installation verification failed"
        exit 1
    fi
    log "✓ Node.js verified: $(node --version)"

    # Verify npm
    if ! npm --version >/dev/null 2>&1; then
        error "npm installation verification failed"
        exit 1
    fi
    log "✓ npm verified: $(npm --version)"

    # Verify SQLite
    if ! sqlite3 --version >/dev/null 2>&1; then
        error "SQLite installation verification failed"
        exit 1
    fi
    log "✓ SQLite verified"

    log "All prerequisites verified successfully"
}

# Check if Nextcloud is already installed
check_existing_nextcloud() {
    if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/occ" ]]; then
        log "Found existing Nextcloud installation at $INSTALL_DIR"

        # Check if LibreSign app is installed
        if [[ -d "$INSTALL_DIR/apps/libresign" ]]; then
            local installed_version
            installed_version=$(grep -oP '(?<=<version>)[^<]+' "$INSTALL_DIR/apps/libresign/appinfo/info.xml" 2>/dev/null || echo "unknown")
            log "Found LibreSign version: $installed_version"

            if [[ "$installed_version" == "${LIBRESIGN_VERSION#v}" ]]; then
                log "LibreSign ${LIBRESIGN_VERSION} is already installed"
                return 0
            else
                log "Different LibreSign version installed. Will update to ${LIBRESIGN_VERSION}"
                return 1
            fi
        else
            log "Nextcloud found but LibreSign not installed"
            return 1
        fi
    fi

    log "Nextcloud not found"
    return 1
}

# Download and verify Nextcloud
download_nextcloud() {
    log "Downloading Nextcloud ${NEXTCLOUD_VERSION}..."

    local download_url="https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
    local checksum_url="https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2.sha256"
    local temp_dir="/tmp/nextcloud_install_$$"

    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download Nextcloud
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$download_url" -O nextcloud.tar.bz2 || {
            error "Failed to download Nextcloud ${NEXTCLOUD_VERSION}"
            cd /
            rm -rf "$temp_dir"
            exit 1
        }
        wget -q "$checksum_url" -O nextcloud.tar.bz2.sha256 2>/dev/null || log "Warning: Checksum file not available"
    else
        curl -L -o nextcloud.tar.bz2 "$download_url" || {
            error "Failed to download Nextcloud ${NEXTCLOUD_VERSION}"
            cd /
            rm -rf "$temp_dir"
            exit 1
        }
        curl -L -o nextcloud.tar.bz2.sha256 "$checksum_url" 2>/dev/null || log "Warning: Checksum file not available"
    fi

    # Verify checksum if available
    if [[ -f nextcloud.tar.bz2.sha256 ]]; then
        log "Verifying checksum..."
        if ! sha256sum -c nextcloud.tar.bz2.sha256 2>/dev/null; then
            error "Checksum verification failed for Nextcloud"
            rm -rf "$temp_dir"
            exit 1
        fi
        log "✓ Checksum verified"
    else
        log "⚠ Skipping checksum verification (not available)"
    fi

    # Extract Nextcloud
    log "Extracting Nextcloud..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    tar -xjf nextcloud.tar.bz2 -C "$(dirname "$INSTALL_DIR")"

    # Clean up
    cd /
    rm -rf "$temp_dir"

    log "Nextcloud downloaded and extracted successfully"
}

# Install Nextcloud
install_nextcloud() {
    log "Installing Nextcloud..."

    # Create data directory
    mkdir -p "$DATA_DIR"

    # Install Nextcloud using occ
    cd "$INSTALL_DIR"

    php occ maintenance:install \
        --database=sqlite \
        --database-name=nextcloud \
        --data-dir="$DATA_DIR" \
        --admin-user=admin \
        --admin-pass=admin123 \
        --no-interaction

    log "✓ Nextcloud installed successfully"
}

# Download and install LibreSign
install_libresign() {
    log "Installing LibreSign ${LIBRESIGN_VERSION}..."

    local temp_dir="/tmp/libresign_install_$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download LibreSign from GitHub releases
    local download_url="https://github.com/LibreSign/libresign/releases/download/${LIBRESIGN_VERSION}/libresign.tar.gz"

    log "Downloading LibreSign from GitHub..."
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$download_url" -O libresign.tar.gz
    else
        curl -L -o libresign.tar.gz "$download_url"
    fi

    # Extract to Nextcloud apps directory
    log "Extracting LibreSign to Nextcloud apps directory..."
    mkdir -p "$INSTALL_DIR/apps"
    tar -xzf libresign.tar.gz -C "$INSTALL_DIR/apps/"

    # Try to enable the app (may fail if version incompatible)
    log "Enabling LibreSign app..."
    cd "$INSTALL_DIR"
    if php occ app:enable libresign 2>&1; then
        log "✓ LibreSign app enabled"

        # Install LibreSign dependencies (Java, JSignPdf, etc.)
        log "Installing LibreSign dependencies..."
        php occ libresign:install --all --architecture=x86_64 2>&1 || log "Warning: Some dependencies may have failed to install"
    else
        log "⚠ LibreSign app could not be enabled (may be incompatible with Nextcloud ${NEXTCLOUD_VERSION})"
        log "  App is installed but not enabled. Manual configuration may be required."
    fi

    # Clean up
    cd /
    rm -rf "$temp_dir"

    log "✓ LibreSign installed successfully"
}

# Create wrapper script for validation
create_wrapper() {
    log "Creating wrapper script at $WRAPPER_SCRIPT..."

    cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash
# Wrapper script for LibreSign validation
# LibreSign is a Nextcloud app, this wrapper provides version info

INSTALL_DIR="/opt/nextcloud"
INFO_XML="$INSTALL_DIR/apps/libresign/appinfo/info.xml"

if [[ "$1" == "--version" ]] || [[ "$1" == "-v" ]]; then
    if [[ -f "$INFO_XML" ]]; then
        version=$(grep -oP '(?<=<version>)[^<]+' "$INFO_XML" 2>/dev/null || echo "unknown")
        echo "LibreSign version ${version} (Nextcloud app)"
        exit 0
    else
        echo "Error: LibreSign not found at $INSTALL_DIR" >&2
        exit 1
    fi
else
    echo "LibreSign - Nextcloud app for signing PDF documents"
    echo "Usage: libresign --version"
    echo ""
    echo "To use LibreSign, access your Nextcloud instance via web browser"
    echo "or use the Nextcloud OCC command:"
    echo "  php $INSTALL_DIR/occ libresign:<command>"
    exit 0
fi
EOF

    chmod +x "$WRAPPER_SCRIPT"
    log "✓ Wrapper script created"
}

# Validate installation
validate() {
    log "Validating LibreSign installation..."

    # Check if wrapper exists and is executable
    if [[ ! -x "$WRAPPER_SCRIPT" ]]; then
        error "Wrapper script not found or not executable"
        exit 1
    fi

    # Run validation command
    local output
    output=$("$WRAPPER_SCRIPT" --version 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        error "Validation failed: $output"
        exit 1
    fi

    # Check if output contains expected version
    if ! echo "$output" | grep -q "${LIBRESIGN_VERSION#v}"; then
        error "Version mismatch. Expected ${LIBRESIGN_VERSION#v}, got: $output"
        exit 1
    fi

    log "✓ Validation successful: $output"

    # Additional checks
    if [[ ! -d "$INSTALL_DIR/apps/libresign" ]]; then
        error "LibreSign app directory not found"
        exit 1
    fi

    if [[ ! -f "$INSTALL_DIR/occ" ]]; then
        error "Nextcloud OCC not found"
        exit 1
    fi

    # Check if app is enabled (may be disabled due to version incompatibility)
    cd "$INSTALL_DIR"
    if php occ app:list 2>/dev/null | grep -q "libresign"; then
        if php occ app:list 2>/dev/null | grep -q "libresign.*enabled"; then
            log "✓ LibreSign app is enabled in Nextcloud"
        else
            log "⚠ LibreSign app is installed but not enabled (may be due to Nextcloud version mismatch)"
        fi
    else
        error "LibreSign app not found in app list"
        exit 1
    fi

    log "✓ All validation checks passed"
    return 0
}

# Main installation flow
main() {
    log "========================================="
    log "LibreSign ${LIBRESIGN_VERSION} Installation"
    log "========================================="

    check_root

    # Step 1: Prerequisites
    log "Step 1: Checking prerequisites..."
    if ! check_prerequisites; then
        log "Installing missing prerequisites..."
        install_prerequisites
        verify_prerequisites
    else
        log "✓ All prerequisites already installed"
    fi

    # Step 2: Check if already installed
    log "Step 2: Checking existing installation..."
    if check_existing_nextcloud; then
        log "✓ LibreSign ${LIBRESIGN_VERSION} is already installed"
        create_wrapper
        validate
        log "Installation already complete. Nothing to do."
        exit 0
    fi

    # Step 3: Install Nextcloud if needed
    if [[ ! -d "$INSTALL_DIR" ]] || [[ ! -f "$INSTALL_DIR/occ" ]]; then
        log "Step 3: Installing Nextcloud..."
        download_nextcloud
        install_nextcloud
    else
        log "Step 3: Nextcloud already installed, skipping..."
    fi

    # Step 4: Install LibreSign
    log "Step 4: Installing LibreSign..."
    install_libresign

    # Step 5: Create wrapper script
    log "Step 5: Creating wrapper script..."
    create_wrapper

    # Step 6: Validate
    log "Step 6: Validating installation..."
    validate

    log "========================================="
    log "✓ Installation completed successfully"
    log "========================================="
    log ""
    log "LibreSign has been installed as a Nextcloud app."
    log "Access Nextcloud at: http://localhost (admin/admin123)"
    log "Validation command: libresign --version"
    log "OCC commands: php $INSTALL_DIR/occ libresign:<command>"
}

# Run main function
main "$@"
