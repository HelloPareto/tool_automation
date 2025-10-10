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
    DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential ca-certificates coreutils curl fontconfig gfortran libboost-date-time1.74.0 libboost-filesystem1.74.0 libboost-locale1.74.0 libcairo2 libcom-err2 libcups2 libcurl4 libdbus-1-3 libfreetype6 libgl1 libglib2.0-0 libglu1-mesa libgssapi-krb5-2 libhunspell-1.7-0 libhyphen0 libice6 libicu70 libk5crypto3 libkrb5-3 liblapack-dev libnspr4 libnss3 libopenblas-dev libsm6 libx11-6 libxext6 libxinerama1 libxml2-dev libxrender1 libxslt1.1 openjdk-11-jre-headless python3 python3-dev python3-pip python3-venv tar
    # Refresh dynamic linker cache to pick up newly installed libs
    ldconfig

    export PATH="/usr/bin:$PATH"
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
