#!/usr/bin/env bash

#==============================================================================
# ERPNext v15.82.2 Installation Script
#
# Description: Installs ERPNext (Open Source ERP) via Frappe Bench
# Version: v15.82.2
# Standards: Solutions Team Install Standards v1.0
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
readonly ERPNEXT_VERSION="v15.82.2"
readonly FRAPPE_VERSION="version-15"
readonly TOOL_NAME="erpnext"

# Versions for prerequisites
readonly PYTHON_MIN_VERSION="3.10"
readonly NODE_VERSION="18"
readonly REDIS_MIN_VERSION="6"
readonly MARIADB_VERSION="10.11"
readonly WKHTMLTOPDF_VERSION="0.12.6.1-3"

# Frappe bench user and paths
readonly FRAPPE_USER="frappe"
readonly FRAPPE_HOME="/home/${FRAPPE_USER}"
readonly BENCH_PATH="${FRAPPE_HOME}/frappe-bench"

# Installation flags
SKIP_PREREQS=false
if [[ "${RESPECT_SHARED_DEPS:-0}" == "1" ]] || [[ "${1:-}" == "--skip-prereqs" ]]; then
    SKIP_PREREQS=true
fi

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*" >&2
}

#------------------------------------------------------------------------------
# Prerequisite Detection
#------------------------------------------------------------------------------
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Python 3.10+
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
        if awk "BEGIN {exit !($python_version >= $PYTHON_MIN_VERSION)}"; then
            log "✓ Python $python_version found"
        else
            log_warning "✗ Python $python_version found, but ${PYTHON_MIN_VERSION}+ required"
            all_present=false
        fi
    else
        log_warning "✗ Python 3 not found"
        all_present=false
    fi

    # Check pip3
    if command -v pip3 &> /dev/null; then
        log "✓ pip3 found"
    else
        log_warning "✗ pip3 not found"
        all_present=false
    fi

    # Check Node.js 18+
    if command -v node &> /dev/null; then
        local node_version
        node_version=$(node --version 2>&1 | sed 's/v//' | cut -d. -f1)
        if [[ $node_version -ge $NODE_VERSION ]]; then
            log "✓ Node.js v$node_version found"
        else
            log_warning "✗ Node.js v$node_version found, but v${NODE_VERSION}+ required"
            all_present=false
        fi
    else
        log_warning "✗ Node.js not found"
        all_present=false
    fi

    # Check npm
    if command -v npm &> /dev/null; then
        log "✓ npm found"
    else
        log_warning "✗ npm not found"
        all_present=false
    fi

    # Check yarn
    if command -v yarn &> /dev/null; then
        log "✓ yarn found"
    else
        log_warning "✗ yarn not found"
        all_present=false
    fi

    # Check Redis
    if command -v redis-server &> /dev/null; then
        log "✓ redis-server found"
    else
        log_warning "✗ redis-server not found"
        all_present=false
    fi

    # Check MariaDB
    if command -v mariadb &> /dev/null || command -v mysql &> /dev/null; then
        log "✓ MariaDB/MySQL client found"
    else
        log_warning "✗ MariaDB/MySQL client not found"
        all_present=false
    fi

    # Check wkhtmltopdf
    if command -v wkhtmltopdf &> /dev/null; then
        log "✓ wkhtmltopdf found"
    else
        log_warning "✗ wkhtmltopdf not found"
        all_present=false
    fi

    # Check git
    if command -v git &> /dev/null; then
        log "✓ git found"
    else
        log_warning "✗ git not found"
        all_present=false
    fi

    # Check build tools
    if command -v gcc &> /dev/null && command -v make &> /dev/null; then
        log "✓ build-essential found"
    else
        log_warning "✗ build-essential not found"
        all_present=false
    fi

    if [[ "$all_present" == true ]]; then
        log "All prerequisites are present"
        return 0
    else
        log_warning "Some prerequisites are missing"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Install Prerequisites
