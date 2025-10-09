#!/bin/bash
set -euo pipefail

###########################################
# sktime v0.39.0 Installation Script
###########################################
# Description: Install sktime v0.39.0 - A unified framework for machine learning with time series
# Prerequisites: Python 3.10+ and pip
# Installation Method: pip install from GitHub
# Validation: Python version check
###########################################

TOOL_NAME="sktime"
TOOL_VERSION="v0.39.0"
# shellcheck disable=SC2034
REQUIRED_PYTHON_VERSION="3.10"  # Used for documentation
GITHUB_REPO="https://github.com/sktime/sktime.git"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

###########################################
# Prerequisites Functions
###########################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"

        # Check if version meets minimum requirement
        local major minor
        major=$(echo "$python_version" | cut -d. -f1)
        minor=$(echo "$python_version" | cut -d. -f2)

        if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 10 ]]; then
            log "Python version $python_version is too old. Minimum required: 3.10"
            all_present=false
        fi
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: $pip_version"
    else
        log "pip3 not found"
        all_present=false
    fi

    # Check for git (needed for pip install from GitHub)
    if command -v git >/dev/null 2>&1; then
        local git_version
        git_version=$(git --version 2>&1 | awk '{print $3}')
        log "Found git: $git_version"
    else
        log "git not found"
        all_present=false
    fi

    if $all_present; then
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
    if command -v apt-get >/dev/null 2>&1; then
        log "Using apt-get package manager"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        # Install Python 3.10+ if not present or too old
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            apt-get install -y -qq python3 python3-pip python3-venv
        else
            local python_version
            python_version=$(python3 --version 2>&1 | awk '{print $2}')
            local major minor
            major=$(echo "$python_version" | cut -d. -f1)
            minor=$(echo "$python_version" | cut -d. -f2)

            if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 10 ]]; then
                log "Upgrading Python to 3.10+..."
                apt-get install -y -qq python3 python3-pip python3-venv
            fi
        fi

        # Install pip if not present
        if ! command -v pip3 >/dev/null 2>&1; then
            log "Installing pip3..."
            apt-get install -y -qq python3-pip
        fi

        # Install git if not present
        if ! command -v git >/dev/null 2>&1; then
            log "Installing git..."
            apt-get install -y -qq git
        fi

        # Install build dependencies that sktime may need
        log "Installing build dependencies..."
        apt-get install -y -qq \
            build-essential \
            python3-dev \
            libgomp1

        # Clean up
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum >/dev/null 2>&1; then
        log "Using yum package manager"

        # Install Python 3.10+ if not present
        if ! command -v python3 >/dev/null 2>&1; then
            log "Installing Python 3..."
            yum install -y python3 python3-pip
        fi

        # Install git if not present
        if ! command -v git >/dev/null 2>&1; then
            log "Installing git..."
            yum install -y git
        fi

        # Install build dependencies
        log "Installing build dependencies..."
        yum install -y gcc gcc-c++ python3-devel

        yum clean all

    else
        error "No supported package manager found (apt-get or yum)"
        error "Please install Python 3.10+, pip, and git manually"
        exit 1
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! python3 --version >/dev/null 2>&1; then
        error "Python 3 verification failed"
        exit 1
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python verification successful: $python_version"

    # Verify pip
    if ! pip3 --version >/dev/null 2>&1; then
        error "pip3 verification failed"
        exit 1
    fi
    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip verification successful: $pip_version"

    # Verify git
    if ! git --version >/dev/null 2>&1; then
        error "git verification failed"
        exit 1
    fi
    local git_version
    git_version=$(git --version 2>&1 | awk '{print $3}')
    log "git verification successful: $git_version"

    log "All prerequisites verified successfully"
}

###########################################
# Installation Functions
###########################################

check_existing_installation() {
    log "Checking if $TOOL_NAME $TOOL_VERSION is already installed..."

    # Check if sktime is installed and get version
    if python3 -c "import sktime" 2>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import sktime; print(sktime.__version__)" 2>/dev/null || echo "unknown")

        if [[ "$installed_version" == "0.39.0" ]]; then
            log "$TOOL_NAME version $installed_version is already installed"
            return 0
        else
            log "$TOOL_NAME version $installed_version is installed, but we need 0.39.0"
            log "Will reinstall the correct version..."
            return 1
        fi
    else
        log "$TOOL_NAME is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing $TOOL_NAME $TOOL_VERSION..."

    # Upgrade pip, setuptools, and wheel first
    log "Upgrading pip, setuptools, and wheel..."
    pip3 install --upgrade pip setuptools wheel --quiet

    # Install sktime v0.39.0 from GitHub
    log "Installing sktime v0.39.0 from GitHub..."
    pip3 install "git+${GITHUB_REPO}@${TOOL_VERSION}" --quiet

    log "$TOOL_NAME installation completed"
}

validate() {
    log "Validating $TOOL_NAME installation..."

    # Check if sktime can be imported
    if ! python3 -c "import sktime" 2>/dev/null; then
        error "Failed to import sktime. Installation may have failed."
        error "Troubleshooting steps:"
        error "  1. Check if Python 3.10+ is installed: python3 --version"
        error "  2. Check if pip is working: pip3 --version"
        error "  3. Try reinstalling: pip3 install git+https://github.com/sktime/sktime.git@v0.39.0"
        exit 1
    fi

    # Get installed version
    local installed_version
    installed_version=$(python3 -c "import sktime; print(sktime.__version__)" 2>/dev/null || echo "unknown")

    log "Installed version: $installed_version"

    # Validate version matches expected
    if [[ "$installed_version" == "0.39.0" ]]; then
        log "✓ Version validation successful: $installed_version matches expected 0.39.0"
    else
        error "Version mismatch: expected 0.39.0, got $installed_version"
        error "Note: The validate command 'sktime --version' does not work because"
        error "sktime is a Python library, not a CLI tool."
        error "Use: python3 -c 'import sktime; print(sktime.__version__)'"
        exit 1
    fi

    # Test basic functionality
    log "Testing basic sktime functionality..."
    if python3 -c "from sktime.forecasting.base import ForecastingHorizon; print('Import test successful')" 2>/dev/null; then
        log "✓ Basic functionality test passed"
    else
        error "Basic functionality test failed"
        exit 1
    fi

    log "✓ Validation completed successfully"
    log ""
    log "NOTE: The provided validation command 'sktime --version' does not work"
    log "because sktime is a Python library without a CLI interface."
    log ""
    log "To check the version, use:"
    log "  python3 -c 'import sktime; print(sktime.__version__)'"
    log ""
    log "Expected output: 0.39.0"
}

###########################################
# Main Installation Flow
###########################################

main() {
    log "=========================================="
    log "Starting $TOOL_NAME $TOOL_VERSION installation..."
    log "=========================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "$TOOL_NAME $TOOL_VERSION is already installed and validated"
        validate
        log "=========================================="
        log "Installation script completed (idempotent - no changes made)"
        log "=========================================="
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "Installation completed successfully"
    log "=========================================="
    log ""
    log "To use sktime in Python:"
    log "  python3 -c 'import sktime; print(sktime.__version__)'"
}

# Execute main function
main
