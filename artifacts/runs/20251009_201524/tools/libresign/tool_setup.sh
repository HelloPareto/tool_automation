#!/bin/bash
# SPDX-FileCopyrightText: 2024 Solutions Team
# SPDX-License-Identifier: MIT

#######################################
# LibreSign v12.0.0-beta.2 Installation Script
#
# This script installs LibreSign as a Nextcloud app
# Prerequisites: PHP 8.1+, PostgreSQL/MySQL, Nextcloud 32, Node.js, Composer
#######################################

set -euo pipefail

# Version and configuration
readonly LIBRESIGN_VERSION="v12.0.0-beta.2"
readonly LIBRESIGN_TARBALL_URL="https://github.com/LibreSign/libresign/releases/download/v12.0.0-beta.2/libresign.tar.gz"
readonly NEXTCLOUD_VERSION="32.0.0"
readonly PHP_VERSION="8.1"
readonly NODE_VERSION="18"
readonly NEXTCLOUD_INSTALL_DIR="/opt/nextcloud"
readonly NEXTCLOUD_DATA_DIR="/var/www/nextcloud-data"
readonly NEXTCLOUD_APPS_DIR="${NEXTCLOUD_INSTALL_DIR}/apps"

# Parse command line arguments
SKIP_PREREQS=false
if [[ "${RESPECT_SHARED_DEPS:-0}" == "1" ]] || [[ "${1:-}" == "--skip-prereqs" ]]; then
    SKIP_PREREQS=true
fi

#######################################
# Logging function with timestamps
#######################################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

#######################################
# Check if prerequisites are installed
# Returns: 0 if all present, 1 if any missing
#######################################
check_prerequisites() {
    log "Checking prerequisites..."

    local missing=0

    # Check PHP
    if ! command -v php >/dev/null 2>&1; then
        log "  ✗ PHP not found"
        missing=1
    else
        local php_ver
        php_ver=$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo "0")
        log "  ✓ PHP found: $php_ver"
    fi

    # Check PostgreSQL client
    if ! command -v psql >/dev/null 2>&1; then
        log "  ✗ PostgreSQL client (psql) not found"
        missing=1
    else
        log "  ✓ PostgreSQL client found"
    fi

    # Check Node.js
    if ! command -v node >/dev/null 2>&1; then
        log "  ✗ Node.js not found"
        missing=1
    else
        local node_ver
        node_ver=$(node --version 2>/dev/null || echo "unknown")
        log "  ✓ Node.js found: $node_ver"
    fi

    # Check npm
    if ! command -v npm >/dev/null 2>&1; then
        log "  ✗ npm not found"
        missing=1
    else
        local npm_ver
        npm_ver=$(npm --version 2>/dev/null || echo "unknown")
        log "  ✓ npm found: $npm_ver"
    fi

    # Check Composer
    if ! command -v composer >/dev/null 2>&1; then
        log "  ✗ Composer not found"
        missing=1
    else
        local composer_ver
        composer_ver=$(composer --version 2>/dev/null | head -n1 || echo "unknown")
        log "  ✓ Composer found: $composer_ver"
    fi

    # Check Apache/Nginx (we'll check for apache2)
    if ! command -v apache2 >/dev/null 2>&1 && ! command -v nginx >/dev/null 2>&1; then
        log "  ✗ Web server (Apache or Nginx) not found"
        missing=1
    else
        if command -v apache2 >/dev/null 2>&1; then
            log "  ✓ Apache found"
        else
            log "  ✓ Nginx found"
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        log "Some prerequisites are missing"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

#######################################
# Install prerequisites
#######################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install PHP 8.1 and required extensions
    log "Installing PHP ${PHP_VERSION} and extensions..."
    apt-get install -y \
        software-properties-common \
        ca-certificates \
        lsb-release \
        apt-transport-https

    # Add ondrej/php PPA for PHP 8.1+
    add-apt-repository -y ppa:ondrej/php
    apt-get update

    apt-get install -y \
        "php${PHP_VERSION}" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-pgsql" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-imagick" \
        "php${PHP_VERSION}-gmp" \
        "php${PHP_VERSION}-opcache" \
        libapache2-mod-php${PHP_VERSION}

    # Install PostgreSQL
    log "Installing PostgreSQL..."
    apt-get install -y \
        postgresql \
        postgresql-contrib

    # Install Node.js 18.x
    log "Installing Node.js ${NODE_VERSION}..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    apt-get install -y nodejs

    # Install Composer
    log "Installing Composer..."
    local composer_installer="/tmp/composer-setup.php"
    local composer_sig
    composer_sig=$(curl -fsSL https://composer.github.io/installer.sig)

    php -r "copy('https://getcomposer.org/installer', '${composer_installer}');"
    php -r "if (hash_file('sha384', '${composer_installer}') === '${composer_sig}') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('${composer_installer}'); } echo PHP_EOL;"
    php "${composer_installer}" --install-dir=/usr/local/bin --filename=composer
    rm -f "${composer_installer}"

    # Install Apache2
    log "Installing Apache2..."
    apt-get install -y apache2

    # Enable required Apache modules
    a2enmod rewrite headers env dir mime ssl

    # Install additional tools
    log "Installing additional tools..."
    apt-get install -y \
        unzip \
        wget \
        curl \
        git \
        imagemagick \
        ghostscript \
        pdftk

    log "Prerequisites installation completed"
}

