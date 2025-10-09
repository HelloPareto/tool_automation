#!/usr/bin/env bash
################################################################################
# CPython Installation Script
# Tool: cpython
# Version: 3.14.0 (latest stable as of October 2025)
# Description: The Python programming language
# Validation Command: python3.14 --version
################################################################################

set -euo pipefail

# Configuration
CPYTHON_VERSION="3.14.0"
CPYTHON_MAJOR_MINOR="3.14"
INSTALL_PREFIX="/usr/local"
DOWNLOAD_URL="https://www.python.org/ftp/python/${CPYTHON_VERSION}/Python-${CPYTHON_VERSION}.tar.xz"
CHECKSUM="2299dae542d395ce3883aca00d3c910307cd68e0b2f7336098c8e7b7eee9f3e9"  # SHA256 for Python 3.14.0

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

################################################################################
# Function: check_prerequisites
# Description: Check if all required build prerequisites are already installed
# Returns: 0 if all present, 1 if any missing
################################################################################
check_prerequisites() {
    log "Checking for required prerequisites..."
    local missing=0

    # Check for essential build tools
    if ! command -v gcc >/dev/null 2>&1; then
        log "  Missing: gcc (C compiler)"
        missing=1
    else
        log "  Found: gcc $(gcc --version | head -n1)"
    fi

    if ! command -v make >/dev/null 2>&1; then
        log "  Missing: make"
        missing=1
    else
        log "  Found: make $(make --version | head -n1)"
    fi

    if ! command -v pkg-config >/dev/null 2>&1; then
        log "  Missing: pkg-config"
        missing=1
    else
        log "  Found: pkg-config"
    fi

    # Check for required development libraries
    local required_libs=(
        "zlib.h"
        "openssl/ssl.h"
        "bzlib.h"
        "ffi.h"
        "sqlite3.h"
        "readline/readline.h"
        "lzma.h"
    )

    for lib in "${required_libs[@]}"; do
        if ! echo "#include <${lib}>" | gcc -E - >/dev/null 2>&1; then
            log "  Missing: development library for ${lib}"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log "Some prerequisites are missing"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

################################################################################
# Function: install_prerequisites
# Description: Install all required build prerequisites
################################################################################
install_prerequisites() {
    log "Installing prerequisites for CPython build..."

    # Update package list
    log "Updating package list..."
    apt-get update || error "Failed to update package list"

    # Install build dependencies
    log "Installing build tools and development libraries..."
    apt-get install -y \
        build-essential \
        gdb \
        lcov \
        pkg-config \
        libbz2-dev \
        libffi-dev \
        libgdbm-dev \
        libgdbm-compat-dev \
        liblzma-dev \
        libncurses5-dev \
        libreadline6-dev \
        libsqlite3-dev \
        libssl-dev \
        lzma \
        lzma-dev \
        tk-dev \
        uuid-dev \
        zlib1g-dev \
        libmpdec-dev \
        libzstd-dev \
        dpkg-dev \
        wget \
        xz-utils || error "Failed to install prerequisites"

    # Clean up apt cache
    log "Cleaning apt cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

################################################################################
# Function: verify_prerequisites
# Description: Verify that all prerequisites are working correctly
################################################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify build tools
    gcc --version >/dev/null 2>&1 || error "gcc verification failed"
    make --version >/dev/null 2>&1 || error "make verification failed"
    pkg-config --version >/dev/null 2>&1 || error "pkg-config verification failed"

    log "Verifying development libraries..."

    # Test compile with critical headers
    local test_code='
#include <zlib.h>
#include <openssl/ssl.h>
#include <bzlib.h>
#include <ffi.h>
#include <sqlite3.h>
#include <lzma.h>

int main() { return 0; }
'

    if ! echo "${test_code}" | gcc -x c - -o /tmp/test_prereq -lz -lssl -lbz2 -lffi -lsqlite3 -llzma 2>/dev/null; then
        rm -f /tmp/test_prereq
        error "Failed to verify development libraries"
    fi
    rm -f /tmp/test_prereq

    log "All prerequisites verified successfully"
}

################################################################################
# Function: check_existing_installation
# Description: Check if CPython is already installed at the target version
# Returns: 0 if installed and correct version, 1 otherwise
################################################################################
check_existing_installation() {
    log "Checking for existing CPython installation..."

    if ! command -v python${CPYTHON_MAJOR_MINOR} >/dev/null 2>&1; then
        log "CPython ${CPYTHON_MAJOR_MINOR} not found"
        return 1
    fi

    local installed_version
    installed_version=$(python${CPYTHON_MAJOR_MINOR} --version 2>&1 | awk '{print $2}')

    if [ "${installed_version}" = "${CPYTHON_VERSION}" ]; then
        log "CPython ${CPYTHON_VERSION} is already installed"
        return 0
    else
        log "Found different version: ${installed_version}"
        return 1
    fi
}

################################################################################
# Function: install_tool
# Description: Download, verify, build, and install CPython from source
################################################################################
install_tool() {
    log "Starting CPython ${CPYTHON_VERSION} installation..."

    local build_dir="/tmp/cpython-build-$$"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    # Download source tarball
    log "Downloading CPython ${CPYTHON_VERSION} source..."
    if ! wget -q --show-progress "${DOWNLOAD_URL}" -O "Python-${CPYTHON_VERSION}.tar.xz"; then
        error "Failed to download CPython source from ${DOWNLOAD_URL}"
    fi

    # Verify checksum
    log "Verifying checksum..."
    echo "${CHECKSUM}  Python-${CPYTHON_VERSION}.tar.xz" > checksum.txt
    if ! sha256sum -c checksum.txt; then
        error "Checksum verification failed. Expected: ${CHECKSUM}"
    fi
    log "Checksum verified successfully"

    # Extract source
    log "Extracting source..."
    tar -xf "Python-${CPYTHON_VERSION}.tar.xz" || error "Failed to extract source"
    cd "Python-${CPYTHON_VERSION}"

    # Configure build with optimization
    log "Configuring build (this may take a few minutes)..."
    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --enable-optimizations \
        --enable-shared \
        --with-computed-gotos \
        --with-system-ffi \
        --with-system-libmpdec \
        LDFLAGS="-Wl,-rpath=${INSTALL_PREFIX}/lib" \
        || error "Configuration failed"

    # Build (using limited cores to avoid LTO issues in Docker)
    # Note: We use fewer cores to avoid jobserver issues with LTO during profile-guided optimization
    local num_cores
    num_cores=$(nproc 2>/dev/null || echo 2)
    # Limit to 4 cores max to avoid LTO jobserver issues
    if [ "${num_cores}" -gt 4 ]; then
        num_cores=4
    fi
    log "Building CPython with ${num_cores} cores (this will take 10-30 minutes)..."
    make -j"${num_cores}" || error "Build failed"

    # Run tests (optional but recommended)
    log "Running basic tests..."
    make test TESTOPTS="-j${num_cores} --timeout=300" || log "WARNING: Some tests failed (non-fatal)"

    # Install
    log "Installing CPython to ${INSTALL_PREFIX}..."
    make altinstall || error "Installation failed"

    # Update shared library cache
    log "Updating shared library cache..."
    ldconfig || log "WARNING: ldconfig failed (may need manual library path configuration)"

    # Create convenient symlinks
    log "Creating symlinks..."
    ln -sf "${INSTALL_PREFIX}/bin/python${CPYTHON_MAJOR_MINOR}" "${INSTALL_PREFIX}/bin/cpython" || true
    ln -sf "${INSTALL_PREFIX}/bin/pip${CPYTHON_MAJOR_MINOR}" "${INSTALL_PREFIX}/bin/cpython-pip" || true

    # Clean up build directory
    log "Cleaning up build directory..."
    cd /
    rm -rf "${build_dir}"

    log "CPython ${CPYTHON_VERSION} installed successfully"
}

################################################################################
# Function: validate
# Description: Validate the installation using the specified validation command
################################################################################
validate() {
    log "Validating CPython installation..."

    # Primary validation: check cpython symlink
    if ! command -v cpython >/dev/null 2>&1; then
        error "Validation failed: 'cpython' command not found in PATH"
    fi

    # Check version
    local version_output
    version_output=$(cpython --version 2>&1)
    log "Version check: ${version_output}"

    if ! echo "${version_output}" | grep -q "${CPYTHON_VERSION}"; then
        error "Validation failed: Expected version ${CPYTHON_VERSION}, got: ${version_output}"
    fi

    # Additional validation: verify python3.14 also works
    if ! command -v python${CPYTHON_MAJOR_MINOR} >/dev/null 2>&1; then
        error "Validation failed: python${CPYTHON_MAJOR_MINOR} not found"
    fi

    # Test basic Python functionality
    log "Testing basic Python functionality..."
    if ! cpython -c "import sys; import ssl; import sqlite3; import zlib; print('Python modules OK')"; then
        error "Validation failed: Core Python modules not working"
    fi

    # Verify pip is available
    if ! command -v pip${CPYTHON_MAJOR_MINOR} >/dev/null 2>&1; then
        log "WARNING: pip${CPYTHON_MAJOR_MINOR} not found"
    else
        log "pip version: $(pip${CPYTHON_MAJOR_MINOR} --version)"
    fi

    log "Validation successful: CPython ${CPYTHON_VERSION} is working correctly"
    return 0
}

################################################################################
# Main execution flow
################################################################################
main() {
    log "=========================================="
    log "CPython ${CPYTHON_VERSION} Installation"
    log "=========================================="

    # Step 1: Handle prerequisites
    if ! check_prerequisites; then
        log "Installing missing prerequisites..."
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites already satisfied"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "CPython ${CPYTHON_VERSION} is already installed"
        validate
        log "Installation script completed (no changes needed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "=========================================="
    log "Installation completed successfully!"
    log "=========================================="
    log ""
    log "Usage:"
    log "  cpython --version              # Check version"
    log "  python${CPYTHON_MAJOR_MINOR} --version       # Alternative command"
    log "  cpython -m pip install <package>  # Install Python packages"
}

# Execute main function
main "$@"
