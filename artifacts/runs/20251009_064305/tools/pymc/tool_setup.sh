#!/usr/bin/env bash
#   Copyright 2025 - Solutions Team
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

set -euo pipefail

# =============================================================================
# PyMC v5.25.1 Installation Script
# =============================================================================
# Description: Installs PyMC v5.25.1 - Bayesian Modeling and Probabilistic
#              Programming in Python
# Tool: pymc
# Version: v5.25.1
# Installation Method: pip
# Prerequisites: Python 3.10+, pip
# =============================================================================

# Configuration
readonly TOOL_NAME="pymc"
readonly TOOL_VERSION="5.25.1"
readonly PYTHON_MIN_VERSION="3.10"
readonly PACKAGE_NAME="pymc"

# Colors for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

# =============================================================================
# Prerequisite Detection
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Python 3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: ${python_version}"

        # Verify Python version is >= 3.10
        local major minor
        major=$(echo "${python_version}" | cut -d. -f1)
        minor=$(echo "${python_version}" | cut -d. -f2)

        if [[ ${major} -lt 3 ]] || [[ ${major} -eq 3 && ${minor} -lt 10 ]]; then
            log_warn "Python ${python_version} found, but Python ${PYTHON_MIN_VERSION}+ is required"
            all_present=false
        fi
    else
        log_warn "Python 3 not found"
        all_present=false
    fi

    # Check for pip
    if command -v pip3 >/dev/null 2>&1; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: ${pip_version}"
    else
        log_warn "pip3 not found"
        all_present=false
    fi

    if [[ "${all_present}" == "true" ]]; then
        log "All prerequisites are present"
        return 0
    else
        log_warn "Some prerequisites are missing"
        return 1
    fi
}

# =============================================================================
# Prerequisite Installation
# =============================================================================

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        install_prerequisites_apt
    elif command -v yum >/dev/null 2>&1; then
        install_prerequisites_yum
    else
        log_error "No supported package manager found (apt-get or yum)"
        log_error "Please install Python ${PYTHON_MIN_VERSION}+ and pip manually"
        exit 1
    fi
}

install_prerequisites_apt() {
    log "Using apt-get package manager..."

    export DEBIAN_FRONTEND=noninteractive

    log "Updating package lists..."
    apt-get update -qq

    log "Installing Python 3 and pip..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential

    log "Cleaning up apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully via apt-get"
}

install_prerequisites_yum() {
    log "Using yum package manager..."

    log "Installing Python 3 and pip..."
    yum install -y -q \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        gcc-c++ \
        make

    log "Cleaning up yum cache..."
    yum clean all

    log "Prerequisites installed successfully via yum"
}

# =============================================================================
# Prerequisite Verification
# =============================================================================

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 installation failed - command not found"
        exit 1
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Python version verified: ${python_version}"

    # Verify Python version meets minimum requirement
    local major minor
    major=$(echo "${python_version}" | cut -d. -f1)
    minor=$(echo "${python_version}" | cut -d. -f2)

    if [[ ${major} -lt 3 ]] || [[ ${major} -eq 3 && ${minor} -lt 10 ]]; then
        log_error "Python version ${python_version} does not meet minimum requirement of ${PYTHON_MIN_VERSION}"
        exit 1
    fi

    # Verify pip
    if ! command -v pip3 >/dev/null 2>&1; then
        log_error "pip3 installation failed - command not found"
        exit 1
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "pip version verified: ${pip_version}"

    log "All prerequisites verified successfully"
}

# =============================================================================
# Check Existing Installation
# =============================================================================

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if pymc is already installed with correct version
    if python3 -c "import pymc; print(pymc.__version__)" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null)

        if [[ "${installed_version}" == "${TOOL_VERSION}" ]]; then
            log "${TOOL_NAME} v${TOOL_VERSION} is already installed"
            return 0
        else
            log_warn "${TOOL_NAME} v${installed_version} is installed, but v${TOOL_VERSION} is required"
            log "Will proceed with installation of v${TOOL_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not currently installed"
        return 1
    fi
}

# =============================================================================
# Tool Installation
# =============================================================================

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Upgrade pip to latest version for better dependency resolution
    log "Upgrading pip..."
    python3 -m pip install --quiet --upgrade pip

    # Install PyMC with pinned version
    log "Installing ${PACKAGE_NAME}==${TOOL_VERSION}..."
    python3 -m pip install --quiet "${PACKAGE_NAME}==${TOOL_VERSION}"

    # Create CLI wrapper script since PyMC is a library, not a CLI tool
    log "Creating CLI wrapper script for validation..."
    local bin_path="/usr/local/bin/pymc"

    cat > "${bin_path}" <<'EOF'
#!/usr/bin/env python3
"""
PyMC CLI wrapper for version checking and basic operations.
"""
import sys

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--version":
        try:
            import pymc
            print(f"pymc {pymc.__version__}")
            return 0
        except ImportError as e:
            print(f"Error: PyMC not found - {e}", file=sys.stderr)
            return 1
    else:
        print("PyMC - Bayesian Modeling and Probabilistic Programming in Python")
        print("\nUsage:")
        print("  pymc --version    Show version information")
        print("\nPyMC is a Python library. Import it in Python:")
        print("  >>> import pymc as pm")
        print("\nFor more information, visit: https://www.pymc.io/")
        return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

    chmod 755 "${bin_path}"

    log "${TOOL_NAME} v${TOOL_VERSION} installed successfully"
}

# =============================================================================
# Validation
# =============================================================================

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Test 1: Check if pymc command exists
    if ! command -v pymc >/dev/null 2>&1; then
        log_error "Validation failed: pymc command not found in PATH"
        exit 1
    fi

    # Test 2: Check version using CLI wrapper
    local output
    if ! output=$(pymc --version 2>&1); then
        log_error "Validation failed: pymc --version command failed"
        log_error "Output: ${output}"
        exit 1
    fi

    # Test 3: Verify version string contains expected version
    if [[ "${output}" == *"${TOOL_VERSION}"* ]]; then
        log "Version check passed: ${output}"
    else
        log_error "Validation failed: version mismatch"
        log_error "Expected: ${TOOL_VERSION}"
        log_error "Got: ${output}"
        exit 1
    fi

    # Test 4: Verify Python import works
    log "Testing Python import..."
    if ! python3 -c "import pymc; import pymc.sampling" >/dev/null 2>&1; then
        log_error "Validation failed: Unable to import pymc in Python"
        exit 1
    fi

    log "Python import test passed"

    # Test 5: Run a simple PyMC example to verify functionality
    log "Running basic functionality test..."
    if ! python3 <<'PYTEST'
import pymc as pm
import numpy as np

# Simple test to verify PyMC works
try:
    with pm.Model() as model:
        # Define a simple prior
        mu = pm.Normal('mu', mu=0, sigma=1)
    # If we get here without errors, basic functionality works
    print("Basic functionality test passed")
except Exception as e:
    print(f"Basic functionality test failed: {e}")
    exit(1)
PYTEST
    then
        log_error "Validation failed: Basic functionality test failed"
        exit 1
    fi

    log "${GREEN}✓${NC} ${TOOL_NAME} v${TOOL_VERSION} validation successful"
    log "Installation completed and verified"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    log "========================================"
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation"
    log "========================================"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "Skipping installation - already at correct version"
        validate
        log "========================================"
        log "Installation script completed (idempotent)"
        log "========================================"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "========================================"
    log "Installation completed successfully"
    log "========================================"
}

# Run main function
main "$@"
