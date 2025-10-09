#!/usr/bin/env bash

###############################################################################
# Apache Superset Installation Script
# Version: superset-helm-chart-0.15.1 (Superset 5.0.0)
# Description: Installs Apache Superset Data Visualization Platform
###############################################################################

set -euo pipefail

# Configuration
SUPERSET_VERSION="5.0.0"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Logging Functions
###############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

###############################################################################
# Prerequisite Detection
###############################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for Python 3.10 or 3.11
    if command -v python3.11 &> /dev/null; then
        PYTHON_CMD="python3.11"
        log "Found Python 3.11: $(python3.11 --version)"
    elif command -v python3.10 &> /dev/null; then
        PYTHON_CMD="python3.10"
        log "Found Python 3.10: $(python3.10 --version)"
    elif command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        local py_version
        py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        log "Found Python: $(python3 --version) (version: ${py_version})"

        # Check if version is 3.10 or 3.11
        if [[ "${py_version}" != "3.10" && "${py_version}" != "3.11" ]]; then
            log_warn "Python ${py_version} found, but Superset 5.0.0 requires Python 3.10 or 3.11"
            missing_prereqs=1
        fi
    else
        log_warn "Python 3 not found"
        missing_prereqs=1
    fi

    # Check for pip
    if ! command -v pip3 &> /dev/null && ! ${PYTHON_CMD:-python3} -m pip --version &> /dev/null; then
        log_warn "pip3 not found"
        missing_prereqs=1
    else
        log "Found pip: $(${PYTHON_CMD:-python3} -m pip --version 2>/dev/null || pip3 --version)"
    fi

    # Check for build essentials (required for some Python packages)
    if ! command -v gcc &> /dev/null; then
        log_warn "gcc not found (build-essential required)"
        missing_prereqs=1
    else
        log "Found gcc: $(gcc --version | head -n1)"
    fi

    # Check for pkg-config (required for some dependencies)
    if ! command -v pkg-config &> /dev/null; then
        log_warn "pkg-config not found"
        missing_prereqs=1
    else
        log "Found pkg-config: $(pkg-config --version)"
    fi

    if [[ ${missing_prereqs} -eq 1 ]]; then
        log "Some prerequisites are missing and need to be installed"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

###############################################################################
# Prerequisite Installation
###############################################################################

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "Cannot detect OS. /etc/os-release not found"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            log "Detected Debian/Ubuntu system"
            export DEBIAN_FRONTEND=noninteractive

            # Update package list
            log "Updating package lists..."
            apt-get update -qq

            # Install Python 3.11 (preferred) or 3.10
            if ! command -v python3.11 &> /dev/null && ! command -v python3.10 &> /dev/null; then
                log "Installing Python 3.11..."
                apt-get install -y -qq \
                    python3.11 \
                    python3.11-dev \
                    python3.11-venv \
                    python3-pip \
                    || apt-get install -y -qq \
                        python3.10 \
                        python3.10-dev \
                        python3.10-venv \
                        python3-pip

                PYTHON_CMD=$(command -v python3.11 || command -v python3.10 || command -v python3)
            fi

            # Install build dependencies
            log "Installing build dependencies..."
            apt-get install -y -qq \
                build-essential \
                libssl-dev \
                libffi-dev \
                python3-dev \
                libsasl2-dev \
                libldap2-dev \
                libxi-dev \
                pkg-config \
                libmariadb-dev \
                libpq-dev

            # Clean up
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;

        centos|rhel|fedora)
            log "Detected RHEL/CentOS/Fedora system"

            # Install Python 3.11 or 3.10
            if ! command -v python3.11 &> /dev/null && ! command -v python3.10 &> /dev/null; then
                log "Installing Python 3.11..."
                yum install -y python311 python311-devel python311-pip \
                    || yum install -y python3.11 python3.11-devel \
                    || yum install -y python310 python310-devel python310-pip \
                    || yum install -y python3.10 python3.10-devel

                PYTHON_CMD=$(command -v python3.11 || command -v python3.10 || command -v python3)
            fi

            # Install build dependencies
            log "Installing build dependencies..."
            yum groupinstall -y "Development Tools"
            yum install -y \
                openssl-devel \
                libffi-devel \
                python3-devel \
                cyrus-sasl-devel \
                openldap-devel \
                libXi-devel \
                pkg-config \
                mariadb-devel \
                postgresql-devel

            yum clean all
            ;;

        *)
            log_error "Unsupported OS: $OS"
            log_error "Please install Python 3.10 or 3.11, pip, and build-essential manually"
            exit 1
            ;;
    esac

    log "Prerequisites installation completed"
}

###############################################################################
# Prerequisite Verification
###############################################################################

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! command -v "${PYTHON_CMD:-python3}" &> /dev/null; then
        log_error "Python verification failed: ${PYTHON_CMD:-python3} not found"
        exit 1
    fi

    local py_version
    py_version=$(${PYTHON_CMD:-python3} -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    log "Python verification successful: ${PYTHON_CMD:-python3} version ${py_version}"

    if [[ "${py_version}" != "3.10" && "${py_version}" != "3.11" ]]; then
        log_error "Python version ${py_version} is not supported. Superset 5.0.0 requires Python 3.10 or 3.11"
        exit 1
    fi

    # Verify pip
    if ! ${PYTHON_CMD:-python3} -m pip --version &> /dev/null; then
        log_error "pip verification failed"
        exit 1
    fi
    log "pip verification successful: $(${PYTHON_CMD:-python3} -m pip --version)"

    # Verify build tools
    if ! command -v gcc &> /dev/null; then
        log_error "gcc verification failed"
        exit 1
    fi
    log "gcc verification successful: $(gcc --version | head -n1)"

    # Verify pkg-config
    if ! command -v pkg-config &> /dev/null; then
        log_error "pkg-config verification failed"
        exit 1
    fi
    log "pkg-config verification successful"

    log "All prerequisites verified successfully"
}

