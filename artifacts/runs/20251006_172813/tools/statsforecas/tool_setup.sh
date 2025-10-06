#!/usr/bin/env bash

################################################################################
# statsforecast Installation Script
# Version: 2.0.2
# Package Manager: pip
# Description: Installs statsforecast Python library for statistical forecasting
################################################################################

set -euo pipefail

# Global variables
readonly TOOL_NAME="statsforecast"
readonly TOOL_VERSION="2.0.2"
readonly VALIDATE_CMD="python3 -c 'import statsforecast; print(statsforecast.__version__)'"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking for required prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python 3: version ${python_version}"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip3: version ${pip_version}"
    else
        log "pip3 not found"
        all_present=false
    fi

    # Check for build tools (gcc, make) - required for native extensions
    if command -v gcc >/dev/null 2>&1; then
        log "Found gcc: $(gcc --version | head -n1)"
    else
        log "gcc not found"
        all_present=false
    fi

    if command -v make >/dev/null 2>&1; then
        log "Found make: $(make --version | head -n1)"
    else
        log "make not found"
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

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    if ! apt-get update; then
        error "Failed to update package lists"
        exit 1
    fi

    # Install Python 3 and pip if not present
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Installing Python 3 and pip..."
        if ! apt-get install -y python3 python3-pip python3-venv python3-dev; then
            error "Failed to install Python 3 and pip"
            error "Remediation: Ensure apt repositories are configured correctly and retry"
            exit 1
        fi
    fi

    # Install build tools if not present
    if ! command -v gcc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
        log "Installing build-essential (gcc, make, etc.)..."
        if ! apt-get install -y build-essential; then
            error "Failed to install build-essential"
            error "Remediation: Ensure apt repositories are configured correctly and retry"
            exit 1
        fi
    fi

    # Clean up
    log "Cleaning up apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        error "Remediation: Reinstall Python 3 with 'apt-get install -y python3'"
        exit 1
    fi

    # Verify pip3
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        error "Remediation: Reinstall pip with 'apt-get install -y python3-pip'"
        exit 1
    fi

    # Verify gcc
    if ! gcc --version >/dev/null 2>&1; then
        error "gcc verification failed"
        error "Remediation: Reinstall build tools with 'apt-get install -y build-essential'"
        exit 1
    fi

    # Verify make
    if ! make --version >/dev/null 2>&1; then
        error "make verification failed"
        error "Remediation: Reinstall build tools with 'apt-get install -y build-essential'"
        exit 1
    fi

    log "All prerequisites verified successfully"
    log "Python version: $(python3 --version 2>&1)"
    log "pip version: $(pip3 --version 2>&1)"
    log "gcc version: $(gcc --version | head -n1)"
    log "make version: $(make --version | head -n1)"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Try to import the module and check version
    if python3 -c "import statsforecast._lib; print(statsforecast._lib.__version__)" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(python3 -c "import statsforecast._lib; print(statsforecast._lib.__version__)" 2>/dev/null)

        if [ "${installed_version}" = "${TOOL_VERSION}" ]; then
            log "${TOOL_NAME} version ${installed_version} is already installed"
            return 0
        else
            log "${TOOL_NAME} version ${installed_version} is installed, but version ${TOOL_VERSION} is required"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} version ${TOOL_VERSION}..."

    # Upgrade pip to latest version to avoid compatibility issues
    log "Upgrading pip to latest version..."
    if ! pip3 install --upgrade pip; then
        error "Failed to upgrade pip"
        error "Remediation: Check internet connectivity and pip configuration"
        exit 1
    fi

    # Install statsforecast with pinned version
    log "Installing ${TOOL_NAME}==${TOOL_VERSION}..."
    if ! pip3 install --no-cache-dir "statsforecast==${TOOL_VERSION}"; then
        error "Failed to install ${TOOL_NAME}"
        error "Remediation: Check internet connectivity, PyPI availability, and build dependencies"
        exit 1
    fi

    log "${TOOL_NAME} installed successfully"
}

################################################################################
# Validation Function
################################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Run the validation command
    local validation_output
    if validation_output=$(eval "${VALIDATE_CMD}" 2>&1); then
        log "Validation successful: ${TOOL_NAME} version ${validation_output}"

        # Verify the version matches expected
        if [ "${validation_output}" = "${TOOL_VERSION}" ]; then
            log "Version verification passed: ${validation_output} matches expected ${TOOL_VERSION}"
            return 0
        else
            error "Version mismatch: expected ${TOOL_VERSION}, got ${validation_output}"
            return 1
        fi
    else
        error "Validation failed: ${validation_output}"
        error "Remediation: Reinstall ${TOOL_NAME} or check for missing dependencies"
        exit 1
    fi
}

################################################################################
# Main Function
################################################################################

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
        log "Installation already complete and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# Execute main function
main "$@"
