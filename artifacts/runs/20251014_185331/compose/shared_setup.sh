#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'

log() {
    echo "[shared][$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This script must run as root."
        exit 1
    fi
}

install_shared_dependencies() {

    if [ ! -d /var/lib/apt/lists ] || [ -z "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]; then
        log "Refreshing apt lists..."
        apt-get update -y
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends apache2 ca-certificates curl default-mysql-client git gnupg libapache2-mod-php8.2 libcurl4 libonig5 libsodium23 libssl3 libxml2-dev libxslt1.1 libzip4 lsb-release php8.2 php8.2-cli php8.2-common php8.2-curl php8.2-gd php8.2-intl php8.2-ldap php8.2-mbstring php8.2-mysql php8.2-soap php8.2-xml php8.2-xsl php8.2-zip software-properties-common unzip wget
    # Refresh dynamic linker cache to pick up newly installed libs
    ldconfig

    export PATH="/usr/local/bin:$PATH"

    # Install Node.js 22 from NodeSource if not present or wrong version
    if ! command -v node >/dev/null 2>&1 || ! node --version 2>/dev/null | grep -q "^v22\."; then
        log "Installing Node.js 22..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
        apt-get install -y --no-install-recommends nodejs >/dev/null 2>&1
        log "Node.js installed: $(node --version 2>/dev/null || echo 'unknown')"
    else
        log "Node.js 22 already installed"
    fi

    # Install Composer if not present
    if ! command -v composer >/dev/null 2>&1; then
        log "Installing Composer..."
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "$tmp_dir"' EXIT
        cd "$tmp_dir"

        # Download and verify Composer installer
        EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"
        wget -q https://getcomposer.org/installer -O composer-setup.php
        ACTUAL_CHECKSUM="$(sha384sum composer-setup.php | awk '{print $1}')"

        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            log "WARNING: Composer installer checksum mismatch, installing anyway..."
        fi

        php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer --version=2.8.3 || true
        rm -f composer-setup.php
        cd -

        if command -v composer >/dev/null 2>&1; then
            log "Composer installed successfully"
        else
            log "WARNING: Composer installation may have failed"
        fi
    else
        log "Composer already installed"
    fi

    log "Shared dependencies installed."
}

main() {
    log "Starting shared setup..."
    ensure_root
    install_shared_dependencies
    log "Shared setup completed successfully."
}

main "$@"