###############################################################################
# Check Existing Installation
###############################################################################

check_existing_installation() {
    log "Checking for existing Superset installation..."

    # Check if apache-superset package is installed
    if ${PYTHON_CMD:-python3} -m pip show apache-superset &> /dev/null; then
        local installed_version
        installed_version=$(${PYTHON_CMD:-python3} -c "from importlib.metadata import version; print(version('apache-superset'))" 2>/dev/null || echo "unknown")

        if [[ "${installed_version}" == "${SUPERSET_VERSION}" ]]; then
            log "Superset ${SUPERSET_VERSION} is already installed"
            return 0
        else
            log "Superset is installed but version is ${installed_version} (expected: ${SUPERSET_VERSION})"
            return 1
        fi
    fi

    log "Superset is not installed"
    return 1
}

###############################################################################
# Install Superset
###############################################################################

install_tool() {
    log "Installing Apache Superset ${SUPERSET_VERSION}..."

    # Upgrade pip, setuptools, and wheel
    log "Upgrading pip, setuptools, and wheel..."
    ${PYTHON_CMD:-python3} -m pip install --upgrade pip setuptools wheel

    # Install apache-superset with pinned version
    log "Installing apache-superset==${SUPERSET_VERSION}..."
    ${PYTHON_CMD:-python3} -m pip install --no-cache-dir "apache-superset==${SUPERSET_VERSION}"

    # Verify superset command is available
    if ! command -v superset &> /dev/null; then
        # Try to find superset in Python scripts directory
        local python_bin_dir
        python_bin_dir=$(${PYTHON_CMD:-python3} -c "import sys; import os; print(os.path.dirname(sys.executable))")

        if [[ -f "${python_bin_dir}/superset" ]]; then
            log "Superset binary found at ${python_bin_dir}/superset"
            # Add to PATH if not already there
            if [[ ":$PATH:" != *":${python_bin_dir}:"* ]]; then
                export PATH="${python_bin_dir}:${PATH}"
                log "Added ${python_bin_dir} to PATH"
            fi
        else
            log_error "Superset command not found after installation"
            log_error "Please check if ${python_bin_dir} is in your PATH"
            exit 1
        fi
    fi

    log "Superset installation completed successfully"
}

###############################################################################
# Validate Installation
###############################################################################

validate() {
    log "Validating Superset installation..."

    # Check if superset command exists
    if ! command -v superset &> /dev/null; then
        # Try to find it in Python scripts directory
        local python_bin_dir
        python_bin_dir=$(${PYTHON_CMD:-python3} -c "import sys; import os; print(os.path.dirname(sys.executable))")

        if [[ -f "${python_bin_dir}/superset" ]]; then
            export PATH="${python_bin_dir}:${PATH}"
        else
            log_error "Superset command not found"
            log_error "Installation validation failed"
            exit 1
        fi
    fi

    # Get installed version
    local installed_version
    installed_version=$(${PYTHON_CMD:-python3} -c "from importlib.metadata import version; print(version('apache-superset'))" 2>/dev/null)

    if [[ -z "${installed_version}" ]]; then
        log_error "Could not determine installed Superset version"
        exit 1
    fi

    log "Installed Superset version: ${installed_version}"

    # Verify version matches
    if [[ "${installed_version}" == "${SUPERSET_VERSION}" ]]; then
        log "✓ Version verification successful: ${installed_version}"
    else
        log_error "Version mismatch: expected ${SUPERSET_VERSION}, got ${installed_version}"
        exit 1
    fi

    # Test superset import
    log "Testing superset import..."
    if ${PYTHON_CMD:-python3} -c "from importlib.metadata import version; print(f'Superset {version(\"apache-superset\")}');" &> /dev/null; then
        log "✓ Superset import works correctly"
    else
        log_error "Superset import test failed"
        exit 1
    fi

    log "✓ Validation completed successfully"
    log "Superset ${installed_version} is ready to use"

    return 0
}

###############################################################################
# Main Installation Flow
###############################################################################

main() {
    log "=========================================="
    log "Apache Superset Installation"
    log "Version: superset-helm-chart-0.15.1 (Superset ${SUPERSET_VERSION})"
    log "=========================================="

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "=========================================="
        log "Installation completed (already installed)"
        log "=========================================="
        exit 0
    fi

    # Step 3: Install Superset
    install_tool

    # Step 4: Validate installation
    validate

    log "=========================================="
    log "Installation completed successfully"
    log "=========================================="
    log ""
    log "Next steps:"
    log "  1. Initialize the database: superset db upgrade"
    log "  2. Create an admin user: superset fab create-admin"
    log "  3. Load examples (optional): superset load_examples"
    log "  4. Initialize: superset init"
    log "  5. Start server: superset run -p 8088"
    log ""
}

# Run main function
main "$@"
