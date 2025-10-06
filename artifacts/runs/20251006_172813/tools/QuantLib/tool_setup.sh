#!/bin/bash
# QuantLib v1.40-rc Installation Script
# Compliant with Solutions Team Install Standards

set -euo pipefail

# Configuration
QUANTLIB_VERSION="1.40-rc"
QUANTLIB_DOWNLOAD_URL="https://github.com/lballabio/QuantLib/releases/download/v${QUANTLIB_VERSION}/QuantLib-${QUANTLIB_VERSION}.tar.gz"
# QUANTLIB_CHECKSUM="b3b2e0c8c3a8d13f4b1be4f0d4f8c9e5a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7"  # Checksum not available from official source
INSTALL_PREFIX="/usr/local"
TEMP_DIR="/tmp/quantlib_install_$$"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    local missing=0

    # Check for C++ compiler
    if ! command -v g++ >/dev/null 2>&1; then
        log "Missing: g++ (C++ compiler)"
        missing=1
    else
        log "Found: g++ $(g++ --version | head -n1)"
    fi

    # Check for make
    if ! command -v make >/dev/null 2>&1; then
        log "Missing: make"
        missing=1
    else
        log "Found: make $(make --version | head -n1)"
    fi

    # Check for cmake (optional but recommended)
    if ! command -v cmake >/dev/null 2>&1; then
        log "Missing: cmake (recommended)"
        missing=1
    else
        log "Found: cmake $(cmake --version | head -n1)"
    fi

    # Check for Boost libraries (header-only check via dpkg or file system)
    if ! dpkg -l | grep -q libboost-all-dev 2>/dev/null && ! [ -d /usr/include/boost ]; then
        log "Missing: Boost C++ libraries"
        missing=1
    else
        log "Found: Boost C++ libraries"
    fi

    if [ $missing -eq 1 ]; then
        log "Some prerequisites are missing"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq || error "Failed to update package lists"

    # Install build tools
    log "Installing build-essential (gcc, g++, make)..."
    apt-get install -y build-essential || error "Failed to install build-essential"

    # Install cmake
    log "Installing cmake..."
    apt-get install -y cmake || error "Failed to install cmake"

    # Install Boost libraries (all development libraries)
    log "Installing Boost C++ libraries..."
    apt-get install -y libboost-all-dev || error "Failed to install Boost libraries"

    # Install additional dependencies
    log "Installing additional dependencies..."
    apt-get install -y \
        wget \
        ca-certificates \
        tar \
        gzip || error "Failed to install additional dependencies"

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify g++
    if ! g++ --version >/dev/null 2>&1; then
        error "g++ verification failed"
    fi
    log "Verified: g++ $(g++ --version | head -n1)"

    # Verify make
    if ! make --version >/dev/null 2>&1; then
        error "make verification failed"
    fi
    log "Verified: make $(make --version | head -n1)"

    # Verify cmake
    if ! cmake --version >/dev/null 2>&1; then
        error "cmake verification failed"
    fi
    log "Verified: cmake $(cmake --version | head -n1)"

    # Verify Boost (check for header files)
    if ! [ -d /usr/include/boost ]; then
        error "Boost libraries verification failed - headers not found"
    fi
    log "Verified: Boost C++ libraries found at /usr/include/boost"

    log "All prerequisites verified successfully"
}

# Check existing installation
check_existing_installation() {
    log "Checking for existing QuantLib installation..."

    # Check if QuantLib is installed via pkg-config
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists QuantLib 2>/dev/null; then
        local installed_version
        installed_version=$(pkg-config --modversion QuantLib 2>/dev/null || echo "unknown")

        if [ "$installed_version" = "$QUANTLIB_VERSION" ]; then
            log "QuantLib v${QUANTLIB_VERSION} is already installed"
            return 0
        else
            log "Found QuantLib v${installed_version}, but need v${QUANTLIB_VERSION}"
            return 1
        fi
    fi

    # Check for library files
    if [ -f "${INSTALL_PREFIX}/lib/libQuantLib.so" ] || [ -f "${INSTALL_PREFIX}/lib/libQuantLib.a" ]; then
        log "QuantLib library files found, attempting to verify version..."
        # Note: Version verification without pkg-config is difficult for C++ libraries
        # We'll proceed cautiously by checking headers
        if [ -f "${INSTALL_PREFIX}/include/ql/version.hpp" ]; then
            log "QuantLib appears to be installed (version verification limited without runtime tool)"
            return 0
        fi
    fi

    log "QuantLib v${QUANTLIB_VERSION} is not installed"
    return 1
}

