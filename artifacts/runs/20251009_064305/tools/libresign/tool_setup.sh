#!/bin/bash
set -euo pipefail

# ==============================================================================
# LibreSign v12.0.0-beta.2 Installation Script
# ==============================================================================
# Description: Installs LibreSign (Nextcloud app for PDF document signing)
# Version: v12.0.0-beta.2
# Prerequisites: PHP 8.1+, Nextcloud, Composer, Node.js 22+, npm 10.5+
# Validation: occ command to verify app installation
# ==============================================================================

readonly VERSION="v12.0.0-beta.2"
readonly VERSION_NUMBER="12.0.0-beta.2"
readonly TOOL_NAME="libresign"
readonly GITHUB_REPO="LibreSign/libresign"
readonly DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/archive/refs/tags/${VERSION}.tar.gz"

# Nextcloud configuration
readonly NEXTCLOUD_VERSION="32.0.0"
readonly NEXTCLOUD_DIR="/var/www/html/nextcloud"
readonly NEXTCLOUD_DATA_DIR="/var/www/html/nextcloud/data"
readonly NEXTCLOUD_APPS_DIR="${NEXTCLOUD_DIR}/custom_apps"
readonly WEB_USER="www-data"

# PHP version requirements
readonly PHP_MIN_VERSION="8.1"
readonly PHP_RECOMMENDED_VERSION="8.3"

# Node.js version requirements
readonly NODE_MIN_VERSION="22.0.0"
readonly NPM_MIN_VERSION="10.5.0"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

# Version comparison function
version_ge() {
    # Returns 0 if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# ==============================================================================
# PREREQUISITE DETECTION
# ==============================================================================
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for PHP
    if command -v php >/dev/null 2>&1; then
        local php_version
        php_version=$(php -r 'echo PHP_VERSION;')
        log "Found PHP version: ${php_version}"

        if ! version_ge "${php_version}" "${PHP_MIN_VERSION}"; then
            log_error "PHP ${PHP_MIN_VERSION}+ is required, found ${php_version}"
            missing_prereqs=1
        fi
    else
        log "PHP not found - will install"
        missing_prereqs=1
    fi

    # Check for Composer
    if command -v composer >/dev/null 2>&1; then
        log "Found Composer: $(composer --version --no-interaction 2>/dev/null | head -n1 || echo 'unknown')"
    else
        log "Composer not found - will install"
        missing_prereqs=1
    fi

    # Check for Node.js
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node --version | sed 's/v//')
        log "Found Node.js version: ${node_version}"

        if ! version_ge "${node_version}" "${NODE_MIN_VERSION}"; then
            log_error "Node.js ${NODE_MIN_VERSION}+ is required, found ${node_version}"
            missing_prereqs=1
        fi
    else
        log "Node.js not found - will install"
        missing_prereqs=1
    fi

    # Check for npm
    if command -v npm >/dev/null 2>&1; then
        local npm_version
        npm_version=$(npm --version)
        log "Found npm version: ${npm_version}"

        if ! version_ge "${npm_version}" "${NPM_MIN_VERSION}"; then
            log_error "npm ${NPM_MIN_VERSION}+ is required, found ${npm_version}"
            missing_prereqs=1
        fi
    else
        log "npm not found - will install"
        missing_prereqs=1
    fi

    # Check for unzip
    if ! command -v unzip >/dev/null 2>&1; then
        log "unzip not found - will install"
        missing_prereqs=1
    fi

    # Check for wget or curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        log "wget or curl not found - will install"
        missing_prereqs=1
    fi

    # Check for poppler-utils (required by LibreSign)
    if ! command -v pdfinfo >/dev/null 2>&1; then
        log "poppler-utils not found - will install"
        missing_prereqs=1
    fi

    return ${missing_prereqs}
}

