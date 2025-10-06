#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Pandera v0.26.1 Installation Script
# ============================================================================
# Description: Installs pandera (Python data validation library) v0.26.1
# Prerequisites: Python 3, pip
# Validation: python -c 'import pandera; print(pandera.__version__)'
# ============================================================================

readonly TOOL_NAME="pandera"
readonly TOOL_VERSION="0.26.1"
readonly PACKAGE_NAME="pandera"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# ============================================================================
# Prerequisite Management
# ============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check pip
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: $pip_version"
    else
        log "pip3 not found"
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
    if ! command -v python3 >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1; then
        log "Updating apt package lists..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        # Install Python 3 and pip if not present
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            apt-get install -y python3 >/dev/null 2>&1
        fi

        if ! command -v pip3 >/dev/null 2>&1; then
            log "Installing pip..."
            apt-get install -y python3-pip >/dev/null 2>&1
        fi

        # Clean up
        log "Cleaning up apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        error "Remediation: Ensure Python 3 is installed correctly"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1)
    log "Verified: $python_version"

    # Verify pip
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        error "Remediation: Ensure pip3 is installed correctly"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | head -n1)
    log "Verified: $pip_version"

    log "All prerequisites verified successfully"
}

# ============================================================================
# Tool Installation
# ============================================================================

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import ${PACKAGE_NAME}; print(${PACKAGE_NAME}.__version__)" 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$TOOL_VERSION" ]; then
            log "${TOOL_NAME} v${TOOL_VERSION} is already installed"
            return 0
        else
            log "${TOOL_NAME} is installed but version is ${installed_version}, expected ${TOOL_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Install pandera with exact version using pip
    log "Running: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"

    if pip3 install "${PACKAGE_NAME}==${TOOL_VERSION}" --no-cache-dir; then
        log "${TOOL_NAME} installation completed"
    else
        error "Failed to install ${TOOL_NAME} v${TOOL_VERSION}"
        error "Remediation: Check pip availability and network connectivity"
        error "Try manually: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
        exit 1
    fi
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if package can be imported
    if ! python3 -c "import ${PACKAGE_NAME}" 2>/dev/null; then
        error "${TOOL_NAME} validation failed: cannot import module"
        error "Remediation: Reinstall ${TOOL_NAME} with: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import ${PACKAGE_NAME}; print(${PACKAGE_NAME}.__version__)" 2>/dev/null)

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        error "${TOOL_NAME} validation failed: version mismatch"
        error "Expected: ${TOOL_VERSION}"
        error "Found: ${installed_version}"
        error "Remediation: Reinstall with exact version: pip3 install ${PACKAGE_NAME}==${TOOL_VERSION}"
        exit 1
    fi

    log "Validation successful: ${TOOL_NAME} v${installed_version}"

    # Run the exact validation command specified
    log "Running validation command..."
    python3 -c 'import pandera; print(pandera.__version__)'

    return 0
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation completed successfully (already installed)"
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