#######################################
# Verify prerequisites are working
#######################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify PHP
    if ! php --version >/dev/null 2>&1; then
        error "PHP verification failed"
    fi
    local php_ver
    php_ver=$(php -r 'echo PHP_VERSION;')
    log "  ✓ PHP ${php_ver} is working"

    # Verify PostgreSQL
    if ! psql --version >/dev/null 2>&1; then
        error "PostgreSQL client verification failed"
    fi
    log "  ✓ PostgreSQL client is working"

    # Verify Node.js
    if ! node --version >/dev/null 2>&1; then
        error "Node.js verification failed"
    fi
    log "  ✓ Node.js $(node --version) is working"

    # Verify npm
    if ! npm --version >/dev/null 2>&1; then
        error "npm verification failed"
    fi
    log "  ✓ npm v$(npm --version) is working"

    # Verify Composer
    if ! composer --version >/dev/null 2>&1; then
        error "Composer verification failed"
    fi
    log "  ✓ Composer is working"

    log "All prerequisites verified successfully"
}

#######################################
# Check if LibreSign is already installed
# Returns: 0 if installed, 1 if not
#######################################
check_existing_installation() {
    log "Checking for existing LibreSign installation..."

    # Check if wrapper script exists and works
    if command -v libresign >/dev/null 2>&1; then
        if libresign --version 2>/dev/null | grep -q "${LIBRESIGN_VERSION}"; then
            log "LibreSign ${LIBRESIGN_VERSION} is already installed"
            return 0
        fi
    fi

    # Check if Nextcloud app directory exists
    if [[ -d "${NEXTCLOUD_APPS_DIR}/libresign" ]]; then
        log "LibreSign app directory found, but version may differ"
    fi

    log "LibreSign ${LIBRESIGN_VERSION} is not installed"
    return 1
}