# ==============================================================================
# PREREQUISITE INSTALLATION
# ==============================================================================
install_prerequisites() {
    log "Installing missing prerequisites..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq

    # Install basic tools
    log "Installing basic tools..."
    apt-get install -y -qq \
        wget \
        curl \
        unzip \
        git \
        gnupg \
        ca-certificates \
        software-properties-common \
        lsb-release \
        apt-transport-https

    # Install PHP 8.3 (recommended version)
    if ! command -v php >/dev/null 2>&1 || ! version_ge "$(php -r 'echo PHP_VERSION;')" "${PHP_MIN_VERSION}"; then
        log "Installing PHP ${PHP_RECOMMENDED_VERSION} and required extensions..."

        # Add Ondřej Surý's PPA for PHP
        add-apt-repository ppa:ondrej/php -y
        apt-get update -qq

        apt-get install -y -qq \
            php${PHP_RECOMMENDED_VERSION}-fpm \
            php${PHP_RECOMMENDED_VERSION}-cli \
            php${PHP_RECOMMENDED_VERSION}-common \
            php${PHP_RECOMMENDED_VERSION}-curl \
            php${PHP_RECOMMENDED_VERSION}-gd \
            php${PHP_RECOMMENDED_VERSION}-mbstring \
            php${PHP_RECOMMENDED_VERSION}-xml \
            php${PHP_RECOMMENDED_VERSION}-zip \
            php${PHP_RECOMMENDED_VERSION}-intl \
            php${PHP_RECOMMENDED_VERSION}-bcmath \
            php${PHP_RECOMMENDED_VERSION}-gmp \
            php${PHP_RECOMMENDED_VERSION}-mysql \
            php${PHP_RECOMMENDED_VERSION}-pgsql \
            php${PHP_RECOMMENDED_VERSION}-sqlite3 \
            php${PHP_RECOMMENDED_VERSION}-redis \
            php${PHP_RECOMMENDED_VERSION}-imagick \
            php${PHP_RECOMMENDED_VERSION}-opcache

        # Set PHP 8.3 as default
        update-alternatives --set php /usr/bin/php${PHP_RECOMMENDED_VERSION}
    fi

    # Install Composer
    if ! command -v composer >/dev/null 2>&1; then
        log "Installing Composer..."

        local composer_installer="/tmp/composer-installer.php"
        local expected_signature="/tmp/composer-installer.sig"

        # Download the installer signature from official source
        wget -q -O "${expected_signature}" https://composer.github.io/installer.sig

        # Download the installer
        wget -q -O "${composer_installer}" https://getcomposer.org/installer

        # Verify installer signature
        local actual_hash
        actual_hash=$(php -r "echo hash_file('sha384', '${composer_installer}');")

        local expected_hash
        expected_hash=$(cat "${expected_signature}")

        if [ "${expected_hash}" != "${actual_hash}" ]; then
            log_error "Composer installer hash mismatch!"
            log_error "Expected: ${expected_hash}"
            log_error "Got: ${actual_hash}"
            rm -f "${composer_installer}" "${expected_signature}"
            exit 1
        fi

        php "${composer_installer}" --install-dir=/usr/local/bin --filename=composer --quiet
        rm -f "${composer_installer}" "${expected_signature}"

        chmod +x /usr/local/bin/composer
    fi

    # Install Node.js 22.x
    if ! command -v node >/dev/null 2>&1 || ! version_ge "$(node --version | sed 's/v//')" "${NODE_MIN_VERSION}"; then
        log "Installing Node.js 22.x..."

        # Add NodeSource repository for Node.js 22.x
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y -qq nodejs
    fi

    # Install poppler-utils (required by LibreSign)
    log "Installing poppler-utils..."
    apt-get install -y -qq poppler-utils

    # Install additional dependencies for Nextcloud
    log "Installing additional dependencies..."
    apt-get install -y -qq \
        apache2 \
        libapache2-mod-php \
        mariadb-server \
        sudo

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log_success "Prerequisites installed successfully"
}

# ==============================================================================
# PREREQUISITE VERIFICATION
# ==============================================================================
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify PHP
    if ! command -v php >/dev/null 2>&1; then
        log_error "PHP installation failed"
        exit 1
    fi

    local php_version
    php_version=$(php -r 'echo PHP_VERSION;')

    if ! version_ge "${php_version}" "${PHP_MIN_VERSION}"; then
        log_error "PHP ${PHP_MIN_VERSION}+ is required, found ${php_version}"
        exit 1
    fi

    log_success "PHP ${php_version} is installed and meets requirements"

    # Verify Composer
    if ! command -v composer >/dev/null 2>&1; then
        log_error "Composer installation failed"
        exit 1
    fi

    log_success "Composer is installed: $(composer --version --no-interaction 2>/dev/null | head -n1 || echo 'unknown')"

    # Verify Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js installation failed"
        exit 1
    fi

    local node_version
    node_version=$(node --version | sed 's/v//')

    if ! version_ge "${node_version}" "${NODE_MIN_VERSION}"; then
        log_error "Node.js ${NODE_MIN_VERSION}+ is required, found ${node_version}"
        exit 1
    fi

    log_success "Node.js ${node_version} is installed and meets requirements"

    # Verify npm
    if ! command -v npm >/dev/null 2>&1; then
        log_error "npm installation failed"
        exit 1
    fi

    local npm_version
    npm_version=$(npm --version)

    if ! version_ge "${npm_version}" "${NPM_MIN_VERSION}"; then
        log_error "npm ${NPM_MIN_VERSION}+ is required, found ${npm_version}"
        exit 1
    fi

    log_success "npm ${npm_version} is installed and meets requirements"

    # Verify poppler-utils
    if ! command -v pdfinfo >/dev/null 2>&1; then
        log_error "poppler-utils installation failed"
        exit 1
    fi

    log_success "poppler-utils is installed"

    log_success "All prerequisites verified successfully"
}

