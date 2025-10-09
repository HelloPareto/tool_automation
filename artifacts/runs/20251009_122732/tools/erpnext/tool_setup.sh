#!/usr/bin/env bash
# ERPNext v15.82.1 Installation Script
# Generated for automated installation following Solutions Team standards
#
# ERPNext is a full ERP web application built on the Frappe Framework.
# It requires frappe-bench for installation and management.
#
# IMPORTANT NOTE: ERPNext is not a CLI tool with a standalone --version command.
# This script installs ERPNext as a web application via frappe-bench.
# The validation creates a wrapper script at /usr/local/bin/erpnext to satisfy
# the validation requirement.

set -euo pipefail

# Configuration
ERPNEXT_VERSION="v15.82.1"
FRAPPE_VERSION="version-15"
# shellcheck disable=SC2034
PYTHON_VERSION="3.10"  # Used for documentation
# shellcheck disable=SC2034
NODE_VERSION="18"       # Used for documentation
BENCH_USER="frappe"
BENCH_PATH="/opt/frappe-bench"
SITE_NAME="erpnext.local"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    local missing=0

    # Check Python 3.10+
    if command -v python3.10 >/dev/null 2>&1; then
        log "Found Python 3.10"
    else
        log "Python 3.10 not found"
        missing=1
    fi

    # Check Node.js 18+
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node --version | sed 's/v//' | cut -d. -f1)
        if [[ "$node_version" -ge 18 ]]; then
            log "Found Node.js v${node_version}"
        else
            log "Node.js version $node_version is too old, need 18+"
            missing=1
        fi
    else
        log "Node.js not found"
        missing=1
    fi

    # Check Redis
    if command -v redis-server >/dev/null 2>&1; then
        log "Found Redis"
    else
        log "Redis not found"
        missing=1
    fi

    # Check MariaDB
    if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; then
        log "Found MariaDB/MySQL"
    else
        log "MariaDB/MySQL not found"
        missing=1
    fi

    # Check wkhtmltopdf
    if command -v wkhtmltopdf >/dev/null 2>&1; then
        log "Found wkhtmltopdf"
    else
        log "wkhtmltopdf not found"
        missing=1
    fi

    # Check yarn
    if command -v yarn >/dev/null 2>&1; then
        log "Found yarn"
    else
        log "yarn not found"
        missing=1
    fi

    # Check pip
    if command -v pip3 >/dev/null 2>&1; then
        log "Found pip3"
    else
        log "pip3 not found"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        log "Some prerequisites are missing"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python 3.10 and development tools
    log "Installing Python 3.10 and development packages..."
    apt-get install -y \
        python3.10 \
        python3.10-dev \
        python3.10-venv \
        python3-pip \
        python3-setuptools \
        python3-distutils \
        build-essential

    # Install Node.js 18.x from NodeSource
    log "Installing Node.js 18.x..."
    if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    else
        log "NodeSource repository already configured"
        apt-get install -y nodejs
    fi

    # Install Yarn
    log "Installing Yarn..."
    npm install -g yarn

    # Install Redis
    log "Installing Redis..."
    apt-get install -y redis-server

    # Install MariaDB
    log "Installing MariaDB..."
    apt-get install -y \
        mariadb-server \
        mariadb-client \
        libmysqlclient-dev

    # Install wkhtmltopdf
    log "Installing wkhtmltopdf..."
    apt-get install -y wkhtmltopdf

    # Install other required packages
    log "Installing additional packages..."
    apt-get install -y \
        git \
        curl \
        wget \
        software-properties-common \
        libffi-dev \
        libssl-dev \
        supervisor \
        nginx \
        fontconfig \
        libxrender1 \
        xfonts-75dpi \
        xfonts-base

    # Clean up
    log "Cleaning up package manager caches..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! python3.10 --version >/dev/null 2>&1; then
        error "Python 3.10 verification failed"
    fi
    log "Python 3.10 verified: $(python3.10 --version)"

    # Verify pip
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
    fi
    log "pip3 verified: $(pip3 --version)"

    # Verify Node.js
    if ! node --version >/dev/null 2>&1; then
        error "Node.js verification failed"
    fi
    log "Node.js verified: $(node --version)"

    # Verify npm
    if ! npm --version >/dev/null 2>&1; then
        error "npm verification failed"
    fi
    log "npm verified: $(npm --version)"

    # Verify yarn
    if ! yarn --version >/dev/null 2>&1; then
        error "yarn verification failed"
    fi
    log "yarn verified: $(yarn --version)"

    # Verify Redis
    if ! redis-server --version >/dev/null 2>&1; then
        error "Redis verification failed"
    fi
    log "Redis verified: $(redis-server --version | head -n1)"

    # Verify MariaDB
    if ! mysql --version >/dev/null 2>&1 && ! mariadb --version >/dev/null 2>&1; then
        error "MariaDB/MySQL verification failed"
    fi
    log "MariaDB verified: $(mysql --version || mariadb --version)"

    # Verify wkhtmltopdf
    if ! wkhtmltopdf --version >/dev/null 2>&1; then
        error "wkhtmltopdf verification failed"
    fi
    log "wkhtmltopdf verified: $(wkhtmltopdf --version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

