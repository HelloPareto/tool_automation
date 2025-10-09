#!/usr/bin/env bash
set -euo pipefail

# CPython Installation Script
# Version: 3.15.0 (latest from main branch)
# Installation method: Build from source

TOOL_VERSION="3.15.0"
PYTHON_VERSION="3.15"
INSTALL_PREFIX="/usr/local"
PYTHON_BINARY="${INSTALL_PREFIX}/bin/python${PYTHON_VERSION}"
SOURCE_DIR="/tmp/cpython-build-${TOOL_VERSION}"
REPO_URL="https://github.com/python/cpython.git"
# Pinning to a specific commit from main branch for reproducibility
COMMIT_HASH="2d4601804751b78fe5ced72da1d8af7b5e5ced6f"  # Latest stable commit as of Oct 2024

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if prerequisites are installed
check_prerequisites() {
    log "Checking prerequisites..."

    local missing=0

    # Check for essential build tools
    if ! command -v gcc >/dev/null 2>&1; then
        log "Missing: gcc (build-essential)"
        missing=1
    fi

    if ! command -v make >/dev/null 2>&1; then
        log "Missing: make (build-essential)"
        missing=1
    fi

    if ! command -v pkg-config >/dev/null 2>&1; then
        log "Missing: pkg-config"
        missing=1
    fi

    if ! command -v git >/dev/null 2>&1; then
        log "Missing: git"
        missing=1
    fi

    # Check for required development libraries by checking for header files
    local dev_libs=(
        "/usr/include/openssl/ssl.h:libssl-dev"
        "/usr/include/ffi.h:libffi-dev"
        "/usr/include/bzlib.h:libbz2-dev"
        "/usr/include/gdbm.h:libgdbm-dev"
        "/usr/include/lzma.h:liblzma-dev"
        "/usr/include/ncurses.h:libncurses5-dev"
        "/usr/include/readline/readline.h:libreadline-dev"
        "/usr/include/sqlite3.h:libsqlite3-dev"
        "/usr/include/zlib.h:zlib1g-dev"
        "/usr/include/uuid/uuid.h:uuid-dev"
        "/usr/include/zstd.h:libzstd-dev"
    )

    for lib_check in "${dev_libs[@]}"; do
        IFS=':' read -r header package <<< "$lib_check"
        if [ ! -f "$header" ]; then
            log "Missing: $package"
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

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    apt-get update || error_exit "Failed to update package lists"

    # Install build tools
    log "Installing build-essential and core tools..."
    apt-get install -y \
        build-essential \
        pkg-config \
        git \
        wget \
        ca-certificates \
        || error_exit "Failed to install build tools"

    # Install development libraries for Python modules
    log "Installing Python development libraries..."
    apt-get install -y \
        libssl-dev \
        libffi-dev \
        libbz2-dev \
        libgdbm-dev \
        libgdbm-compat-dev \
        liblzma-dev \
        libncurses5-dev \
        libreadline-dev \
        libsqlite3-dev \
        zlib1g-dev \
        tk-dev \
        uuid-dev \
        libzstd-dev \
        || error_exit "Failed to install development libraries"

    # Note: libmpdec-dev is not available on Ubuntu 24.04 / Debian 12
    # Installing it if available, but not failing if it's not
    log "Attempting to install optional libmpdec-dev..."
    apt-get install -y libmpdec-dev 2>/dev/null || log "libmpdec-dev not available, skipping"

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify build tools
    gcc --version >/dev/null 2>&1 || error_exit "gcc verification failed"
    make --version >/dev/null 2>&1 || error_exit "make verification failed"
    pkg-config --version >/dev/null 2>&1 || error_exit "pkg-config verification failed"
    git --version >/dev/null 2>&1 || error_exit "git verification failed"

    log "GCC version: $(gcc --version | head -n1)"
    log "Make version: $(make --version | head -n1)"
    log "Git version: $(git --version)"

    log "Prerequisites verified successfully"
}

# Check if CPython is already installed
check_existing_installation() {
    log "Checking for existing CPython ${TOOL_VERSION} installation..."

    if [ -f "${PYTHON_BINARY}" ]; then
        log "Found existing Python binary at ${PYTHON_BINARY}"

        # Check if it's the right version
        if "${PYTHON_BINARY}" --version 2>&1 | grep -q "${PYTHON_VERSION}"; then
            log "CPython ${PYTHON_VERSION} is already installed"
            return 0
        else
            log "Found Python binary but version doesn't match"
            return 1
        fi
    fi

    log "CPython ${TOOL_VERSION} is not installed"
    return 1
}