#------------------------------------------------------------------------------
install_prerequisites() {
    log "Installing prerequisites..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    log "Updating package lists..."
    apt-get update

    # Install base dependencies
    log "Installing base dependencies..."
    apt-get install -y \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        curl \
        wget \
        git

    # Install Python 3.11 and development packages
    log "Installing Python 3.11 and development packages..."
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y \
        python3.11 \
        python3.11-dev \
        python3.11-venv \
        python3-pip \
        python3-setuptools \
        python3-distutils

    # Make Python 3.11 the default
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
    update-alternatives --set python3 /usr/bin/python3.11

    # Install Node.js 18.x from NodeSource
    log "Installing Node.js ${NODE_VERSION}.x..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    apt-get install -y nodejs

    # Install Yarn
    log "Installing Yarn..."
    npm install -g yarn

    # Install Redis
    log "Installing Redis ${REDIS_MIN_VERSION}+..."
    apt-get install -y redis-server

    # Install MariaDB
    log "Installing MariaDB ${MARIADB_VERSION}..."
    curl -fsSL https://supplychain.mariadb.com/mariadb-keyring-2019.gpg -o /usr/share/keyrings/mariadb-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://deb.mariadb.org/${MARIADB_VERSION}/ubuntu $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/mariadb.list
    apt-get update
    apt-get install -y mariadb-server mariadb-client

    # Install wkhtmltopdf
    log "Installing wkhtmltopdf ${WKHTMLTOPDF_VERSION}..."
    wget -q https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/wkhtmltox_${WKHTMLTOPDF_VERSION}.jammy_amd64.deb \
        -O /tmp/wkhtmltox.deb
    apt-get install -y /tmp/wkhtmltox.deb
    rm -f /tmp/wkhtmltox.deb

    # Install build tools and development libraries
    log "Installing build tools and libraries..."
    apt-get install -y \
        build-essential \
        libssl-dev \
        libffi-dev \
        libmysqlclient-dev \
        libcups2-dev \
        libldap2-dev \
        libsasl2-dev \
        libtiff5-dev \
        libjpeg8-dev \
        libopenjp2-7-dev \
        zlib1g-dev \
        libfreetype6-dev \
        liblcms2-dev \
        libwebp-dev \
        tcl8.6-dev \
        tk8.6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libxcb1-dev \
        xvfb \
        libfontconfig

    # Install additional tools
    apt-get install -y \
        supervisor \
        nginx \
        fontconfig \
        cron

    log "Prerequisites installation completed"
}

#------------------------------------------------------------------------------
# Verify Prerequisites
#------------------------------------------------------------------------------
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! python3 --version; then
        log_error "Python verification failed"
        exit 1
    fi

    if ! pip3 --version; then
        log_error "pip3 verification failed"
        exit 1
    fi

    # Verify Node.js and npm
    if ! node --version; then
        log_error "Node.js verification failed"
        exit 1
    fi

    if ! npm --version; then
        log_error "npm verification failed"
        exit 1
    fi

    # Verify Yarn
    if ! yarn --version; then
        log_error "Yarn verification failed"
        exit 1
    fi

    # Verify Redis
    if ! redis-server --version; then
        log_error "Redis verification failed"
        exit 1
    fi

    # Verify MariaDB
    if ! mariadb --version; then
        log_error "MariaDB verification failed"
        exit 1
    fi

    # Verify wkhtmltopdf
    if ! wkhtmltopdf --version; then
        log_error "wkhtmltopdf verification failed"
        exit 1
    fi

    # Verify git
    if ! git --version; then
        log_error "git verification failed"
        exit 1
    fi

    # Verify build tools
    if ! gcc --version; then
        log_error "gcc verification failed"
        exit 1
    fi

    if ! make --version; then
        log_error "make verification failed"
        exit 1
    fi

    log "All prerequisites verified successfully"
}

#------------------------------------------------------------------------------
# Check Existing Installation
#------------------------------------------------------------------------------
check_existing_installation() {
    log "Checking for existing ERPNext installation..."

    # Check if frappe-bench is installed
    if command -v bench &> /dev/null; then
        local bench_version
        bench_version=$(bench version 2>/dev/null || echo "unknown")
        log "frappe-bench found (version: $bench_version)"

        # Check if ERPNext is installed in the bench
        if [[ -d "${BENCH_PATH}/apps/erpnext" ]]; then
            # Check ERPNext version
            cd "${BENCH_PATH}/apps/erpnext" || return 1
            local erpnext_current_version
            erpnext_current_version=$(git describe --tags 2>/dev/null || echo "unknown")

            if [[ "$erpnext_current_version" == "$ERPNEXT_VERSION" ]]; then
                log "ERPNext ${ERPNEXT_VERSION} is already installed"
                return 0
            else
                log "ERPNext is installed but version is $erpnext_current_version (expected: $ERPNEXT_VERSION)"
                return 1
            fi
        fi
    fi

    log "ERPNext is not installed"
    return 1
}

