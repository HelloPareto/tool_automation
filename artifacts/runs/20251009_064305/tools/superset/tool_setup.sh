#!/bin/bash
set -euo pipefail

#######################################
# Apache Superset Installation Script
# Version: superset-helm-chart-0.15.1 (Apache Superset 5.0.0)
# Description: Apache Superset is a Data Visualization and Data Exploration Platform
#######################################

# Configuration
readonly SUPERSET_VERSION="5.0.0"
readonly PYTHON_MIN_VERSION="3.10"
readonly LOG_PREFIX="[Superset Install]"

# Logging function
log() {
    echo "${LOG_PREFIX} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

error() {
    echo "${LOG_PREFIX} ERROR $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

#######################################
# Check if prerequisites are installed
# Returns: 0 if all present, 1 if any missing
#######################################
check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=0

    # Check Python 3.10+
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        local major minor
        major=$(echo "$python_version" | cut -d. -f1)
        minor=$(echo "$python_version" | cut -d. -f2)

        if [[ "$major" -ge 3 ]] && [[ "$minor" -ge 10 ]]; then
            log "Found Python $python_version"
        else
            log "Python $python_version found, but version $PYTHON_MIN_VERSION or higher required"
            all_present=1
        fi
    else
        log "Python 3 not found"
        all_present=1
    fi

    # Check pip
    if command -v pip3 >/dev/null 2>&1; then
        log "Found pip3 $(pip3 --version | awk '{print $2}')"
    else
        log "pip3 not found"
        all_present=1
    fi

    # Check for build essentials (gcc)
    if command -v gcc >/dev/null 2>&1; then
        log "Found gcc $(gcc --version | head -n1 | awk '{print $NF}')"
    else
        log "gcc not found"
        all_present=1
    fi

    # Check for required system packages
    local missing_packages=()

    # These are common packages needed for Python package compilation
    for pkg in pkg-config libssl-dev libffi-dev; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log "Missing system packages: ${missing_packages[*]}"
        all_present=1
    else
        log "All required system packages present"
    fi

    return $all_present
}

#######################################
# Install prerequisites
#######################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package list
    log "Updating package list..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update

    # Install Python 3.10+ and pip if not present
    if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
        log "Installing Python 3.10..."
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:deadsnakes/ppa
        apt-get update
        apt-get install -y python3.10 python3.10-dev python3.10-venv python3-pip

        # Update alternatives to use Python 3.10
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
    fi

    # Install pip if not present
    if ! command -v pip3 >/dev/null 2>&1; then
        log "Installing pip..."
        apt-get install -y python3-pip
    fi

    # Upgrade pip, setuptools, wheel
    log "Upgrading pip, setuptools, and wheel..."
    pip3 install --upgrade pip setuptools wheel

    # Install build essentials and system dependencies
    log "Installing build essentials and system dependencies..."
    apt-get install -y \
        build-essential \
        pkg-config \
        libssl-dev \
        libffi-dev \
        libsasl2-dev \
        libldap2-dev \
        libpq-dev \
        default-libmysqlclient-dev \
        libecpg-dev \
        curl \
        wget

    # Clean up
    log "Cleaning package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

#######################################
# Verify prerequisites work correctly
#######################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! python3 --version; then
        error "Python 3 verification failed"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    local major minor
    major=$(echo "$python_version" | cut -d. -f1)
    minor=$(echo "$python_version" | cut -d. -f2)

    if [[ "$major" -lt 3 ]] || [[ "$minor" -lt 10 ]]; then
        error "Python version $python_version is less than required $PYTHON_MIN_VERSION"
        exit 1
    fi

    log "Python version: $python_version ✓"

    # Verify pip
    if ! pip3 --version; then
        error "pip3 verification failed"
        exit 1
    fi
    log "pip3 version: $(pip3 --version | awk '{print $2}') ✓"

    # Verify gcc
    if ! gcc --version >/dev/null 2>&1; then
        error "gcc verification failed"
        exit 1
    fi
    log "gcc version: $(gcc --version | head -n1 | awk '{print $NF}') ✓"

    log "All prerequisites verified successfully"
}

#######################################
# Check if tool is already installed (idempotency)
# Returns: 0 if installed, 1 if not
#######################################
check_existing_installation() {
    log "Checking for existing Superset installation..."

    if command -v superset >/dev/null 2>&1; then
        # Check installed version via pip
        local installed_version
        installed_version=$(pip3 show apache-superset 2>/dev/null | grep "^Version:" | awk '{print $2}')

        if [[ -n "$installed_version" ]]; then
            if [[ "$installed_version" == "$SUPERSET_VERSION" ]]; then
                log "Superset $SUPERSET_VERSION is already installed"
                return 0
            else
                log "Found Superset version $installed_version, but need $SUPERSET_VERSION"
                return 1
            fi
        else
            log "Could not determine Superset version"
            return 1
        fi
    else
        log "Superset is not installed"
        return 1
    fi
}

#######################################
# Install Apache Superset
#######################################
install_tool() {
    log "Installing Apache Superset ${SUPERSET_VERSION}..."

    # Install apache-superset with pinned version
    log "Installing apache-superset==${SUPERSET_VERSION} via pip..."

    # Set environment variables for compilation
    export CRYPTOGRAPHY_DONT_BUILD_RUST=1

    # Remove conflicting distutils package if present
    if python3 -c "import blinker" 2>/dev/null; then
        log "Removing conflicting blinker package..."
        pip3 install --ignore-installed blinker
    fi

    # Install with no cache to ensure clean installation
    pip3 install --no-cache-dir --ignore-installed "apache-superset==${SUPERSET_VERSION}"

    log "Apache Superset installed successfully"
}

#######################################
# Validate installation
#######################################
validate() {
    log "Validating Superset installation..."

    # Check if superset command exists
    if ! command -v superset >/dev/null 2>&1; then
        error "superset command not found in PATH"
        error "Installation validation failed"
        exit 1
    fi

    # Superset version command requires Flask app context
    # Use pip show instead for validation
    log "Checking installed version with: pip show apache-superset"
    local pip_output
    if pip_output=$(pip3 show apache-superset 2>&1); then
        local installed_version
        installed_version=$(echo "$pip_output" | grep "^Version:" | awk '{print $2}')

        log "Installed version: $installed_version"

        if [[ "$installed_version" == "$SUPERSET_VERSION" ]]; then
            log "✓ Validation successful - Apache Superset $installed_version is correctly installed"

            # Verify superset command is accessible
            if superset --help >/dev/null 2>&1; then
                log "✓ superset command is working"
                return 0
            else
                error "superset command exists but not functioning properly"
                exit 1
            fi
        else
            error "Version mismatch: expected $SUPERSET_VERSION, got $installed_version"
            exit 1
        fi
    else
        error "Failed to query installed package"
        error "Output: $pip_output"
        exit 1
    fi
}

#######################################
# Main installation flow
#######################################
main() {
    log "Starting Apache Superset ${SUPERSET_VERSION} installation..."
    log "This corresponds to superset-helm-chart-0.15.1"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites already present"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Superset is already installed with correct version"
        validate
        log "Installation completed (idempotent - no changes made)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# Run main function
main "$@"