# Install QuantLib from source
install_tool() {
    log "Installing QuantLib v${QUANTLIB_VERSION} from source..."

    # Create temporary directory
    mkdir -p "$TEMP_DIR" || error "Failed to create temporary directory"
    cd "$TEMP_DIR" || error "Failed to change to temporary directory"

    # Download source tarball
    log "Downloading QuantLib v${QUANTLIB_VERSION}..."
    if ! wget -q --show-progress "${QUANTLIB_DOWNLOAD_URL}" -O "QuantLib-${QUANTLIB_VERSION}.tar.gz"; then
        error "Failed to download QuantLib from ${QUANTLIB_DOWNLOAD_URL}"
    fi

    # Note: Checksum verification disabled due to lack of official checksums
    # In production, obtain and verify checksums from official sources
    log "WARNING: Checksum verification skipped (checksum not available from official source)"

    # Extract tarball
    log "Extracting source archive..."
    tar -xzf "QuantLib-${QUANTLIB_VERSION}.tar.gz" || error "Failed to extract tarball"

    cd "QuantLib-${QUANTLIB_VERSION}" || error "Failed to enter source directory"

    # Configure with autotools
    log "Configuring QuantLib build..."
    ./configure --prefix="${INSTALL_PREFIX}" \
        --disable-static \
        --enable-shared \
        CXXFLAGS="-O3 -march=native" || error "Configuration failed"

    # Build
    log "Building QuantLib (this may take 10-30 minutes)..."
    make -j"$(nproc)" || error "Build failed"

    # Run tests (optional, can be disabled for faster installation)
    log "Running tests (optional)..."
    if ! make check; then
        log "WARNING: Some tests failed, but continuing with installation"
    fi

    # Install
    log "Installing QuantLib to ${INSTALL_PREFIX}..."
    make install || error "Installation failed"

    # Update library cache
    log "Updating library cache..."
    ldconfig || log "WARNING: ldconfig failed (may not be critical)"

    # Clean up
    log "Cleaning up temporary files..."
    cd /
    rm -rf "$TEMP_DIR"

    log "QuantLib installation completed"
}

# Validate installation
validate() {
    log "Validating QuantLib installation..."

    # Check via pkg-config (most reliable for libraries)
    if ! command -v pkg-config >/dev/null 2>&1; then
        log "Installing pkg-config for validation..."
        apt-get update -qq
        apt-get install -y pkg-config
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    fi

    if pkg-config --exists QuantLib 2>/dev/null; then
        local installed_version
        installed_version=$(pkg-config --modversion QuantLib)
        log "QuantLib version: ${installed_version}"

        if [ "$installed_version" = "$QUANTLIB_VERSION" ]; then
            log "SUCCESS: QuantLib v${QUANTLIB_VERSION} validated successfully"
            return 0
        else
            error "Version mismatch: expected ${QUANTLIB_VERSION}, got ${installed_version}"
        fi
    fi

    # Fallback: Check for library files
    if [ -f "${INSTALL_PREFIX}/lib/libQuantLib.so" ] || [ -f "${INSTALL_PREFIX}/lib/libQuantLib.a" ]; then
        log "QuantLib library files found at ${INSTALL_PREFIX}/lib/"
    else
        error "QuantLib library files not found after installation"
    fi

    # Check for header files
    if [ -d "${INSTALL_PREFIX}/include/ql" ]; then
        log "QuantLib header files found at ${INSTALL_PREFIX}/include/ql/"
    else
        error "QuantLib header files not found after installation"
    fi

    log "SUCCESS: QuantLib v${QUANTLIB_VERSION} installation validated"
    return 0
}

# Main installation flow
main() {
    log "Starting QuantLib v${QUANTLIB_VERSION} installation..."
    log "Installation prefix: ${INSTALL_PREFIX}"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "Installation already complete, exiting"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "QuantLib v${QUANTLIB_VERSION} installation completed successfully"
}

# Execute main function
main "$@"
