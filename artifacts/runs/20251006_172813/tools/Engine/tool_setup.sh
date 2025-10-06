#!/bin/bash
#
# Installation script for Engine v1.8.13.1 (Open Source Risk Engine)
# https://github.com/OpenSourceRisk/Engine
#
# This script follows Solutions Team installation standards:
# - Idempotent (can be run multiple times safely)
# - Detects and installs prerequisites
# - Pins specific versions
# - Non-interactive
# - Validates installation
#
# IMPORTANT NOTE:
# The OpenSourceRisk Engine GitHub repository contains submodules that reference
# private GitLab repositories (gitlab.acadiasoft.net) requiring SSH authentication.
# This script will attempt to build from source, but may fail if you don't have
# access to these private repositories. In that case, use pre-built binaries from:
# https://github.com/OpenSourceRisk/Engine/releases
#

set -euo pipefail

# Configuration
readonly TOOL_NAME="Engine"
readonly TOOL_VERSION="v1.8.13.1"
readonly REPO_URL="https://github.com/OpenSourceRisk/Engine.git"
readonly INSTALL_DIR="/opt/ore"
readonly BIN_DIR="/usr/local/bin"
readonly BUILD_DIR="/tmp/ore_build_$$"

# Required versions
readonly MIN_CMAKE_VERSION="3.15"
readonly MIN_BOOST_VERSION="1.72.0"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check prerequisites - determine what's installed
check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for C++ build tools
    if ! command -v g++ &>/dev/null; then
        log "  ✗ g++ not found"
        all_present=false
    else
        log "  ✓ g++ found: $(g++ --version | head -n1)"
    fi

    if ! command -v make &>/dev/null; then
        log "  ✗ make not found"
        all_present=false
    else
        log "  ✓ make found: $(make --version | head -n1)"
    fi

    # Check for CMake
    if ! command -v cmake &>/dev/null; then
        log "  ✗ cmake not found"
        all_present=false
    else
        local cmake_version
        cmake_version=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
        log "  ✓ cmake found: $cmake_version"

        # Check version is sufficient
        if ! version_ge "$cmake_version" "$MIN_CMAKE_VERSION"; then
            log "  ✗ cmake version $cmake_version is too old (need >= $MIN_CMAKE_VERSION)"
            all_present=false
        fi
    fi

    # Check for Git
    if ! command -v git &>/dev/null; then
        log "  ✗ git not found"
        all_present=false
    else
        log "  ✓ git found: $(git --version)"
    fi

    # Check for Boost
    if ! ldconfig -p 2>/dev/null | grep -q libboost_system; then
        log "  ✗ Boost C++ libraries not found"
        all_present=false
    else
        log "  ✓ Boost C++ libraries found"
    fi

    # Check for pkg-config (helpful for finding libraries)
    if ! command -v pkg-config &>/dev/null; then
        log "  ✗ pkg-config not found"
        all_present=false
    else
        log "  ✓ pkg-config found"
    fi

    # Check for wget/curl for downloads
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        log "  ✗ Neither wget nor curl found"
        all_present=false
    else
        log "  ✓ Download tool found"
    fi

    if [ "$all_present" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

# Version comparison helper
version_ge() {
    # Returns 0 if $1 >= $2, 1 otherwise
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    if command -v apt-get &>/dev/null; then
        log "Updating apt package lists..."
        apt-get update -y

        log "Installing build essentials..."
        apt-get install -y \
            build-essential \
            g++ \
            gcc \
            make \
            pkg-config \
            wget \
            curl \
            ca-certificates

        log "Installing Git..."
        apt-get install -y git

        log "Installing CMake..."
        apt-get install -y cmake

        # Verify CMake version after installation
        local cmake_version
        cmake_version=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
        if ! version_ge "$cmake_version" "$MIN_CMAKE_VERSION"; then
            error "Installed CMake version $cmake_version is too old (need >= $MIN_CMAKE_VERSION)"
            error "Please install CMake $MIN_CMAKE_VERSION or later manually"
            exit 1
        fi

        log "Installing Boost C++ libraries..."
        apt-get install -y \
            libboost-all-dev \
            libboost-filesystem-dev \
            libboost-system-dev \
            libboost-thread-dev \
            libboost-date-time-dev \
            libboost-serialization-dev \
            libboost-regex-dev \
            libboost-test-dev

        log "Installing optional dependencies..."
        apt-get install -y \
            zlib1g-dev \
            libssl-dev

        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum &>/dev/null; then
        log "Installing prerequisites via yum..."
        yum groupinstall -y "Development Tools"
        yum install -y \
            gcc-c++ \
            make \
            cmake \
            git \
            wget \
            curl \
            boost-devel \
            zlib-devel \
            openssl-devel

        yum clean all

    elif command -v apk &>/dev/null; then
        log "Installing prerequisites via apk..."
        apk add --no-cache \
            build-base \
            g++ \
            gcc \
            make \
            cmake \
            git \
            wget \
            curl \
            boost-dev \
            zlib-dev \
            openssl-dev

    else
        error "Unsupported package manager. Please install prerequisites manually:"
        error "  - build-essential (gcc, g++, make)"
        error "  - cmake >= $MIN_CMAKE_VERSION"
        error "  - git"
        error "  - Boost C++ libraries >= $MIN_BOOST_VERSION"
        error "  - zlib-dev (optional)"
        exit 1
    fi

    log "Prerequisites installation completed"
}

# Verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify C++ compiler
    if ! g++ --version &>/dev/null; then
        error "g++ verification failed"
        exit 1
    fi
    log "  ✓ g++ verified: $(g++ --version | head -n1)"

    # Verify make
    if ! make --version &>/dev/null; then
        error "make verification failed"
        exit 1
    fi
    log "  ✓ make verified: $(make --version | head -n1)"

    # Verify CMake
    if ! cmake --version &>/dev/null; then
        error "cmake verification failed"
        exit 1
    fi
    local cmake_version
    cmake_version=$(cmake --version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    log "  ✓ cmake verified: $cmake_version"

    if ! version_ge "$cmake_version" "$MIN_CMAKE_VERSION"; then
        error "cmake version $cmake_version is insufficient (need >= $MIN_CMAKE_VERSION)"
        exit 1
    fi

    # Verify Git
    if ! git --version &>/dev/null; then
        error "git verification failed"
        exit 1
    fi
    log "  ✓ git verified: $(git --version)"

    # Verify Boost (check for common Boost libraries)
    if ! ldconfig -p 2>/dev/null | grep -q libboost_system; then
        error "Boost libraries verification failed"
        error "libboost_system not found in library path"
        exit 1
    fi
    log "  ✓ Boost libraries verified"

    log "All prerequisites verified successfully"
}

# Check if Engine is already installed
check_existing_installation() {
    log "Checking for existing Engine installation..."

    # Check if ore binary exists
    if [ -f "$BIN_DIR/ore" ]; then
        log "Found ore binary at $BIN_DIR/ore"

        # Try to get version
        if "$BIN_DIR/ore" --version &>/dev/null; then
            local installed_version
            installed_version=$("$BIN_DIR/ore" --version 2>&1 || echo "unknown")
            log "Installed version: $installed_version"

            # Check if it's the correct version
            if echo "$installed_version" | grep -q "$TOOL_VERSION"; then
                log "Engine $TOOL_VERSION is already installed"
                return 0
            else
                log "Different version installed, will reinstall"
                return 1
            fi
        else
            log "ore binary exists but cannot determine version"
            return 1
        fi
    fi

    # Check if installation directory exists
    if [ -d "$INSTALL_DIR" ]; then
        log "Installation directory $INSTALL_DIR exists"

        # Check if it has the correct version
        if [ -f "$INSTALL_DIR/VERSION" ]; then
            local installed_version
            installed_version=$(cat "$INSTALL_DIR/VERSION")
            if [ "$installed_version" = "$TOOL_VERSION" ]; then
                log "Engine $TOOL_VERSION is already installed at $INSTALL_DIR"

                # Ensure binary is linked
                if [ ! -f "$BIN_DIR/ore" ] && [ -f "$INSTALL_DIR/build/App/ore" ]; then
                    log "Linking ore binary to $BIN_DIR"
                    ln -sf "$INSTALL_DIR/build/App/ore" "$BIN_DIR/ore"
                fi

                return 0
            fi
        fi
    fi

    log "Engine $TOOL_VERSION is not installed"
    return 1
}

# Install Engine
install_tool() {
    log "Installing Engine $TOOL_VERSION..."

    # Create build directory
    log "Creating build directory: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Clone the repository with submodules
    log "Cloning Engine repository (this may take several minutes)..."
    if ! git clone --recurse-submodules --branch "$TOOL_VERSION" --depth 1 "$REPO_URL" ore; then
        error "Failed to clone Engine repository"
        error "Please check your internet connection and that version $TOOL_VERSION exists"
        error ""
        error "NOTE: The OpenSourceRisk Engine repository has submodules that point to"
        error "private GitLab repositories (gitlab.acadiasoft.net) which require SSH access."
        error "This is a known limitation of the public GitHub repository."
        error ""
        error "Alternative installation methods:"
        error "1. Download pre-built binaries from: https://github.com/OpenSourceRisk/Engine/releases"
        error "2. Request access to the private GitLab repositories from Acadia"
        error "3. Use ORE Docker images if available"
        exit 1
    fi

    cd ore

    # Configure build with CMake
    log "Configuring build with CMake..."
    mkdir -p build
    cd build

    # Set Boost paths if needed
    if [ -d "/usr/include/boost" ]; then
        export BOOST_INCLUDEDIR="/usr/include"
    fi
    if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
        export BOOST_LIBRARYDIR="/usr/lib/x86_64-linux-gnu"
    fi

    # Run CMake with appropriate flags
    if ! cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DORE_USE_ZLIB=ON \
        -DBUILD_DOC=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTS=OFF; then
        error "CMake configuration failed"
        error "Check that all dependencies are properly installed"
        exit 1
    fi

    # Build the project
    log "Building Engine (this may take 30+ minutes)..."
    local num_cores
    num_cores=$(nproc 2>/dev/null || echo 2)
    log "Using $num_cores CPU cores for parallel build"

    if ! cmake --build . --config Release -j "$num_cores"; then
        error "Build failed"
        error "Check build logs above for specific errors"
        exit 1
    fi

    # Install to target directory
    log "Installing to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    # Copy the built artifacts
    cp -r "$BUILD_DIR/ore" "$INSTALL_DIR/"

    # Create version file
    echo "$TOOL_VERSION" > "$INSTALL_DIR/VERSION"

    # Link the ore binary to system bin directory
    if [ -f "$INSTALL_DIR/ore/build/App/ore" ]; then
        log "Linking ore binary to $BIN_DIR"
        ln -sf "$INSTALL_DIR/ore/build/App/ore" "$BIN_DIR/ore"
        chmod +x "$BIN_DIR/ore"
    else
        error "ore binary not found at expected location"
        exit 1
    fi

    # Clean up build directory
    log "Cleaning up build directory..."
    cd /
    rm -rf "$BUILD_DIR"

    log "Engine installation completed"
}

# Validate the installation
validate() {
    log "Validating Engine installation..."

    # Check if ore binary exists and is executable
    if [ ! -x "$BIN_DIR/ore" ]; then
        error "ore binary not found or not executable at $BIN_DIR/ore"
        exit 1
    fi

    # Try to run the version command
    if ! "$BIN_DIR/ore" --version &>/dev/null; then
        error "Failed to run 'ore --version'"
        error "The binary may be installed but not working correctly"
        exit 1
    fi

    # Get and display version
    local version_output
    version_output=$("$BIN_DIR/ore" --version 2>&1 || echo "unknown")
    log "Engine version check: $version_output"

    # Verify it matches expected version
    if echo "$version_output" | grep -q "$TOOL_VERSION"; then
        log "✓ Engine $TOOL_VERSION validated successfully"
        return 0
    else
        log "⚠ Warning: Version output does not contain expected version $TOOL_VERSION"
        log "⚠ However, ore binary is functional"
        return 0
    fi
}

# Main installation flow
main() {
    log "Starting Engine $TOOL_VERSION installation..."
    log "Installation directory: $INSTALL_DIR"
    log "Binary directory: $BIN_DIR"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "Skipping prerequisite installation (all present)"
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "Engine $TOOL_VERSION is already installed and validated"
        validate
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "=========================================="
    log "Engine $TOOL_VERSION installation completed successfully!"
    log "Binary location: $BIN_DIR/ore"
    log "Installation directory: $INSTALL_DIR"
    log "=========================================="
}

# Run main installation
main "$@"
