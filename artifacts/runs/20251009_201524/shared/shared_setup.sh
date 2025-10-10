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
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 apt-transport-https build-essential ca-certificates coreutils curl fontconfig ghostscript git gnupg gnupg2 imagemagick libapache2-mod-php8.1 libcairo2 libcups2 libcups2-dev libdbus-glib-1-2 libffi-dev libfontconfig libfreetype6-dev libfribidi-dev libglu1-mesa libharfbuzz-dev libjpeg8-dev liblcms2-dev libldap2-dev libmysqlclient-dev libopenjp2-7-dev libsasl2-dev libsm6 libssl-dev libtiff5-dev libwebp-dev libx11-6 libxcb1-dev libxext6 libxinerama1 libxrender1 lsb-release nginx openjdk-11-jre-headless pdftk php8.1-bcmath php8.1-cli php8.1-common php8.1-curl php8.1-fpm php8.1-gd php8.1-gmp php8.1-imagick php8.1-intl php8.1-mbstring php8.1-mysql php8.1-opcache php8.1-pgsql php8.1-xml php8.1-zip python3 python3-dev python3-pip python3-venv snapd software-properties-common supervisor tar tcl8.6-dev tk8.6-dev unzip wget xvfb zlib1g-dev

    export PATH="/home/frappe/.local/bin:$PATH"
    export PATH="/snap/bin:$PATH"
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