# ==============================================================================
# CHECK EXISTING INSTALLATION
# ==============================================================================
check_existing_installation() {
    log "Checking for existing LibreSign installation..."

    # Check if Nextcloud is installed
    if [ ! -d "${NEXTCLOUD_DIR}" ]; then
        log "Nextcloud not found at ${NEXTCLOUD_DIR}"
        return 1
    fi

    # Check if LibreSign app directory exists
    if [ ! -d "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}" ]; then
        log "LibreSign app not found"
        return 1
    fi

    # Check if the correct version is installed
    local app_info_file="${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}/appinfo/info.xml"
    if [ -f "${app_info_file}" ]; then
        local installed_version
        installed_version=$(grep -oPm1 "(?<=<version>)[^<]+" "${app_info_file}" || echo "unknown")

        if [ "${installed_version}" = "${VERSION_NUMBER}" ]; then
            log_success "LibreSign ${VERSION_NUMBER} is already installed"
            return 0
        else
            log "Different version installed: ${installed_version}, expected: ${VERSION_NUMBER}"
            return 1
        fi
    fi

    return 1
}

# ==============================================================================
# INSTALL NEXTCLOUD
# ==============================================================================
install_nextcloud() {
    log "Installing Nextcloud ${NEXTCLOUD_VERSION}..."

    # Create directories
    mkdir -p "${NEXTCLOUD_DIR}"
    mkdir -p "${NEXTCLOUD_APPS_DIR}"

    # Download Nextcloud
    local nextcloud_archive="/tmp/nextcloud.tar.bz2"
    local nextcloud_url="https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"

    log "Downloading Nextcloud from ${nextcloud_url}..."
    wget -q -O "${nextcloud_archive}" "${nextcloud_url}"

    # Extract Nextcloud
    log "Extracting Nextcloud..."
    tar -xjf "${nextcloud_archive}" -C /var/www/html/
    rm -f "${nextcloud_archive}"

    # Create custom_apps directory
    mkdir -p "${NEXTCLOUD_APPS_DIR}"

    # Set permissions
    chown -R ${WEB_USER}:${WEB_USER} "${NEXTCLOUD_DIR}"
    chmod -R 755 "${NEXTCLOUD_DIR}"

    # Create config directory if it doesn't exist
    mkdir -p "${NEXTCLOUD_DIR}/config"
    chown ${WEB_USER}:${WEB_USER} "${NEXTCLOUD_DIR}/config"

    # Create a minimal config for OCC to work
    cat > "${NEXTCLOUD_DIR}/config/config.php" <<'EOF'
<?php
$CONFIG = array (
  'apps_paths' => array (
    0 => array (
      'path' => '/var/www/html/nextcloud/apps',
      'url' => '/apps',
      'writable' => false,
    ),
    1 => array (
      'path' => '/var/www/html/nextcloud/custom_apps',
      'url' => '/custom_apps',
      'writable' => true,
    ),
  ),
  'datadirectory' => '/var/www/html/nextcloud/data',
  'installed' => true,
  'instanceid' => 'oc_libresign_test',
);
EOF

    chown ${WEB_USER}:${WEB_USER} "${NEXTCLOUD_DIR}/config/config.php"
    chmod 640 "${NEXTCLOUD_DIR}/config/config.php"

    # Create data directory
    mkdir -p "${NEXTCLOUD_DATA_DIR}"
    chown -R ${WEB_USER}:${WEB_USER} "${NEXTCLOUD_DATA_DIR}"
    chmod 770 "${NEXTCLOUD_DATA_DIR}"

    log_success "Nextcloud installed successfully"
}

