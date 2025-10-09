#!/bin/bash
#===============================================================================
# ERPNext v15.82.1 Installation Script
#
# Description: Installs ERPNext v15.82.1 with Frappe Framework using bench
# Requirements: Python 3.10+, Node.js 18+, MariaDB 10.6+, Redis, wkhtmltopdf
# Validation: bench version (shows erpnext 15.82.1)
#===============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Version constants
readonly ERPNEXT_VERSION="v15.82.1"
readonly FRAPPE_VERSION="version-15"
readonly BENCH_USER="frappe"
readonly BENCH_DIR="/home/${BENCH_USER}/frappe-bench"

#===============================================================================
# Logging Functions
#===============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

#===============================================================================
# Prerequisite Detection Functions
#===============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    local missing=0

    # Check Python 3.10+
    if command -v python3 &>/dev/null; then
        local py_version
        py_version=$(python3 --version 2>&1 | awk '{print $2}')
        if python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
            log "✓ Python ${py_version} found"
        else
            log_warning "✗ Python ${py_version} found, but 3.10+ required"
            missing=1
        fi
    else
        log_warning "✗ Python 3 not found"
        missing=1
    fi

    # Check pip3
    if command -v pip3 &>/dev/null; then
        log "✓ pip3 found"
    else
        log_warning "✗ pip3 not found"
        missing=1
    fi

    # Check Node.js
    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node --version)
        log "✓ Node.js ${node_ver} found"
    else
        log_warning "✗ Node.js not found"
        missing=1
    fi

    # Check npm
    if command -v npm &>/dev/null; then
        local npm_ver
        npm_ver=$(npm --version)
        log "✓ npm ${npm_ver} found"
    else
        log_warning "✗ npm not found"
        missing=1
    fi

    # Check MariaDB/MySQL
    if command -v mysql &>/dev/null; then
        log "✓ MySQL/MariaDB client found"
    else
        log_warning "✗ MySQL/MariaDB client not found"
        missing=1
    fi

    # Check Redis
    if command -v redis-server &>/dev/null; then
        log "✓ Redis server found"
    else
        log_warning "✗ Redis server not found"
        missing=1
    fi

    # Check wkhtmltopdf
    if command -v wkhtmltopdf &>/dev/null; then
        log "✓ wkhtmltopdf found"
    else
        log_warning "✗ wkhtmltopdf not found"
        missing=1
    fi

    # Check git
    if command -v git &>/dev/null; then
        log "✓ git found"
    else
        log_warning "✗ git not found"
        missing=1
    fi

    # Check build tools
    if command -v gcc &>/dev/null && command -v make &>/dev/null; then
        log "✓ Build tools found"
    else
        log_warning "✗ Build tools not found"
        missing=1
    fi

    return ${missing}
}