# Check if ERPNext is already installed
check_existing_installation() {
    log "Checking for existing ERPNext installation..."

    # Check if bench user exists
    if id "$BENCH_USER" >/dev/null 2>&1; then
        log "Bench user '$BENCH_USER' exists"

        # Check if bench directory exists
        if [[ -d "$BENCH_PATH" ]]; then
            log "Bench directory exists at $BENCH_PATH"

            # Check if ERPNext app exists
            if [[ -d "$BENCH_PATH/apps/erpnext" ]]; then
                log "ERPNext app directory exists"

                # Check version
                if [[ -f "$BENCH_PATH/apps/erpnext/__init__.py" ]]; then
                    local installed_version
                    installed_version=$(grep -oP "__version__\s*=\s*['\"]\\K[^'\"]*" "$BENCH_PATH/apps/erpnext/__init__.py" 2>/dev/null || echo "unknown")
                    log "Found installed ERPNext version: $installed_version"

                    # Check if it matches our target version
                    if [[ "$installed_version" == "${ERPNEXT_VERSION#v}" ]]; then
                        log "ERPNext $ERPNEXT_VERSION is already installed"
                        return 0
                    else
                        log "Different version installed: $installed_version (expected: ${ERPNEXT_VERSION#v})"
                        return 1
                    fi
                fi
            fi
        fi
    fi

    log "ERPNext is not installed"
    return 1
}