# ==============================================================================
# INSTALL LIBRESIGN
# ==============================================================================
install_tool() {
    log "Starting LibreSign ${VERSION} installation..."

    # Check if Nextcloud is installed, if not, install it
    if [ ! -d "${NEXTCLOUD_DIR}" ]; then
        install_nextcloud
    fi

    # Create custom_apps directory if it doesn't exist
    mkdir -p "${NEXTCLOUD_APPS_DIR}"

    # Download LibreSign
    local download_archive="/tmp/${TOOL_NAME}-${VERSION}.tar.gz"

    log "Downloading LibreSign ${VERSION}..."
    wget -q -O "${download_archive}" "${DOWNLOAD_URL}"

    # Verify download
    if [ ! -f "${download_archive}" ]; then
        log_error "Failed to download LibreSign from ${DOWNLOAD_URL}"
        exit 1
    fi

    # Note: GitHub doesn't provide checksums for archive downloads via tags
    # We'll verify the integrity by checking the extracted files

    # Extract to custom_apps directory
    log "Extracting LibreSign to ${NEXTCLOUD_APPS_DIR}..."

    # Remove existing installation if present
    if [ -d "${NEXTCLOUD_APPS_DIR:?}/${TOOL_NAME:?}" ]; then
        log "Removing existing LibreSign installation..."
        rm -rf "${NEXTCLOUD_APPS_DIR:?}/${TOOL_NAME:?}"
    fi

    # Extract (GitHub archives extract to a directory named repo-tag)
    tar -xzf "${download_archive}" -C /tmp/
    mv "/tmp/${TOOL_NAME}-${VERSION_NUMBER}" "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"

    rm -f "${download_archive}"

    # Set proper permissions
    chown -R ${WEB_USER}:${WEB_USER} "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"
    chmod -R 755 "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"

    # Install PHP dependencies
    log "Installing PHP dependencies with Composer..."
    cd "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"

    # Run composer as web user
    sudo -u ${WEB_USER} composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader

    # Install Node.js dependencies
    log "Installing Node.js dependencies..."
    sudo -u ${WEB_USER} npm ci --production

    # Build frontend assets
    log "Building frontend assets..."
    sudo -u ${WEB_USER} npm run build

    log_success "LibreSign ${VERSION} installed successfully"
}

# ==============================================================================
# VALIDATION
# ==============================================================================
validate() {
    log "Validating LibreSign installation..."

    # Check if app directory exists
    if [ ! -d "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}" ]; then
        log_error "LibreSign app directory not found at ${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"
        exit 1
    fi

    # Check if info.xml exists
    local app_info_file="${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}/appinfo/info.xml"
    if [ ! -f "${app_info_file}" ]; then
        log_error "LibreSign app info file not found at ${app_info_file}"
        exit 1
    fi

    # Extract and verify version
    local installed_version
    installed_version=$(grep -oPm1 "(?<=<version>)[^<]+" "${app_info_file}" || echo "unknown")

    if [ "${installed_version}" != "${VERSION_NUMBER}" ]; then
        log_error "Version mismatch! Expected: ${VERSION_NUMBER}, Found: ${installed_version}"
        exit 1
    fi

    log_success "Version verified: ${installed_version}"

    # Check if OCC command works
    if [ ! -f "${NEXTCLOUD_DIR}/occ" ]; then
        log_error "Nextcloud OCC command not found at ${NEXTCLOUD_DIR}/occ"
        exit 1
    fi

    # List apps to verify LibreSign is recognized
    log "Checking LibreSign app status via OCC..."
    cd "${NEXTCLOUD_DIR}"

    if sudo -u ${WEB_USER} php occ app:list | grep -q "${TOOL_NAME}"; then
        log_success "LibreSign is recognized by Nextcloud"
    else
        log_error "LibreSign is not recognized by Nextcloud"
        exit 1
    fi

    # Verify key files exist
    local key_files=(
        "appinfo/info.xml"
        "lib/AppInfo/Application.php"
        "composer.json"
        "package.json"
    )

    for file in "${key_files[@]}"; do
        if [ ! -f "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}/${file}" ]; then
            log_error "Required file missing: ${file}"
            exit 1
        fi
    done

    log_success "All required files present"

    # Check if vendor directory exists (Composer dependencies installed)
    if [ ! -d "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}/vendor" ]; then
        log_error "Composer dependencies not installed (vendor directory missing)"
        exit 1
    fi

    log_success "Composer dependencies installed"

    # Check if node_modules exists (npm dependencies installed)
    if [ ! -d "${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}/node_modules" ]; then
        log_error "npm dependencies not installed (node_modules directory missing)"
        exit 1
    fi

    log_success "npm dependencies installed"

    # Final validation message
    log_success "LibreSign ${VERSION_NUMBER} installation validated successfully!"
    log "Installation location: ${NEXTCLOUD_APPS_DIR}/${TOOL_NAME}"
    log "To enable the app, run: sudo -u ${WEB_USER} php ${NEXTCLOUD_DIR}/occ app:enable ${TOOL_NAME}"

    return 0
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
main() {
    log "Starting LibreSign ${VERSION} installation..."
    log "========================================================================"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log_success "All prerequisites already installed"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log_success "LibreSign ${VERSION_NUMBER} is already installed and validated"
        validate
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "========================================================================"
    log_success "LibreSign ${VERSION} installation completed successfully!"
    log ""
    log "Next steps:"
    log "1. Enable the app: sudo -u ${WEB_USER} php ${NEXTCLOUD_DIR}/occ app:enable ${TOOL_NAME}"
    log "2. Access LibreSign settings in Nextcloud admin panel"
    log "3. Click 'Download binaries' to install LibreSign dependencies (Java, PDFtk, etc.)"
    log "   Or run: sudo -u ${WEB_USER} php ${NEXTCLOUD_DIR}/occ libresign:install --all"
}

# Run main function
main "$@"
