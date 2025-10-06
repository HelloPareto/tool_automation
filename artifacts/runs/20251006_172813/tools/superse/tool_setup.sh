#!/bin/bash
set -euo pipefail

# Apache Superset Installation Script
# Tool: superse (apache-superset)
# Version: 5.0.0
# Package Manager: pip
# Validation: python -c 'import apache_superset; print(apache_superset.__version__)'

readonly TOOL_NAME="apache-superset"
readonly TOOL_VERSION="5.0.0"
readonly VALIDATE_CMD="python3 -c 'import superset; print(superset.__version__)'"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check Python 3
    if command -v python3 &> /dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"

        # Check if Python version is >= 3.8
        local major minor
        major=$(echo "$python_version" | cut -d. -f1)
        minor=$(echo "$python_version" | cut -d. -f2)
        if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 8 ]; }; then
            error "Python 3.8+ required, found $python_version"
            all_present=false
        fi
    else
        log "Python3 not found"
        all_present=false
    fi

    # Check pip
    if command -v pip3 &> /dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: $pip_version"
    else
        log "pip3 not found"
        all_present=false
    fi

    # Check build-essential (gcc)
    if command -v gcc &> /dev/null; then
        local gcc_version
        gcc_version=$(gcc --version 2>&1 | head -1)
        log "Found gcc: $gcc_version"
    else
        log "gcc not found (build-essential needed)"
        all_present=false
    fi

    # Check make
    if command -v make &> /dev/null; then
        local make_version
        make_version=$(make --version 2>&1 | head -1)
        log "Found make: $make_version"
    else
        log "make not found (build-essential needed)"
        all_present=false
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    if ! apt-get update; then
        error "Failed to update apt package lists"
        error "Remediation: Check internet connection and apt sources configuration"
        exit 1
    fi

    # Install Python 3 and pip if missing
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python 3 and pip..."
        if ! apt-get install -y python3 python3-pip python3-venv python3-dev; then
            error "Failed to install Python 3 and pip"
            error "Remediation: Check apt repository configuration and disk space"
            exit 1
        fi
    fi

    # Install build-essential if missing
    if ! command -v gcc &> /dev/null || ! command -v make &> /dev/null; then
        log "Installing build-essential..."
        if ! apt-get install -y build-essential; then
            error "Failed to install build-essential"
            error "Remediation: Check apt repository configuration and disk space"
            exit 1
        fi
    fi

    # Install additional system dependencies required by Superset
    log "Installing additional system dependencies..."
    if ! apt-get install -y \
        libssl-dev \
        libffi-dev \
        libsasl2-dev \
        libldap2-dev \
        libpq-dev \
        pkg-config; then
        error "Failed to install system dependencies"
        error "Remediation: Check apt repository configuration and disk space"
        exit 1
    fi

    # Clean up apt cache
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        error "Python 3 verification failed"
        error "Remediation: Reinstall Python 3 with apt-get install -y python3"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1)
    log "Python verification successful: $python_version"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        error "Remediation: Reinstall pip with apt-get install -y python3-pip"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1)
    log "pip verification successful: $pip_version"

    # Verify gcc
    if ! gcc --version &> /dev/null; then
        error "gcc verification failed"
        error "Remediation: Reinstall build-essential with apt-get install -y build-essential"
        exit 1
    fi
    log "gcc verification successful"

    # Verify make
    if ! make --version &> /dev/null; then
        error "make verification failed"
        error "Remediation: Reinstall build-essential with apt-get install -y build-essential"
        exit 1
    fi
    log "make verification successful"

    log "All prerequisites verified successfully"
}

# Check if tool is already installed (idempotency)
check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import superset" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import superset; print(superset.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} version ${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            log "Proceeding with installation to ensure correct version"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

# Install the tool
install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Upgrade pip, setuptools, and wheel to latest versions
    log "Upgrading pip, setuptools, and wheel..."
    if ! pip3 install --upgrade pip setuptools wheel; then
        error "Failed to upgrade pip, setuptools, and wheel"
        error "Remediation: Check internet connection and PyPI availability"
        exit 1
    fi

    # Install apache-superset with pinned version
    log "Installing apache-superset==${TOOL_VERSION}..."
    # Use --ignore-installed for system packages that may conflict (common in Ubuntu)
    if ! pip3 install --ignore-installed "apache-superset==${TOOL_VERSION}"; then
        error "Failed to install ${TOOL_NAME} version ${TOOL_VERSION}"
        error "Remediation: Check internet connection, PyPI availability, and system dependencies"
        error "You may need additional system packages. Check Superset documentation."
        exit 1
    fi

    log "${TOOL_NAME} ${TOOL_VERSION} installation completed"
}

# Validate the installation
validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if superset module can be imported
    if ! python3 -c "import superset" 2>/dev/null; then
        error "Validation failed: Cannot import superset module"
        error "Remediation: Reinstall with pip3 install apache-superset==${TOOL_VERSION}"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import superset; print(superset.__version__)" 2>/dev/null || echo "unknown")

    if [ "$installed_version" = "$TOOL_VERSION" ]; then
        log "Validation successful: ${TOOL_NAME} version ${installed_version}"
        return 0
    else
        error "Validation failed: Expected version ${TOOL_VERSION}, but found ${installed_version}"
        error "Remediation: Reinstall with pip3 install --force-reinstall apache-superset==${TOOL_VERSION}"
        exit 1
    fi
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation verified - ${TOOL_NAME} ${TOOL_VERSION} is ready"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
    log "${TOOL_NAME} ${TOOL_VERSION} is now available"
}

# Run main function
main "$@"
