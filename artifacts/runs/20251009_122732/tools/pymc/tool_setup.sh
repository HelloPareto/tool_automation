#!/bin/bash
################################################################################
# PyMC v5.25.1 Installation Script
#
# Description: Installs PyMC (Bayesian Modeling and Probabilistic Programming)
# Version: v5.25.1
# Installation Method: pip (Python Package Index)
# Prerequisites: Python 3.10+, pip
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="pymc"
readonly TOOL_VERSION="5.25.1"
readonly PYTHON_MIN_VERSION="3.10"
readonly VALIDATE_CMD="pymc"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

################################################################################
# Function: check_prerequisites
# Description: Check if required prerequisites are already installed
# Returns: 0 if all present, 1 if any missing
################################################################################
check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for Python 3
    if command -v python3 &>/dev/null; then
        local python_version
        python_version=$(python3 --version 2>&1 | awk '{print $2}')
        log "Found Python: $python_version"

        # Verify Python version meets minimum requirement
        local python_major python_minor
        python_major=$(echo "$python_version" | cut -d. -f1)
        python_minor=$(echo "$python_version" | cut -d. -f2)

        if [[ "$python_major" -lt 3 ]] || [[ "$python_major" -eq 3 && "$python_minor" -lt 10 ]]; then
            log "Python version $python_version is below required minimum 3.10"
            all_present=false
        fi
    else
        log "Python 3 not found"
        all_present=false
    fi

    # Check for pip3
    if command -v pip3 &>/dev/null; then
        local pip_version
        pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
        log "Found pip: $pip_version"
    else
        log "pip3 not found"
        all_present=false
    fi

    if [[ "$all_present" == true ]]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

################################################################################
# Function: install_prerequisites
# Description: Install missing prerequisites (Python 3.10+, pip)
################################################################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Detect OS and package manager
    if command -v apt-get &>/dev/null; then
        log "Using apt-get package manager"
        export DEBIAN_FRONTEND=noninteractive

        log "Updating package lists..."
        apt-get update -qq || die "Failed to update package lists"

        # Check if we need to install Python 3.10+
        if ! command -v python3 &>/dev/null; then
            log "Installing Python 3.10+..."
            apt-get install -y python3 python3-pip python3-venv python3-dev \
                || die "Failed to install Python"
        else
            # Check if we just need pip
            if ! command -v pip3 &>/dev/null; then
                log "Installing pip3..."
                apt-get install -y python3-pip || die "Failed to install pip3"
            fi
        fi

        # Install build essentials (may be needed for PyMC dependencies)
        log "Installing build essentials for Python package compilation..."
        apt-get install -y build-essential gfortran libopenblas-dev liblapack-dev \
            || log "Warning: Failed to install some build tools (may not be critical)"

        # Clean up
        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum &>/dev/null; then
        log "Using yum package manager"

        log "Installing Python 3.10+..."
        yum install -y python3 python3-pip python3-devel gcc gcc-gfortran \
            || die "Failed to install Python"

        log "Cleaning yum cache..."
        yum clean all

    elif command -v brew &>/dev/null; then
        log "Using Homebrew package manager"

        if ! command -v python3 &>/dev/null; then
            log "Installing Python 3..."
            brew install python3 || die "Failed to install Python"
        fi

    else
        die "Unsupported package manager. Please install Python 3.10+ and pip manually."
    fi

    log "Prerequisites installation completed"
}

################################################################################
# Function: verify_prerequisites
# Description: Verify that prerequisites are correctly installed and working
################################################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python 3
    if ! command -v python3 &>/dev/null; then
        die "Python 3 verification failed: python3 command not found"
    fi

    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}')
    log "Verified Python: $python_version"

    # Verify minimum Python version
    local python_major python_minor
    python_major=$(echo "$python_version" | cut -d. -f1)
    python_minor=$(echo "$python_version" | cut -d. -f2)

    if [[ "$python_major" -lt 3 ]] || [[ "$python_major" -eq 3 && "$python_minor" -lt 10 ]]; then
        die "Python version $python_version is below required minimum 3.10"
    fi

    # Verify pip3
    if ! command -v pip3 &>/dev/null; then
        die "pip3 verification failed: pip3 command not found"
    fi

    local pip_version
    pip_version=$(pip3 --version 2>&1 | awk '{print $2}')
    log "Verified pip: $pip_version"

    log "All prerequisites verified successfully"
}