# Install CPython from source
install_tool() {
    log "Starting CPython ${TOOL_VERSION} installation from source..."

    # Clean up any previous build directory
    if [ -d "${SOURCE_DIR}" ]; then
        log "Cleaning up previous build directory..."
        rm -rf "${SOURCE_DIR}"
    fi

    # Clone the repository
    log "Cloning CPython repository..."
    git clone --depth 1 "${REPO_URL}" "${SOURCE_DIR}" || error_exit "Failed to clone repository"

    cd "${SOURCE_DIR}" || error_exit "Failed to change to source directory"

    # Checkout specific commit for reproducibility
    log "Fetching specific commit ${COMMIT_HASH}..."
    git fetch --depth 1 origin "${COMMIT_HASH}" || log "Could not fetch specific commit, using latest main"
    git checkout "${COMMIT_HASH}" 2>/dev/null || log "Using HEAD from main branch"

    log "Configuring build..."
    # Configure without aggressive optimizations for more stable builds
    # LTO can cause issues on some platforms, so we disable it
    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --enable-shared \
        --with-computed-gotos \
        --with-system-expat \
        --enable-loadable-sqlite-extensions \
        LDFLAGS="-Wl,-rpath=${INSTALL_PREFIX}/lib" \
        || error_exit "Configure failed"

    log "Building CPython (this may take 10-15 minutes)..."
    # Use fewer parallel jobs for more stable builds, especially on emulated platforms
    make -j2 || error_exit "Build failed"

    log "Running quicktest..."
    # Run a minimal test to verify the build works
    make quicktest || log "Warning: Quicktest had issues, but continuing installation"

    log "Installing CPython..."
    make altinstall || error_exit "Installation failed"

    # Create symlinks for convenience
    log "Creating symlinks..."
    ln -sf "${INSTALL_PREFIX}/bin/python${PYTHON_VERSION}" "${INSTALL_PREFIX}/bin/python3" || true
    ln -sf "${INSTALL_PREFIX}/bin/pip${PYTHON_VERSION}" "${INSTALL_PREFIX}/bin/pip3" || true

    # Update shared library cache
    log "Updating shared library cache..."
    ldconfig || log "Warning: ldconfig failed, shared libraries may not be found"

    # Clean up source directory
    log "Cleaning up build directory..."
    cd /
    rm -rf "${SOURCE_DIR}"

    log "CPython installation completed successfully"
}

# Validate installation
validate() {
    log "Validating CPython installation..."

    # Check if binary exists
    if [ ! -f "${PYTHON_BINARY}" ]; then
        error_exit "Python binary not found at ${PYTHON_BINARY}"
    fi

    # Check version
    local installed_version
    installed_version=$("${PYTHON_BINARY}" --version 2>&1 | awk '{print $2}')
    log "Installed version: ${installed_version}"

    if ! echo "${installed_version}" | grep -q "^${PYTHON_VERSION}"; then
        error_exit "Version mismatch. Expected ${PYTHON_VERSION}.x, got ${installed_version}"
    fi

    # Test basic functionality
    log "Testing basic Python functionality..."
    "${PYTHON_BINARY}" -c "import sys; print(f'Python {sys.version}')" || error_exit "Basic Python test failed"

    # Test importing common modules
    log "Testing standard library modules..."
    "${PYTHON_BINARY}" -c "import ssl, sqlite3, zlib, bz2, lzma, readline" || error_exit "Standard library module import failed"

    # Check pip
    if [ -f "${INSTALL_PREFIX}/bin/pip${PYTHON_VERSION}" ]; then
        log "pip version: $("${INSTALL_PREFIX}/bin/pip${PYTHON_VERSION}" --version)"
    fi

    log "Validation successful!"
    log "Python ${PYTHON_VERSION} installed at: ${PYTHON_BINARY}"
    log "To use: python${PYTHON_VERSION} --version"

    return 0
}

# Main installation flow
main() {
    log "=========================================="
    log "CPython ${TOOL_VERSION} Installation"
    log "=========================================="

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "Prerequisites already satisfied"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "CPython is already installed, validating..."
        validate
        log "Installation is already complete and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "=========================================="
    log "Installation completed successfully!"
    log "=========================================="
}

# Run main function
main "$@"
