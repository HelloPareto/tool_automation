#!/usr/bin/env bash

###############################################################################
# Apache Airflow 3.1.0 Installation Script
#
# This script installs Apache Airflow version 3.1.0 following Solutions Team
# installation standards with full prerequisite detection and management.
#
# Validation: python -c 'import airflow; print(airflow.__version__)'
###############################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="airflow"
readonly TOOL_VERSION="3.1.0"
readonly PYTHON_MIN_VERSION="3.8"
readonly CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${TOOL_VERSION}/constraints-3.8.txt"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Function to compare version numbers
version_ge() {
    # Returns 0 (true) if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

###############################################################################
# STEP 1: CHECK PREREQUISITES
###############################################################################
check_prerequisites() {
    log "Checking prerequisites for Apache Airflow..."
    local all_present=0

    # Check Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"

        # Extract major.minor version
        local py_major_minor
        py_major_minor=$(echo "$python_version" | cut -d. -f1-2)

        if version_ge "$py_major_minor" "$PYTHON_MIN_VERSION"; then
            log "Python version is sufficient (>= ${PYTHON_MIN_VERSION})"
        else
            error "Python version $python_version is below minimum ${PYTHON_MIN_VERSION}"
            all_present=1
        fi
    else
        log "Python3 not found - needs installation"
        all_present=1
    fi

    # Check pip3
    if command -v pip3 >/dev/null 2>&1; then
        log "Found pip3: $(pip3 --version 2>&1 | cut -d' ' -f1-2)"
    else
        log "pip3 not found - needs installation"
        all_present=1
    fi

    # Check for required system libraries
    if ! dpkg -l | grep -q libpq-dev 2>/dev/null && ! rpm -q postgresql-devel >/dev/null 2>&1; then
        log "PostgreSQL development libraries not found - needs installation"
        all_present=1
    else
        log "Found PostgreSQL development libraries"
    fi

    # Check for build tools (gcc, make)
    if command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
        log "Found build tools: gcc $(gcc --version | head -n1 | awk '{print $NF}')"
    else
        log "Build tools not found - needs installation"
        all_present=1
    fi

    if [ $all_present -eq 0 ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

###############################################################################
# STEP 2: INSTALL PREREQUISITES
###############################################################################
install_prerequisites() {
    log "Installing missing prerequisites..."

    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        install_prerequisites_apt
    elif command -v yum >/dev/null 2>&1; then
        install_prerequisites_yum
    else
        error "No supported package manager found (apt-get or yum required)"
        exit 1
    fi
}

install_prerequisites_apt() {
    log "Using apt-get package manager"

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq

    # Install Python 3 and pip if needed
    if ! command -v python3 >/dev/null 2>&1; then
        log "Installing Python 3..."
        apt-get install -y -qq python3 python3-pip python3-venv python3-dev
    elif ! command -v pip3 >/dev/null 2>&1; then
        log "Installing pip3..."
        apt-get install -y -qq python3-pip python3-venv python3-dev
    fi

    # Install build tools if needed
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        log "Installing build-essential..."
        apt-get install -y -qq build-essential
    fi

    # Install system dependencies for Airflow
    log "Installing Airflow system dependencies..."
    apt-get install -y -qq \
        libpq-dev \
        libssl-dev \
        libffi-dev \
        pkg-config \
        default-libmysqlclient-dev \
        freetds-dev \
        libkrb5-dev \
        libsasl2-dev \
        libldap2-dev

    # Clean up
    log "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully via apt-get"
}

install_prerequisites_yum() {
    log "Using yum package manager"

    # Install Python 3 and pip if needed
    if ! command -v python3 >/dev/null 2>&1; then
        log "Installing Python 3..."
        yum install -y python3 python3-pip python3-devel
    elif ! command -v pip3 >/dev/null 2>&1; then
        log "Installing pip3..."
        yum install -y python3-pip python3-devel
    fi

    # Install build tools if needed
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        log "Installing development tools..."
        yum groupinstall -y "Development Tools"
    fi

    # Install system dependencies for Airflow
    log "Installing Airflow system dependencies..."
    yum install -y \
        postgresql-devel \
        openssl-devel \
        libffi-devel \
        pkgconfig \
        mariadb-devel \
        freetds-devel \
        krb5-devel \
        cyrus-sasl-devel \
        openldap-devel

    # Clean up
    log "Cleaning yum cache..."
    yum clean all

    log "Prerequisites installed successfully via yum"
}

###############################################################################
# STEP 3: VERIFY PREREQUISITES
###############################################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! command -v python3 >/dev/null 2>&1; then
        error "Python3 verification failed - not found in PATH"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python verified: $python_version"

    # Verify pip3
    if ! command -v pip3 >/dev/null 2>&1; then
        error "pip3 verification failed - not found in PATH"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip3 verified: $pip_version"

    # Verify build tools
    if ! command -v gcc >/dev/null 2>&1; then
        error "gcc verification failed - not found in PATH"
        exit 1
    fi
    log "gcc verified: $(gcc --version | head -n1 | awk '{print $NF}')"

    if ! command -v make >/dev/null 2>&1; then
        error "make verification failed - not found in PATH"
        exit 1
    fi
    log "make verified: $(make --version | head -n1)"

    log "All prerequisites verified successfully"
}

###############################################################################
# STEP 4: CHECK EXISTING INSTALLATION
###############################################################################
check_existing_installation() {
    log "Checking for existing Apache Airflow installation..."

    # Try to import airflow and check version
    if python3 -c "import airflow" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import airflow; print(airflow.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "Apache Airflow ${TOOL_VERSION} is already installed"
            return 0
        else
            log "Apache Airflow is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Will proceed with installation to ensure correct version"
            return 1
        fi
    else
        log "Apache Airflow is not installed"
        return 1
    fi
}

###############################################################################
# STEP 5: INSTALL APACHE AIRFLOW
###############################################################################
install_tool() {
    log "Installing Apache Airflow ${TOOL_VERSION}..."

    # Upgrade pip, setuptools, and wheel to ensure compatibility
    log "Upgrading pip, setuptools, and wheel..."
    pip3 install --upgrade pip setuptools wheel --quiet

    # Set AIRFLOW_HOME if not set (prevents initialization during install)
    export AIRFLOW_HOME="${AIRFLOW_HOME:-/root/airflow}"

    # Install Apache Airflow with constraints to ensure compatible dependencies
    # Using constraints file for reproducible installation
    log "Installing apache-airflow==${TOOL_VERSION}..."

    # First, determine the Python version for the constraint URL
    local python_version
    python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    log "Using Python ${python_version} constraints"

    # Construct the correct constraints URL
    local constraints_url="https://raw.githubusercontent.com/apache/airflow/constraints-${TOOL_VERSION}/constraints-${python_version}.txt"

    # Check if constraints file exists, fallback to no constraints if not available
    if curl -fsSL --head "$constraints_url" >/dev/null 2>&1; then
        log "Using constraints from: $constraints_url"
        pip3 install "apache-airflow==${TOOL_VERSION}" \
            --constraint "$constraints_url" \
            --no-cache-dir \
            --quiet
    else
        log "Constraints file not available, installing without constraints"
        log "This may result in dependency conflicts, but will proceed"
        pip3 install "apache-airflow==${TOOL_VERSION}" \
            --no-cache-dir \
            --quiet
    fi

    log "Apache Airflow ${TOOL_VERSION} installation completed"
}

###############################################################################
# STEP 6: VALIDATE INSTALLATION
###############################################################################
validate() {
    log "Validating Apache Airflow installation..."

    # Check if airflow command exists
    if ! command -v airflow >/dev/null 2>&1; then
        error "Validation failed: 'airflow' command not found in PATH"
        error "Expected location: $(which airflow 2>&1 || echo 'not found')"
        exit 1
    fi

    log "Found airflow command at: $(which airflow)"

    # Run the validation command
    local installed_version
    if ! installed_version=$(python3 -c 'import airflow; print(airflow.__version__)' 2>&1); then
        error "Validation failed: Unable to import airflow module"
        error "Error output: $installed_version"
        exit 1
    fi

    log "Installed version: $installed_version"

    # Verify version matches expected
    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "Validation failed: Version mismatch"
        error "Expected: ${TOOL_VERSION}"
        error "Got: ${installed_version}"
        exit 1
    fi

    # Additional validation: check airflow CLI
    if airflow version 2>/dev/null | grep -q "$TOOL_VERSION"; then
        log "Airflow CLI version check passed"
    else
        log "Warning: Airflow CLI version check did not match exactly, but Python import succeeded"
    fi

    log "Validation successful: Apache Airflow ${TOOL_VERSION} is correctly installed"
    return 0
}

###############################################################################
# MAIN EXECUTION
###############################################################################
main() {
    log "Starting Apache Airflow ${TOOL_VERSION} installation..."
    log "Installation method: pip (PyPI package)"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Tool already installed with correct version, validating..."
        validate
        log "Installation verification completed - no changes needed"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "Apache Airflow ${TOOL_VERSION} installation completed successfully"
    log "=========================================="
    log ""
    log "Quick start commands:"
    log "  airflow version                    # Show version"
    log "  airflow db init                    # Initialize database"
    log "  airflow standalone                 # Run standalone mode"
    log ""
    log "Documentation: https://airflow.apache.org/docs/apache-airflow/${TOOL_VERSION}/"
}

# Run main function
main "$@"
