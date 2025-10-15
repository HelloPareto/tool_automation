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
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 ca-certificates curl default-mysql-client flatpak git gnupg libapache2-mod-php8.2 libcurl4 libonig5 libsodium23 libssl3 libxml2-dev libxslt1.1 libzip4 lsb-release nodejs npm php8.2 php8.2-cli php8.2-common php8.2-curl php8.2-gd php8.2-intl php8.2-ldap php8.2-mbstring php8.2-mysql php8.2-soap php8.2-xml php8.2-xsl php8.2-zip software-properties-common unzip wget
    # Refresh dynamic linker cache to pick up newly installed libs
    ldconfig

    export PATH="/usr/local/bin:$PATH"


    log "Shared dependencies installed."
}

main() {
    log "Starting shared setup..."
    ensure_root
    install_shared_dependencies
    log "Shared setup completed successfully."
}

main "$@"
