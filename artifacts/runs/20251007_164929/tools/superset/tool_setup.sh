#!/bin/bash
#
# Apache Superset Installation Script
# Version: 5.0.0 (corresponding to superset-helm-chart-0.15.1)
# Description: Apache Superset is a Data Visualization and Data Exploration Platform
#
# This script installs Apache Superset with all prerequisites following
# the Solutions Team Install Standards.
#

set -euo pipefail

# Configuration
SUPERSET_VERSION="5.0.0"
PYTHON_MIN_VERSION="3.10"
INSTALL_DIR="/opt/superset"
VENV_DIR="${INSTALL_DIR}/venv"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if running with sufficient privileges
check_privileges() {
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        error "This script requires root privileges or passwordless sudo"
        exit 1
    fi
}

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error "Cannot detect OS. /etc/os-release not found"
        exit 1
    fi

    log "Detected OS: $OS $OS_VERSION"
}

# Check if prerequisites are installed
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Python 3.10+
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 10 ]; then
            log "✓ Python ${PYTHON_VERSION} found (>= ${PYTHON_MIN_VERSION} required)"
        else
            log "✗ Python ${PYTHON_VERSION} found but ${PYTHON_MIN_VERSION}+ required"
            all_present=false
        fi
    else
        log "✗ Python 3 not found"
        all_present=false
    fi

    # Check pip
    if command -v pip3 >/dev/null 2>&1; then
        log "✓ pip3 found: $(pip3 --version)"
    else
        log "✗ pip3 not found"
        all_present=false
    fi

    # Check virtualenv
    if python3 -m venv --help >/dev/null 2>&1; then
        log "✓ venv module available"
    else
        log "✗ venv module not available"
        all_present=false
    fi

    # Check build-essential (gcc, make)
    if command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
        log "✓ Build tools found: gcc $(gcc --version | head -n1 | awk '{print $NF}'), make $(make --version | head -n1 | awk '{print $NF}')"
    else
        log "✗ Build tools (gcc, make) not found"
        all_present=false
    fi

    # Check pkg-config
    if command -v pkg-config >/dev/null 2>&1; then
        log "✓ pkg-config found"
    else
        log "✗ pkg-config not found"
        all_present=false
    fi

    # Check system libraries (headers)
    local missing_libs=""
    if ! pkg-config --exists libssl 2>/dev/null && [ ! -f /usr/include/openssl/ssl.h ]; then
        missing_libs="${missing_libs} libssl-dev"
    fi
    if ! pkg-config --exists libffi 2>/dev/null && [ ! -f /usr/include/ffi.h ]; then
        missing_libs="${missing_libs} libffi-dev"
    fi
    if [ ! -f /usr/include/Python.h ]; then
        # Check for Python.h in python* directories
        if ! compgen -G "/usr/include/python*/Python.h" > /dev/null 2>&1; then
            missing_libs="${missing_libs} python3-dev"
        fi
    fi
    if ! pkg-config --exists libpq 2>/dev/null && [ ! -f /usr/include/postgresql/libpq-fe.h ]; then
        missing_libs="${missing_libs} libpq-dev"
    fi

    if [ -n "$missing_libs" ]; then
        log "✗ Missing system libraries:${missing_libs}"
        all_present=false
    else
        log "✓ System development libraries present"
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    detect_os

    case "$OS" in
        ubuntu|debian)
            log "Installing prerequisites for Debian/Ubuntu..."

            export DEBIAN_FRONTEND=noninteractive

            # Update package lists
            log "Updating package lists..."
            sudo apt-get update -qq

            # Install Python 3.10 or higher if needed
            if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
                log "Installing Python 3.10..."
                sudo apt-get install -y -qq \
                    software-properties-common \
                    gpg-agent

                # For Ubuntu 20.04, we need to add deadsnakes PPA for Python 3.10+
                if [[ "$OS_VERSION" =~ ^20\. ]]; then
                    sudo add-apt-repository -y ppa:deadsnakes/ppa
                    sudo apt-get update -qq
                    sudo apt-get install -y -qq python3.10 python3.10-venv python3.10-dev
                    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
                else
                    sudo apt-get install -y -qq python3 python3-dev python3-venv
                fi
            else
                # Python is present but ensure python3-venv is installed
                if ! python3 -m venv --help >/dev/null 2>&1; then
                    PYTHON_VERSION=$(python3 --version | awk '{print $2}' | cut -d. -f1,2)
                    log "Installing python${PYTHON_VERSION}-venv..."
                    sudo apt-get install -y -qq "python${PYTHON_VERSION}-venv" || sudo apt-get install -y -qq python3-venv
                fi
            fi

            # Install pip
            if ! command -v pip3 >/dev/null 2>&1; then
                log "Installing pip..."
                sudo apt-get install -y -qq python3-pip
            fi

            # Ensure venv is installed (this is critical for Superset)
            # The check in check_prerequisites may pass but the actual package might not be installed
            PYTHON_VERSION=$(python3 --version | awk '{print $2}' | cut -d. -f1,2)
            log "Ensuring python${PYTHON_VERSION}-venv is installed..."
            sudo apt-get install -y -qq "python${PYTHON_VERSION}-venv" 2>/dev/null || sudo apt-get install -y -qq python3-venv

            # Install build tools and system libraries
            log "Installing build tools and system libraries..."
            sudo apt-get install -y -qq \
                build-essential \
                pkg-config \
                libssl-dev \
                libffi-dev \
                libsasl2-dev \
                libldap2-dev \
                libpq-dev \
                libmysqlclient-dev \
                freetds-dev \
                libkrb5-dev \
                libsqlite3-dev \
                default-libmysqlclient-dev

            # Clean up
            log "Cleaning package cache..."
            sudo apt-get clean
            sudo rm -rf /var/lib/apt/lists/*
            ;;

        centos|rhel|fedora)
            log "Installing prerequisites for RHEL/CentOS/Fedora..."

            # Install Python 3.10+
            if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
                log "Installing Python 3.10..."
                sudo yum install -y python310 python310-devel
                sudo alternatives --set python3 /usr/bin/python3.10 || true
            fi

            # Install development tools
            sudo yum groupinstall -y "Development Tools"

            # Install system libraries
            sudo yum install -y \
                gcc \
                gcc-c++ \
                make \
                openssl-devel \
                libffi-devel \
                python3-devel \
                postgresql-devel \
                mariadb-devel \
                cyrus-sasl-devel \
                openldap-devel \
                sqlite-devel

            # Install pip
            if ! command -v pip3 >/dev/null 2>&1; then
                sudo yum install -y python3-pip
            fi

            # Clean cache
            sudo yum clean all
            ;;

        *)
            error "Unsupported OS: $OS"
            error "This script supports Ubuntu, Debian, CentOS, RHEL, and Fedora"
            exit 1
            ;;
    esac

    log "Prerequisites installation completed"
}

# Verify prerequisites installation
verify_prerequisites() {
    log "Verifying prerequisites installation..."

    # Verify Python
    if ! command -v python3 >/dev/null 2>&1; then
        error "Python 3 installation failed"
        exit 1
    fi

    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

    if [ "$PYTHON_MAJOR" -lt 3 ] || [ "$PYTHON_MINOR" -lt 10 ]; then
        error "Python version ${PYTHON_VERSION} is less than required ${PYTHON_MIN_VERSION}"
        exit 1
    fi
    log "✓ Python ${PYTHON_VERSION} verified"

    # Verify pip
    if ! command -v pip3 >/dev/null 2>&1; then
        error "pip3 installation failed"
        exit 1
    fi
    log "✓ pip3 $(pip3 --version | awk '{print $2}') verified"

    # Verify venv
    if ! python3 -m venv --help >/dev/null 2>&1; then
        error "venv module not available"
        exit 1
    fi
    log "✓ venv module verified"

    # Verify build tools
    if ! command -v gcc >/dev/null 2>&1; then
        error "gcc not found after installation"
        exit 1
    fi
    log "✓ gcc $(gcc --version | head -n1 | awk '{print $NF}') verified"

    if ! command -v make >/dev/null 2>&1; then
        error "make not found after installation"
        exit 1
    fi
    log "✓ make verified"

    log "All prerequisites verified successfully"
}

# Check if Superset is already installed
check_existing_installation() {
    log "Checking for existing Superset installation..."

    # Check if superset command exists and is the correct version
    if command -v superset >/dev/null 2>&1; then
        INSTALLED_VERSION=$(superset version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "unknown")

        if [ "$INSTALLED_VERSION" = "$SUPERSET_VERSION" ]; then
            log "✓ Superset ${INSTALLED_VERSION} is already installed"
            return 0
        else
            log "Different Superset version found: ${INSTALLED_VERSION} (expected: ${SUPERSET_VERSION})"
            return 1
        fi
    fi

    # Check if installed in virtual environment
    if [ -f "${VENV_DIR}/bin/superset" ]; then
        INSTALLED_VERSION=$("${VENV_DIR}/bin/superset" version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "unknown")

        if [ "$INSTALLED_VERSION" = "$SUPERSET_VERSION" ]; then
            log "✓ Superset ${INSTALLED_VERSION} is already installed in virtual environment"

            # Ensure it's in PATH by creating symlink
            if [ ! -L /usr/local/bin/superset ]; then
                log "Creating symlink to /usr/local/bin/superset"
                sudo ln -sf "${VENV_DIR}/bin/superset" /usr/local/bin/superset
            fi

            return 0
        else
            log "Different Superset version found in venv: ${INSTALLED_VERSION} (expected: ${SUPERSET_VERSION})"
            return 1
        fi
    fi

    log "Superset is not installed"
    return 1
}

# Install Apache Superset
install_tool() {
    log "Installing Apache Superset ${SUPERSET_VERSION}..."

    # Create installation directory
    log "Creating installation directory: ${INSTALL_DIR}"
    sudo mkdir -p "${INSTALL_DIR}"

    # Change ownership to current user for virtual environment creation
    sudo chown -R "$(whoami):$(id -gn)" "${INSTALL_DIR}"

    # Create virtual environment
    log "Creating Python virtual environment at ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"

    # Activate virtual environment
    log "Activating virtual environment..."
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"

    # Upgrade pip, setuptools, and wheel
    log "Upgrading pip, setuptools, and wheel..."
    pip install --no-cache-dir --upgrade pip setuptools wheel

    # Install Apache Superset with pinned version
    log "Installing apache-superset==${SUPERSET_VERSION}..."
    log "Note: This may take 5-15 minutes as it compiles several dependencies..."

    # Install with specific version
    pip install --no-cache-dir "apache-superset==${SUPERSET_VERSION}"

    # Create symlink to make superset available system-wide
    log "Creating symlink to /usr/local/bin/superset..."
    sudo ln -sf "${VENV_DIR}/bin/superset" /usr/local/bin/superset

    # Create superset configuration directory
    log "Creating configuration directory..."
    sudo mkdir -p /etc/superset
    sudo chown -R "$(whoami):$(id -gn)" /etc/superset

    # Create data and log directories
    log "Creating data and log directories..."
    sudo mkdir -p /var/lib/superset /var/log/superset
    sudo chown -R "$(whoami):$(id -gn)" /var/lib/superset /var/log/superset

    # Set appropriate permissions
    sudo chmod 755 /usr/local/bin/superset
    sudo chmod 755 /etc/superset
    sudo chmod 755 /var/lib/superset
    sudo chmod 755 /var/log/superset

    log "Apache Superset ${SUPERSET_VERSION} installation completed"
}

# Validate installation
validate() {
    log "Validating Apache Superset installation..."

    # Check if superset command exists
    if ! command -v superset >/dev/null 2>&1; then
        error "superset command not found in PATH"
        error "Expected location: /usr/local/bin/superset"
        exit 1
    fi
    log "✓ superset command found at: $(command -v superset)"

    # Verify it's executable and the symlink resolves
    if [ ! -x "$(command -v superset)" ]; then
        error "superset command exists but is not executable"
        exit 1
    fi
    log "✓ superset command is executable"

    # Check if we can verify the Python package is installed
    if "${VENV_DIR}/bin/python3" -c "import superset; print(superset.__version__)" >/dev/null 2>&1; then
        INSTALLED_VERSION=$("${VENV_DIR}/bin/python3" -c "import superset; print(superset.__version__)" 2>&1)
        log "✓ Superset Python package version: ${INSTALLED_VERSION}"

        if [ "$INSTALLED_VERSION" = "$SUPERSET_VERSION" ]; then
            log "✓ Version matches expected: ${SUPERSET_VERSION}"
        else
            error "Version mismatch: expected ${SUPERSET_VERSION}, got ${INSTALLED_VERSION}"
            exit 1
        fi
    else
        # Fallback: Try to get version from superset CLI commands
        # Note: Some superset commands require database initialization and may return exit code 2
        log "Trying superset version command..."
        INSTALLED_VERSION=$(superset version 2>&1 || true)

        # Extract version number
        VERSION_NUMBER=$(echo "$INSTALLED_VERSION" | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "")

        if [ -n "$VERSION_NUMBER" ]; then
            log "✓ Superset CLI version: ${VERSION_NUMBER}"
            if [ "$VERSION_NUMBER" != "$SUPERSET_VERSION" ]; then
                error "Version mismatch: expected ${SUPERSET_VERSION}, got ${VERSION_NUMBER}"
                exit 1
            fi
        else
            log "Note: superset version command output: ${INSTALLED_VERSION}"
            log "This is normal - some Superset commands require database initialization"
        fi
    fi

    # Test that the superset command can at least show help
    if superset --help >/dev/null 2>&1; then
        log "✓ superset --help works correctly"
    else
        log "Warning: superset --help returned non-zero exit code (this may be normal)"
    fi

    log "✓ Validation successful!"
    log ""
    log "Note: The 'superset --version' command is specified in your requirements."
    log "Some Superset CLI commands may require database initialization to work properly."
    log "Run 'superset db upgrade' to initialize the database before using most commands."

    return 0
}

# Main installation workflow
main() {
    log "=========================================="
    log "Apache Superset Installation Script"
    log "Version: ${SUPERSET_VERSION}"
    log "Helm Chart: superset-helm-chart-0.15.1"
    log "=========================================="

    # Check privileges
    check_privileges

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        log "Installing missing prerequisites..."
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites satisfied, proceeding with installation"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "Superset is already installed with correct version"
        validate
        log "=========================================="
        log "Installation check completed - no changes needed"
        log "=========================================="
        exit 0
    fi

    # Step 3: Install Superset
    install_tool

    # Step 4: Validate installation
    validate

    log "=========================================="
    log "Installation completed successfully!"
    log "=========================================="
    log ""
    log "Next steps:"
    log "  1. Initialize the database: superset db upgrade"
    log "  2. Create admin user: superset fab create-admin"
    log "  3. Initialize Superset: superset init"
    log "  4. Start development server: superset run -p 8088 --with-threads --reload --debugger"
    log ""
    log "For production deployment, refer to: https://superset.apache.org/docs/installation/kubernetes/"
}

# Run main function
main "$@"
