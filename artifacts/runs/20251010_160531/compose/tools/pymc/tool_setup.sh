#!/usr/bin/env bash
################################################################################
# PyMC v5.25.1 Installation Script
#
# This script installs PyMC (Bayesian Modeling and Probabilistic Programming)
# following the Solutions Team installation standards.
#
# Prerequisites: Python 3.10+, pip3
# Installation Method: pip
# Validation: python3 -c "import pymc; print(pymc.__version__)"
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Initialize variables safely under set -euo pipefail
tmp_dir="${tmp_dir:-$(mktemp -d)}"
trap 'rm -rf "$tmp_dir"' EXIT

readonly TOOL_NAME="pymc"
readonly TOOL_VERSION="5.25.1"
readonly PYPI_PACKAGE="pymc"
readonly MIN_PYTHON_VERSION="3.10"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        log_warn "Python 3 not found"
        missing_prereqs=1
    else
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python $python_version"

        # Check minimum Python version
        if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (${MIN_PYTHON_VERSION%%.*}, ${MIN_PYTHON_VERSION##*.}) else 1)" 2>/dev/null; then
            log_error "Python ${MIN_PYTHON_VERSION}+ required, found $python_version"
            log_error "Please upgrade Python to at least version ${MIN_PYTHON_VERSION}"
            return 1
        fi
    fi

    # Check for pip3
    if ! command -v pip3 &> /dev/null; then
        log_warn "pip3 not found"
        missing_prereqs=1
    else
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip $pip_version"
    fi

    # Check for build essentials (often needed for Python packages with C extensions)
    if ! command -v gcc &> /dev/null; then
        log_warn "gcc not found (may be needed for some Python dependencies)"
        missing_prereqs=1
    else
        log "Found gcc $(gcc --version | head -1 | awk '{print $NF}')"
    fi

    if [ $missing_prereqs -eq 1 ]; then
        log "Some prerequisites are missing and need to be installed"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Check if we should skip prerequisites
    if [ "${RESPECT_SHARED_DEPS:-0}" = "1" ]; then
        log "RESPECT_SHARED_DEPS=1, skipping prerequisite installation"
        return 0
    fi

    # Update package lists
    log "Updating package lists..."
    if ! apt-get update -qq; then
        log_error "Failed to update package lists"
        log_error "Remediation: Check network connectivity and apt sources configuration"
        return 1
    fi

    # Install Python 3 and pip
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python 3 and pip..."
        if ! apt-get install -y -qq python3 python3-pip python3-venv python3-dev; then
            log_error "Failed to install Python prerequisites"
            log_error "Remediation: Ensure apt repositories are configured correctly and you have sufficient permissions"
            return 1
        fi
    fi

    # Install build essentials (for Python packages with C extensions)
    if ! command -v gcc &> /dev/null; then
        log "Installing build essentials..."
        if ! apt-get install -y -qq build-essential; then
            log_warn "Failed to install build-essential (may cause issues with some dependencies)"
        fi
    fi

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version &> /dev/null; then
        log_error "Python 3 verification failed"
        log_error "Remediation: Reinstall Python 3 or check PATH configuration"
        return 1
    fi

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        log_error "pip3 verification failed"
        log_error "Remediation: Reinstall python3-pip or check PATH configuration"
        return 1
    fi

    # Verify Python version meets minimum requirement
    if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (${MIN_PYTHON_VERSION%%.*}, ${MIN_PYTHON_VERSION##*.}) else 1)" 2>/dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log_error "Python version check failed: found $python_version, need ${MIN_PYTHON_VERSION}+"
        log_error "Remediation: Upgrade Python to version ${MIN_PYTHON_VERSION} or higher"
        return 1
    fi

    log "All prerequisites verified successfully"
    return 0
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import ${PYPI_PACKAGE}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${PYPI_PACKAGE}; print(${PYPI_PACKAGE}.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} v${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} version $installed_version found (expected: ${TOOL_VERSION})"
            log "Will proceed with installation of v${TOOL_VERSION}"
            return 1
        fi
    fi

    log "${TOOL_NAME} is not installed"
    return 1
}

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Install PyMC with pinned version
    log "Running: pip3 install ${PYPI_PACKAGE}==${TOOL_VERSION}"
    if ! pip3 install --no-cache-dir "${PYPI_PACKAGE}==${TOOL_VERSION}"; then
        log_error "Failed to install ${TOOL_NAME} v${TOOL_VERSION}"
        log_error "Remediation: Check network connectivity and PyPI availability"
        log_error "Alternatively, check if Python version is compatible (requires Python ${MIN_PYTHON_VERSION}+)"
        return 1
    fi

    log "${TOOL_NAME} v${TOOL_VERSION} installed successfully"

    # Self-healing: Check for missing shared libraries
    log "Performing runtime linkage verification..."

    # PyMC is a pure Python library, but its dependencies (especially pytensor, scipy, numpy)
    # may have compiled components. Check if we can import key dependencies.
    local missing_deps=()

    for dep in numpy scipy pytensor; do
        if ! python3 -c "import $dep" 2>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Some dependencies failed to import: ${missing_deps[*]}"
        log "Attempting to install missing system libraries..."

        # Common system libraries needed for scientific Python packages
        local sys_libs=("libopenblas-dev" "liblapack-dev" "gfortran")

        for lib in "${sys_libs[@]}"; do
            if ! dpkg -l | grep -q "^ii  $lib"; then
                log "Installing $lib..."
                apt-get install -y -qq "$lib" 2>/dev/null || log_warn "Could not install $lib"
            fi
        done

        # Run ldconfig to update library cache
        ldconfig 2>/dev/null || true

        # Re-check dependencies
        local still_missing=()
        for dep in "${missing_deps[@]}"; do
            if ! python3 -c "import $dep" 2>/dev/null; then
                still_missing+=("$dep")
            fi
        done

        if [ ${#still_missing[@]} -gt 0 ]; then
            log_warn "Some dependencies still cannot be imported: ${still_missing[*]}"
            log_warn "This may not affect PyMC functionality, but validation may fail"
        fi
    fi
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if PyMC can be imported
    if ! python3 -c "import ${PYPI_PACKAGE}" 2>/dev/null; then
        log_error "${TOOL_NAME} validation failed: cannot import module"
        log_error "Remediation: Reinstall ${TOOL_NAME} or check Python environment"
        return 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import ${PYPI_PACKAGE}; print(${PYPI_PACKAGE}.__version__)" 2>/dev/null)

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        log_error "Version mismatch: expected ${TOOL_VERSION}, found ${installed_version}"
        return 1
    fi

    log "${GREEN}✓${NC} ${TOOL_NAME} v${installed_version} validated successfully"

    # Display validation command for reference
    log "Validation command: python3 -c \"import ${PYPI_PACKAGE}; print(${PYPI_PACKAGE}.__version__)\""

    return 0
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."
    log "=================================================="

    # Parse command-line arguments
    for arg in "$@"; do
        case $arg in
            --skip-prereqs)
                export RESPECT_SHARED_DEPS=1
                shift
                ;;
        esac
    done

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "=================================================="
        log "${GREEN}Installation completed successfully (already installed)${NC}"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=================================================="
    log "${GREEN}Installation completed successfully${NC}"
}

# Run main function
main "$@"