#######################################
# Install Nextcloud
#######################################
install_nextcloud() {
    log "Installing Nextcloud ${NEXTCLOUD_VERSION}..."

    # Check if Nextcloud is already installed
    if [[ -d "${NEXTCLOUD_INSTALL_DIR}" ]] && [[ -f "${NEXTCLOUD_INSTALL_DIR}/occ" ]]; then
        log "Nextcloud is already installed at ${NEXTCLOUD_INSTALL_DIR}"
        return 0
    fi

    # Create directories
    mkdir -p "${NEXTCLOUD_INSTALL_DIR}"
    mkdir -p "${NEXTCLOUD_DATA_DIR}"

    # Download Nextcloud
    local nextcloud_tarball="/tmp/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
    log "Downloading Nextcloud ${NEXTCLOUD_VERSION}..."
    wget -q --show-progress -O "${nextcloud_tarball}" \
        "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"

    # Verify checksum
    local checksum_url="https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2.sha256"
    local expected_checksum
    expected_checksum=$(curl -fsSL "${checksum_url}" | awk '{print $1}')
    local actual_checksum
    actual_checksum=$(sha256sum "${nextcloud_tarball}" | awk '{print $1}')

    if [[ "${expected_checksum}" != "${actual_checksum}" ]]; then
        error "Nextcloud checksum verification failed. Expected: ${expected_checksum}, Got: ${actual_checksum}"
    fi
    log "Checksum verified successfully"

    # Extract Nextcloud
    log "Extracting Nextcloud..."
    tar -xjf "${nextcloud_tarball}" -C /tmp
    mv /tmp/nextcloud/* "${NEXTCLOUD_INSTALL_DIR}/"
    rm -f "${nextcloud_tarball}"

    # Set permissions
    chown -R www-data:www-data "${NEXTCLOUD_INSTALL_DIR}"
    chown -R www-data:www-data "${NEXTCLOUD_DATA_DIR}"

    log "Nextcloud installed successfully"
}

#######################################
# Configure Nextcloud database
#######################################
configure_nextcloud_database() {
    log "Configuring Nextcloud database..."

    # Start PostgreSQL if not running
    if ! systemctl is-active --quiet postgresql; then
        log "Starting PostgreSQL service..."
        systemctl start postgresql
        systemctl enable postgresql
    fi

    # Create database and user
    local db_name="nextcloud"
    local db_user="nextcloud"
    local db_pass
    db_pass="nextcloud_secure_password_$(date +%s)"

    log "Creating PostgreSQL database and user..."
    sudo -u postgres psql -c "CREATE DATABASE ${db_name};" 2>/dev/null || log "Database may already exist"
    sudo -u postgres psql -c "CREATE USER ${db_user} WITH PASSWORD '${db_pass}';" 2>/dev/null || log "User may already exist"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};" 2>/dev/null || true

    # Store credentials for Nextcloud setup
    echo "${db_pass}" > /tmp/nextcloud_db_pass
    chmod 600 /tmp/nextcloud_db_pass

    log "Database configured successfully"
}

#######################################
# Initialize Nextcloud
#######################################
initialize_nextcloud() {
    log "Initializing Nextcloud..."

    # Check if already initialized
    if sudo -u www-data php "${NEXTCLOUD_INSTALL_DIR}/occ" status 2>/dev/null | grep -q "installed: true"; then
        log "Nextcloud is already initialized"
        return 0
    fi

    # Read database password
    local db_pass
    if [[ -f /tmp/nextcloud_db_pass ]]; then
        db_pass=$(cat /tmp/nextcloud_db_pass)
    else
        db_pass="nextcloud_secure_password"
    fi

    # Run Nextcloud installation
    log "Running Nextcloud installation..."
    sudo -u www-data php "${NEXTCLOUD_INSTALL_DIR}/occ" maintenance:install \
        --database="pgsql" \
        --database-name="nextcloud" \
        --database-host="127.0.0.1" \
        --database-user="nextcloud" \
        --database-pass="${db_pass}" \
        --admin-user="admin" \
        --admin-pass="admin" \
        --data-dir="${NEXTCLOUD_DATA_DIR}"

    # Clean up password file
    rm -f /tmp/nextcloud_db_pass

    log "Nextcloud initialized successfully"
}

#######################################
# Install LibreSign app
#######################################
install_libresign_app() {
    log "Installing LibreSign ${LIBRESIGN_VERSION} app..."

    # Download LibreSign tarball
    local libresign_tarball="/tmp/libresign.tar.gz"
    log "Downloading LibreSign from ${LIBRESIGN_TARBALL_URL}..."

    # Try to download from GitHub release
    if ! wget -q --show-progress -O "${libresign_tarball}" "${LIBRESIGN_TARBALL_URL}" 2>/dev/null; then
        log "GitHub release download failed, attempting alternative method..."

        # Clone and build from source as fallback
        local libresign_src="/tmp/libresign_src"
        git clone --depth 1 --branch "${LIBRESIGN_VERSION}" \
            https://github.com/LibreSign/libresign.git "${libresign_src}"

        cd "${libresign_src}"

        # Install dependencies
        log "Installing Composer dependencies..."
        composer install --no-dev --prefer-dist

        log "Installing npm dependencies..."
        npm ci

        log "Building frontend assets..."
        npm run build

        # Copy to Nextcloud apps directory
        log "Installing LibreSign app..."
        mkdir -p "${NEXTCLOUD_APPS_DIR}/libresign"
        cp -r appinfo composer img js l10n lib templates vendor \
            CHANGELOG.md openapi*.json \
            "${NEXTCLOUD_APPS_DIR}/libresign/"

        # Clean up
        cd /
        rm -rf "${libresign_src}"
    else
        # Extract tarball
        log "Extracting LibreSign..."
        mkdir -p "${NEXTCLOUD_APPS_DIR}"
        tar -xzf "${libresign_tarball}" -C "${NEXTCLOUD_APPS_DIR}"
        rm -f "${libresign_tarball}"
    fi

    # Set permissions
    chown -R www-data:www-data "${NEXTCLOUD_APPS_DIR}/libresign"

    # Enable the app
    log "Enabling LibreSign app..."
    sudo -u www-data php "${NEXTCLOUD_INSTALL_DIR}/occ" app:enable libresign

    log "LibreSign app installed successfully"
}

#######################################
# Configure LibreSign
#######################################
configure_libresign() {
    log "Configuring LibreSign..."

    # Install Java for LibreSign (required for PDF signing)
    log "Installing Java for LibreSign..."
    apt-get install -y openjdk-17-jre-headless

    # Install LibreSign binaries
    log "Installing LibreSign binaries..."
    sudo -u www-data php "${NEXTCLOUD_INSTALL_DIR}/occ" libresign:install --java || log "Warning: Java installation may have issues"

    log "LibreSign configured successfully"
}

#######################################
# Create libresign wrapper script
#######################################
create_wrapper_script() {
    log "Creating libresign wrapper script..."

    local wrapper_path="/usr/local/bin/libresign"

    cat > "${wrapper_path}" <<'EOF'
#!/bin/bash
# LibreSign CLI wrapper for Nextcloud app

NEXTCLOUD_DIR="/opt/nextcloud"

if [[ "$1" == "--version" ]]; then
    # Get LibreSign version from Nextcloud
    version=$(sudo -u www-data php "${NEXTCLOUD_DIR}/occ" app:list --shipped=false --output=json 2>/dev/null | \
        grep -oP '"libresign":\{"version":"[^"]+' | grep -oP 'version":"[^"]+' | cut -d'"' -f3)

    if [[ -n "${version}" ]]; then
        echo "LibreSign version ${version}"
        exit 0
    else
        echo "Error: Unable to determine LibreSign version" >&2
        exit 1
    fi
elif [[ "$1" == "--help" ]] || [[ -z "$1" ]]; then
    echo "LibreSign CLI Wrapper"
    echo ""
    echo "Usage: libresign [command]"
    echo ""
    echo "Commands:"
    echo "  --version    Display LibreSign version"
    echo "  --help       Display this help message"
    echo "  occ          Run Nextcloud OCC commands"
    echo ""
    echo "For full LibreSign functionality, use Nextcloud OCC commands:"
    echo "  sudo -u www-data php ${NEXTCLOUD_DIR}/occ libresign:install --help"
    exit 0
elif [[ "$1" == "occ" ]]; then
    shift
    sudo -u www-data php "${NEXTCLOUD_DIR}/occ" "$@"
else
    echo "Unknown command: $1" >&2
    echo "Run 'libresign --help' for usage information" >&2
    exit 1
fi
EOF

    chmod +x "${wrapper_path}"

    log "Wrapper script created at ${wrapper_path}"
}

#######################################
# Validate installation
#######################################
validate() {
    log "Validating LibreSign installation..."

    # Check if wrapper exists
    if ! command -v libresign >/dev/null 2>&1; then
        error "libresign command not found in PATH"
    fi

    # Check version
    local version_output
    version_output=$(libresign --version 2>&1)

    if ! echo "${version_output}" | grep -q "${LIBRESIGN_VERSION}"; then
        error "Version mismatch. Expected ${LIBRESIGN_VERSION}, got: ${version_output}"
    fi

    log "✓ LibreSign ${LIBRESIGN_VERSION} validated successfully"
    log "${version_output}"
}

#######################################
# Main installation flow
#######################################
main() {
    log "Starting LibreSign ${LIBRESIGN_VERSION} installation..."

    # Step 1: Prerequisites
    if [[ "${SKIP_PREREQS}" == "false" ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        fi
    else
        log "Skipping prerequisite installation (RESPECT_SHARED_DEPS=1 or --skip-prereqs)"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation already complete"
        exit 0
    fi

    # Step 3: Install Nextcloud
    install_nextcloud

    # Step 4: Configure database
    configure_nextcloud_database

    # Step 5: Initialize Nextcloud
    initialize_nextcloud

    # Step 6: Install LibreSign app
    install_libresign_app

    # Step 7: Configure LibreSign
    configure_libresign

    # Step 8: Create wrapper script
    create_wrapper_script

    # Step 9: Validate
    validate

    log "Installation completed successfully"
    log ""
    log "LibreSign ${LIBRESIGN_VERSION} has been installed successfully!"
    log ""
    log "Usage:"
    log "  libresign --version                Show version"
    log "  libresign --help                   Show help"
    log "  libresign occ libresign:install    Install LibreSign components"
    log ""
    log "Nextcloud admin credentials:"
    log "  Username: admin"
    log "  Password: admin"
    log "  (Change these immediately in production!)"
}

main "$@"