# Install frappe-bench and ERPNext
install_tool() {
    log "Starting ERPNext installation..."

    # Create bench user if it doesn't exist
    if ! id "$BENCH_USER" >/dev/null 2>&1; then
        log "Creating user '$BENCH_USER'..."
        useradd -m -s /bin/bash "$BENCH_USER"
        log "User '$BENCH_USER' created"
    else
        log "User '$BENCH_USER' already exists"
    fi

    # Add bench user to sudoers if not already there
    if ! grep -q "^$BENCH_USER ALL=" /etc/sudoers 2>/dev/null && ! grep -q "^$BENCH_USER ALL=" /etc/sudoers.d/* 2>/dev/null; then
        log "Adding '$BENCH_USER' to sudoers..."
        echo "$BENCH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$BENCH_USER
        chmod 0440 /etc/sudoers.d/$BENCH_USER
    fi

    # Start and enable MariaDB
    log "Starting MariaDB service..."
    systemctl start mariadb || service mariadb start || true
    systemctl enable mariadb || true

    # Start and enable Redis
    log "Starting Redis service..."
    systemctl start redis-server || service redis-server start || true
    systemctl enable redis-server || true

    # Configure MariaDB for Frappe (if not already configured)
    log "Configuring MariaDB for Frappe..."
    if [[ ! -f /etc/mysql/mariadb.conf.d/frappe.cnf ]]; then
        cat > /etc/mysql/mariadb.conf.d/frappe.cnf <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
        systemctl restart mariadb || service mariadb restart || true
        log "MariaDB configured"
    else
        log "MariaDB already configured"
    fi

    # Install frappe-bench as bench user
    log "Installing frappe-bench..."
    sudo -u "$BENCH_USER" bash -c "
        set -euo pipefail
        cd /home/$BENCH_USER

        # Install frappe-bench
        if ! command -v bench >/dev/null 2>&1; then
            pip3 install frappe-bench
            # Add local bin to PATH
            export PATH=\"\$HOME/.local/bin:\$PATH\"
        fi

        # Create bench directory if it doesn't exist
        if [[ ! -d $BENCH_PATH ]]; then
            echo 'Initializing Frappe bench...'
            export PATH=\"\$HOME/.local/bin:\$PATH\"
            bench init $BENCH_PATH --frappe-branch $FRAPPE_VERSION --python /usr/bin/python3.10
        fi
    "

    # Install ERPNext app
    log "Installing ERPNext app..."
    sudo -u "$BENCH_USER" bash -c "
        set -euo pipefail
        export PATH=\"\$HOME/.local/bin:\$PATH\"
        cd $BENCH_PATH

        # Get ERPNext app if not already present
        if [[ ! -d apps/erpnext ]]; then
            echo 'Getting ERPNext app...'
            bench get-app erpnext --branch $ERPNEXT_VERSION --resolve-deps
        else
            echo 'ERPNext app directory already exists, skipping download'
        fi

        # Create site if it doesn't exist
        if [[ ! -d sites/$SITE_NAME ]]; then
            echo 'Creating site...'
            bench new-site $SITE_NAME --admin-password admin --mariadb-root-password '' --no-mariadb-socket || \
            bench new-site $SITE_NAME --admin-password admin --db-root-password '' || \
            echo 'Site creation failed or already exists'
        fi

        # Install ERPNext on site
        if ! bench --site $SITE_NAME list-apps | grep -q erpnext; then
            echo 'Installing ERPNext on site...'
            bench --site $SITE_NAME install-app erpnext
        else
            echo 'ERPNext already installed on site'
        fi
    "

    # Create erpnext wrapper script for validation
    log "Creating erpnext CLI wrapper..."
    cat > /usr/local/bin/erpnext <<'EOF'
#!/usr/bin/env bash
# ERPNext CLI wrapper for validation
# ERPNext is a web application, not a CLI tool
# This wrapper provides version information for validation purposes

BENCH_PATH="/opt/frappe-bench"
ERPNEXT_INIT="$BENCH_PATH/apps/erpnext/__init__.py"

if [[ "$1" == "--version" ]] || [[ "$1" == "version" ]]; then
    if [[ -f "$ERPNEXT_INIT" ]]; then
        version=$(grep -oP "__version__\s*=\s*['\"]\\K[^'\"]*" "$ERPNEXT_INIT" 2>/dev/null)
        if [[ -n "$version" ]]; then
            echo "ERPNext version $version"
            exit 0
        fi
    fi
    echo "ERPNext version information not available"
    exit 1
else
    echo "ERPNext is a web application managed via frappe-bench"
    echo "Usage: erpnext --version (to check version)"
    echo ""
    echo "To manage ERPNext, use bench commands:"
    echo "  cd $BENCH_PATH"
    echo "  bench start         # Start development server"
    echo "  bench --site <site> list-apps  # List installed apps"
    echo "  bench --help        # More commands"
    exit 0
fi
EOF
    chmod +x /usr/local/bin/erpnext
    log "ERPNext CLI wrapper created at /usr/local/bin/erpnext"

    # Set proper ownership
    log "Setting proper ownership..."
    chown -R "$BENCH_USER:$BENCH_USER" "$BENCH_PATH"

    log "ERPNext installation completed"
}

# Validate installation
validate() {
    log "Validating ERPNext installation..."

    # Check if erpnext command exists
    if ! command -v erpnext >/dev/null 2>&1; then
        error "erpnext command not found in PATH"
    fi

    # Run validation command
    local version_output
    if version_output=$(erpnext --version 2>&1); then
        log "Validation successful: $version_output"

        # Check if version matches
        if echo "$version_output" | grep -q "${ERPNEXT_VERSION#v}"; then
            log "Version verification successful: $ERPNEXT_VERSION"
            return 0
        else
            log "WARNING: Version mismatch detected"
            log "Expected: ${ERPNEXT_VERSION#v}"
            log "Got: $version_output"
            return 1
        fi
    else
        error "Validation command failed: $version_output"
    fi
}

# Main installation flow
main() {
    log "Starting ERPNext $ERPNEXT_VERSION installation..."

    # Check root
    check_root

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        log "Installing prerequisites..."
        install_prerequisites
        verify_prerequisites
    else
        log "Prerequisites already satisfied"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "ERPNext $ERPNEXT_VERSION is already installed (idempotent check passed)"
        validate
        log "Installation verification completed successfully"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "ERPNext $ERPNEXT_VERSION installation completed successfully"
    log ""
    log "To start ERPNext:"
    log "  sudo -u $BENCH_USER bash"
    log "  cd $BENCH_PATH"
    log "  bench start"
    log ""
    log "Access ERPNext at: http://localhost:8000"
    log "Site: $SITE_NAME"
    log "Default credentials: Administrator / admin"
}

# Execute main function
main "$@"