#------------------------------------------------------------------------------
# Install ERPNext
#------------------------------------------------------------------------------
install_tool() {
    log "Installing ERPNext ${ERPNEXT_VERSION}..."

    # Create frappe user if it doesn't exist
    if ! id -u "${FRAPPE_USER}" &> /dev/null; then
        log "Creating frappe user..."
        useradd -m -s /bin/bash "${FRAPPE_USER}"
        echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    fi

    # Install frappe-bench globally
    log "Installing frappe-bench..."
    pip3 install frappe-bench

    # Ensure services are running
    log "Starting required services..."
    service redis-server start || true
    service mariadb start || true

    # Configure MariaDB for Frappe
    log "Configuring MariaDB..."
    cat > /etc/mysql/mariadb.conf.d/99-frappe.cnf <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

    service mariadb restart || true

    # Secure MariaDB installation (automated)
    log "Securing MariaDB installation..."
    mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'frappe_root_pass123';" || true
    mariadb -e "DELETE FROM mysql.user WHERE User='';" || true
    mariadb -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" || true
    mariadb -e "DROP DATABASE IF EXISTS test;" || true
    mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" || true
    mariadb -e "FLUSH PRIVILEGES;" || true

    # Switch to frappe user for bench operations
    log "Initializing Frappe bench..."
    su - "${FRAPPE_USER}" <<'FRAPPE_SETUP'
set -euo pipefail

# Initialize bench with Frappe Framework version 15
cd ~
bench init --frappe-branch version-15 frappe-bench --verbose

# Navigate to bench directory
cd ~/frappe-bench

# Get ERPNext app with specific version
bench get-app --branch v15.82.2 erpnext --resolve-deps

# Create a new site
bench new-site erpnext.local \
    --admin-password admin \
    --mariadb-root-password frappe_root_pass123 \
    --no-mariadb-socket

# Install ERPNext on the site
bench --site erpnext.local install-app erpnext

# Set ERPNext site as default
bench use erpnext.local

echo "ERPNext installation completed for frappe user"
FRAPPE_SETUP

    # Create symbolic link for bench command
    if [[ ! -L /usr/local/bin/bench ]]; then
        ln -s "${FRAPPE_HOME}/.local/bin/bench" /usr/local/bin/bench || true
    fi

    log "ERPNext ${ERPNEXT_VERSION} installed successfully"
}

#------------------------------------------------------------------------------
# Validate Installation
#------------------------------------------------------------------------------
validate() {
    log "Validating ERPNext installation..."

    # Check if bench command is available
    if ! command -v bench &> /dev/null; then
        log_error "bench command not found"
        log_error "Remediation: Ensure frappe-bench is installed correctly"
        exit 1
    fi

    # Check bench version
    log "Checking bench version..."
    bench version

    # Check if ERPNext directory exists
    if [[ ! -d "${BENCH_PATH}/apps/erpnext" ]]; then
        log_error "ERPNext directory not found at ${BENCH_PATH}/apps/erpnext"
        log_error "Remediation: Run installation again"
        exit 1
    fi

    # Verify ERPNext version
    log "Verifying ERPNext version..."
    cd "${BENCH_PATH}/apps/erpnext" || exit 1
    local installed_version
    installed_version=$(git describe --tags 2>/dev/null || echo "unknown")

    if [[ "$installed_version" != "$ERPNEXT_VERSION" ]]; then
        log_error "ERPNext version mismatch: installed=$installed_version, expected=$ERPNEXT_VERSION"
        exit 1
    fi

    log "✓ ERPNext ${ERPNEXT_VERSION} validated successfully"
    log "✓ Bench version: $(bench version)"
    log "✓ Site: erpnext.local"
    log "✓ Installation path: ${BENCH_PATH}"

    # Note about starting the application
    log ""
    log "NOTE: To start ERPNext, run:"
    log "  su - frappe"
    log "  cd ~/frappe-bench"
    log "  bench start"
    log ""
    log "Access ERPNext at: http://localhost:8000"
    log "Default credentials: Administrator / admin"

    return 0
}

#------------------------------------------------------------------------------
# Main Installation Flow
#------------------------------------------------------------------------------
main() {
    log "Starting ERPNext ${ERPNEXT_VERSION} installation..."
    log "Skip prerequisites: ${SKIP_PREREQS}"

    # Step 1: Handle Prerequisites
    if [[ "$SKIP_PREREQS" == false ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        else
            log "Prerequisites already satisfied, skipping installation"
        fi
    else
        log "Skipping prerequisite installation (--skip-prereqs or RESPECT_SHARED_DEPS=1)"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "ERPNext ${ERPNEXT_VERSION} is already installed"
        validate
        log "Installation completed successfully (idempotent)"
        exit 0
    fi

    # Step 3: Install ERPNext
    install_tool

    # Step 4: Validate
    validate

    log "ERPNext ${ERPNEXT_VERSION} installation completed successfully"
}

#------------------------------------------------------------------------------
# Script Entry Point
#------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