################################################################################
# Function: check_existing_installation
# Description: Check if PyMC is already installed at the correct version
# Returns: 0 if already installed, 1 if not
################################################################################
check_existing_installation() {
    log "Checking for existing PyMC installation..."

    if python3 -c "import pymc" &>/dev/null; then
        local installed_version
        installed_version=$(python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null || echo "unknown")

        if [[ "$installed_version" == "$TOOL_VERSION" ]]; then
            log "PyMC v$TOOL_VERSION is already installed"
            return 0
        else
            log "Found PyMC v$installed_version, but need v$TOOL_VERSION"
            return 1
        fi
    else
        log "PyMC is not installed"
        return 1
    fi
}

################################################################################
# Function: install_tool
# Description: Install PyMC v5.25.1 using pip
################################################################################
install_tool() {
    log "Installing PyMC v$TOOL_VERSION..."

    # Upgrade pip to latest version to avoid compatibility issues
    log "Upgrading pip..."
    pip3 install --upgrade pip || log "Warning: Failed to upgrade pip (continuing anyway)"

    # Install PyMC with pinned version
    log "Installing pymc==$TOOL_VERSION..."
    pip3 install "pymc==$TOOL_VERSION" || die "Failed to install PyMC v$TOOL_VERSION"

    log "PyMC installation completed"
}

################################################################################
# Function: create_cli_wrapper
# Description: Create a CLI wrapper script for PyMC version checking
# Note: PyMC is a Python library without a native CLI, so we create a wrapper
################################################################################
create_cli_wrapper() {
    log "Creating CLI wrapper for PyMC..."

    local wrapper_path="/usr/local/bin/pymc"

    cat > "$wrapper_path" << 'EOF'
#!/usr/bin/env python3
"""
PyMC CLI Wrapper
Provides basic command-line interface for PyMC version checking
"""
import sys
import argparse

try:
    import pymc
except ImportError:
    print("Error: PyMC is not installed", file=sys.stderr)
    sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='PyMC CLI Wrapper')
    parser.add_argument('--version', action='store_true',
                       help='Show PyMC version')

    args = parser.parse_args()

    if args.version:
        print(f"PyMC {pymc.__version__}")
        return 0
    else:
        print("PyMC - Bayesian Modeling and Probabilistic Programming in Python")
        print(f"Version: {pymc.__version__}")
        print("\nUsage:")
        print("  pymc --version    Show version information")
        print("\nFor Python usage:")
        print("  import pymc")
        return 0

if __name__ == '__main__':
    sys.exit(main())
EOF

    chmod +x "$wrapper_path" || die "Failed to make wrapper executable"
    log "CLI wrapper created at $wrapper_path"
}

################################################################################
# Function: validate
# Description: Validate the PyMC installation
################################################################################
validate() {
    log "Validating PyMC installation..."

    # Test Python import
    if ! python3 -c "import pymc" &>/dev/null; then
        die "Validation failed: Cannot import pymc module"
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import pymc; print(pymc.__version__)" 2>/dev/null)

    if [[ "$installed_version" != "$TOOL_VERSION" ]]; then
        die "Validation failed: Expected version $TOOL_VERSION, got $installed_version"
    fi

    log "Python module validation: OK (version $installed_version)"

    # Validate CLI wrapper
    if [[ -f "/usr/local/bin/pymc" ]]; then
        if pymc --version &>/dev/null; then
            local cli_output
            cli_output=$(pymc --version 2>&1)
            log "CLI wrapper validation: OK ($cli_output)"
        else
            log "Warning: CLI wrapper exists but failed to execute"
        fi
    else
        log "Note: CLI wrapper not created (may need root permissions)"
    fi

    log "Validation completed successfully"
    return 0
}

################################################################################
# Function: main
# Description: Main installation workflow
################################################################################
main() {
    log "=========================================="
    log "Starting PyMC v$TOOL_VERSION installation"
    log "=========================================="

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "Prerequisites already satisfied"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "PyMC v$TOOL_VERSION is already installed"
        validate
        log "Installation script completed (no changes needed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Create CLI wrapper (optional, may fail without root)
    if [[ $EUID -eq 0 ]] || [[ -w /usr/local/bin ]]; then
        create_cli_wrapper || log "Warning: Failed to create CLI wrapper (not critical)"
    else
        log "Skipping CLI wrapper creation (requires write access to /usr/local/bin)"
    fi

    # Step 5: Validate installation
    validate

    log "=========================================="
    log "PyMC v$TOOL_VERSION installation completed successfully"
    log "=========================================="
    log ""
    log "Usage:"
    log "  Python: import pymc"
    log "  CLI:    pymc --version (if wrapper was created)"
}

# Execute main function
main "$@"
