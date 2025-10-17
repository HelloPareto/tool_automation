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
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl flatpak gnupg lsb-release
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