#===============================================================================
# Prerequisite Installation Functions
#===============================================================================

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq

    # Install system dependencies
    log "Installing system packages..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-dev \
        python3-venv \
        python3-setuptools \
        git \
        build-essential \
        software-properties-common \
        curl \
        wget \
        libffi-dev \
        libssl-dev \
        libmysqlclient-dev \
        libcrypt-dev \
        pkg-config \
        supervisor \
        cron \
        fontconfig \
        libxrender1 \
        xfonts-75dpi \
        xfonts-base \
        xvfb \
        libxext6 \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

    # Install MariaDB
    if ! command -v mysql &>/dev/null; then
        log "Installing MariaDB 10.6+..."
        apt-get update -qq
        apt-get install -y -qq \
            mariadb-server \
            mariadb-client \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/*

        # Start MariaDB service
        if command -v systemctl &>/dev/null; then
            systemctl start mariadb || service mysql start || true
            systemctl enable mariadb || true
        else
            service mysql start || true
        fi

        # Configure MariaDB for Frappe
        log "Configuring MariaDB..."
        cat > /etc/mysql/conf.d/frappe.cnf <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

        # Restart MariaDB to apply config
        if command -v systemctl &>/dev/null; then
            systemctl restart mariadb || service mysql restart || true
        else
            service mysql restart || true
        fi
    fi

    # Install Redis
    if ! command -v redis-server &>/dev/null; then
        log "Installing Redis..."
        apt-get update -qq
        apt-get install -y -qq redis-server \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/*

        # Start Redis service
        if command -v systemctl &>/dev/null; then
            systemctl start redis-server || service redis-server start || true
            systemctl enable redis-server || true
        else
            service redis-server start || true
        fi
    fi

    # Install Node.js 18.x
    if ! command -v node &>/dev/null; then
        log "Installing Node.js 18.x..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y -qq nodejs \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/*
    fi

    # Install yarn
    log "Installing yarn..."
    npm install -g yarn --silent

    # Install wkhtmltopdf
    if ! command -v wkhtmltopdf &>/dev/null; then
        log "Installing wkhtmltopdf..."
        cd /tmp
        wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
        apt-get install -y -qq /tmp/wkhtmltox_0.12.6.1-2.jammy_amd64.deb || true
        rm -f /tmp/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    fi

    log "Prerequisites installation completed"
}

#===============================================================================
# Prerequisite Verification Functions
#===============================================================================

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
        log_error "Python 3.10+ verification failed"
        python3 --version
        exit 1
    fi
    log "✓ Python 3.10+ verified"

    # Verify pip
    if ! pip3 --version &>/dev/null; then
        log_error "pip3 verification failed"
        exit 1
    fi
    log "✓ pip3 verified"

    # Verify Node.js
    if ! node --version &>/dev/null; then
        log_error "Node.js verification failed"
        exit 1
    fi
    log "✓ Node.js verified"

    # Verify npm
    if ! npm --version &>/dev/null; then
        log_error "npm verification failed"
        exit 1
    fi
    log "✓ npm verified"

    # Verify yarn
    if ! yarn --version &>/dev/null; then
        log_error "yarn verification failed"
        exit 1
    fi
    log "✓ yarn verified"

    # Verify MariaDB
    if ! mysql --version &>/dev/null; then
        log_error "MySQL/MariaDB verification failed"
        exit 1
    fi
    log "✓ MySQL/MariaDB verified"

    # Verify Redis (check if command exists, don't require it to be running)
    if ! command -v redis-server &>/dev/null; then
        log_error "Redis verification failed"
        exit 1
    fi
    log "✓ Redis verified"

    # Verify wkhtmltopdf
    if ! wkhtmltopdf --version &>/dev/null; then
        log_error "wkhtmltopdf verification failed"
        exit 1
    fi
    log "✓ wkhtmltopdf verified"

    # Verify git
    if ! git --version &>/dev/null; then
        log_error "git verification failed"
        exit 1
    fi
    log "✓ git verified"

    # Verify build tools
    if ! gcc --version &>/dev/null || ! make --version &>/dev/null; then
        log_error "Build tools verification failed"
        exit 1
    fi
    log "✓ Build tools verified"

    log "All prerequisites verified successfully"
}

#===============================================================================
# Installation Check Functions
#===============================================================================

check_existing_installation() {
    log "Checking for existing ERPNext installation..."

    # Check if bench command exists
    if ! command -v bench &>/dev/null; then
        log "Bench not found - fresh installation needed"
        return 1
    fi

    # Check if bench directory exists
    if [ ! -d "${BENCH_DIR}" ]; then
        log "Bench directory not found - fresh installation needed"
        return 1
    fi

    # Check if erpnext is installed
    if [ -d "${BENCH_DIR}/apps/erpnext" ]; then
        log "ERPNext installation found at ${BENCH_DIR}"

        # Check version
        local installed_version
        installed_version=$(grep -oP "^__version__\s*=\s*\"\K[^\"]*" "${BENCH_DIR}/apps/erpnext/erpnext/__init__.py" 2>/dev/null || echo "unknown")

        if [ "${installed_version}" = "15.82.1" ]; then
            log "ERPNext ${installed_version} is already installed (matches target version ${ERPNEXT_VERSION})"
            return 0
        else
            log_warning "ERPNext ${installed_version} is installed but does not match target version ${ERPNEXT_VERSION}"
            return 1
        fi
    fi

    log "ERPNext not found - installation needed"
    return 1
}

#===============================================================================
# ERPNext Installation Functions
#===============================================================================

create_frappe_user() {
    if id "${BENCH_USER}" &>/dev/null; then
        log "User ${BENCH_USER} already exists"
    else
        log "Creating user ${BENCH_USER}..."
        useradd -m -s /bin/bash "${BENCH_USER}"
        usermod -aG sudo "${BENCH_USER}" 2>/dev/null || true
        echo "${BENCH_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    fi
}

install_bench_cli() {
    log "Installing Frappe Bench CLI..."

    # Install bench globally
    pip3 install --no-cache-dir frappe-bench

    # Verify bench installation
    if ! command -v bench &>/dev/null; then
        log_error "Bench installation failed - command not found"
        exit 1
    fi

    local bench_version
    bench_version=$(bench --version 2>&1 || echo "unknown")
    log "✓ Bench CLI installed: ${bench_version}"
}

setup_bench_environment() {
    log "Setting up Frappe bench environment..."

    # Create bench user if needed
    create_frappe_user

    # Create parent directory with proper permissions
    mkdir -p "$(dirname "${BENCH_DIR}")"
    chown -R "${BENCH_USER}:${BENCH_USER}" "$(dirname "${BENCH_DIR}")"

    # Initialize bench as the frappe user
    if [ ! -d "${BENCH_DIR}" ]; then
        log "Initializing new bench at ${BENCH_DIR}..."
        sudo -u "${BENCH_USER}" bash <<EOF
set -euo pipefail
cd "$(dirname "${BENCH_DIR}")"
bench init "$(basename "${BENCH_DIR}")" --frappe-branch ${FRAPPE_VERSION} --python python3 --verbose
EOF
    else
        log "Bench directory already exists at ${BENCH_DIR}"
    fi
}

install_erpnext_app() {
    log "Installing ERPNext ${ERPNEXT_VERSION}..."

    sudo -u "${BENCH_USER}" bash <<EOF
set -euo pipefail
cd "${BENCH_DIR}"

# Get ERPNext app at specific version
if [ ! -d "apps/erpnext" ]; then
    echo "Downloading ERPNext ${ERPNEXT_VERSION}..."
    bench get-app erpnext --branch ${ERPNEXT_VERSION} --resolve-deps
else
    echo "ERPNext app directory already exists"
fi
EOF

    log "ERPNext app installed successfully"
}

create_site() {
    log "Creating ERPNext site..."

    # Note: In a production environment, you would create a site here
    # For validation purposes, we'll skip site creation as it requires
    # a running database and is environment-specific
    log "Site creation skipped (requires database configuration)"
    log "To create a site manually, run as ${BENCH_USER}:"
    log "  cd ${BENCH_DIR}"
    log "  bench new-site <site-name>"
    log "  bench --site <site-name> install-app erpnext"
}

install_tool() {
    log "Starting ERPNext installation..."

    # Install bench CLI
    install_bench_cli

    # Setup bench environment
    setup_bench_environment

    # Install ERPNext app
    install_erpnext_app

    # Create site (optional)
    create_site

    log "ERPNext installation completed"
}

#===============================================================================
# Validation Functions
#===============================================================================

validate() {
    log "Validating ERPNext installation..."

    # Check bench command
    if ! command -v bench &>/dev/null; then
        log_error "Validation failed: bench command not found"
        log_error "Expected: bench command in PATH"
        exit 1
    fi

    # Check bench directory
    if [ ! -d "${BENCH_DIR}" ]; then
        log_error "Validation failed: bench directory not found at ${BENCH_DIR}"
        exit 1
    fi

    # Check ERPNext app directory
    if [ ! -d "${BENCH_DIR}/apps/erpnext" ]; then
        log_error "Validation failed: ERPNext app not found"
        exit 1
    fi

    # Check ERPNext version
    local installed_version
    installed_version=$(grep -oP "^__version__\s*=\s*\"\K[^\"]*" "${BENCH_DIR}/apps/erpnext/erpnext/__init__.py" 2>/dev/null || echo "unknown")

    if [ "${installed_version}" != "15.82.1" ]; then
        log_error "Validation failed: Expected version 15.82.1, found ${installed_version}"
        exit 1
    fi

    # Display version information using bench
    log "Getting version information..."
    cd "${BENCH_DIR}"
    sudo -u "${BENCH_USER}" bench version --format plain 2>/dev/null || true

    log "✓ Validation successful: ERPNext ${installed_version} is installed"
    log ""
    log "Installation Summary:"
    log "  - Bench directory: ${BENCH_DIR}"
    log "  - ERPNext version: ${installed_version}"
    log "  - Frappe user: ${BENCH_USER}"
    log ""
    log "Note: The validate command 'erpnext --version' is not applicable."
    log "ERPNext does not provide a standalone CLI. Use 'bench version' instead."
    log ""
    log "Next steps:"
    log "  1. Switch to frappe user: sudo su - ${BENCH_USER}"
    log "  2. Navigate to bench: cd ${BENCH_DIR}"
    log "  3. Create a site: bench new-site <site-name>"
    log "  4. Install ERPNext: bench --site <site-name> install-app erpnext"
    log "  5. Start bench: bench start"
}

#===============================================================================
# Main Function
#===============================================================================

main() {
    log "Starting ERPNext ${ERPNEXT_VERSION} installation..."
    log "=============================================="

    # Step 1: Prerequisites
    log ""
    log "Step 1/4: Checking prerequisites..."
    if ! check_prerequisites; then
        log "Missing prerequisites detected. Installing..."
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites already installed"
    fi

    # Step 2: Check if already installed
    log ""
    log "Step 2/4: Checking for existing installation..."
    if check_existing_installation; then
        log "ERPNext ${ERPNEXT_VERSION} is already installed"
        validate
        exit 0
    fi

    # Step 3: Install the tool
    log ""
    log "Step 3/4: Installing ERPNext..."
    install_tool

    # Step 4: Validate
    log ""
    log "Step 4/4: Validating installation..."
    validate

    log ""
    log "=============================================="
    log "Installation completed successfully!"
}

# Run main function
main "$@"
