#!/bin/bash
set -euo pipefail

# R Source Installation Script
# Tool: r-source (The R Programming Language from source)
# Version: 4.4.2 (latest stable)
# Description: Installs R programming language from source code

# Configuration
readonly TOOL_NAME="r-source"
readonly R_VERSION="4.4.2"
readonly R_TARBALL_URL="https://cran.r-project.org/src/base/R-4/R-${R_VERSION}.tar.gz"
readonly INSTALL_PREFIX="/usr/local"
readonly BUILD_DIR="/tmp/r-build-${R_VERSION}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if prerequisites are installed
check_prerequisites() {
    log "Checking for required prerequisites..."

    local missing_prereqs=0

    # Check for essential build tools
    if ! command -v gcc >/dev/null 2>&1; then
        log "Missing: gcc (C compiler)"
        missing_prereqs=1
    else
        log "Found: gcc $(gcc --version | head -n1)"
    fi

    if ! command -v g++ >/dev/null 2>&1; then
        log "Missing: g++ (C++ compiler)"
        missing_prereqs=1
    else
        log "Found: g++ $(g++ --version | head -n1)"
    fi

    if ! command -v gfortran >/dev/null 2>&1; then
        log "Missing: gfortran (Fortran compiler)"
        missing_prereqs=1
    else
        log "Found: gfortran $(gfortran --version | head -n1)"
    fi

    if ! command -v make >/dev/null 2>&1; then
        log "Missing: make"
        missing_prereqs=1
    else
        log "Found: make $(make --version | head -n1)"
    fi

    if ! command -v git >/dev/null 2>&1; then
        log "Missing: git"
        missing_prereqs=1
    else
        log "Found: git $(git --version)"
    fi

    if ! command -v perl >/dev/null 2>&1; then
        log "Missing: perl"
        missing_prereqs=1
    else
        log "Found: perl $(perl --version | grep -oP 'v\d+\.\d+\.\d+' | head -n1)"
    fi

    # Check for essential libraries via pkg-config or files
    if ! pkg-config --exists zlib 2>/dev/null && [ ! -f /usr/include/zlib.h ]; then
        log "Missing: zlib development libraries"
        missing_prereqs=1
    else
        log "Found: zlib"
    fi

    if [ ! -f /usr/include/bzlib.h ]; then
        log "Missing: bzip2 development libraries"
        missing_prereqs=1
    else
        log "Found: bzip2"
    fi

    if [ ! -f /usr/include/lzma.h ]; then
        log "Missing: xz/liblzma development libraries"
        missing_prereqs=1
    else
        log "Found: xz/liblzma"
    fi

    if ! pkg-config --exists libpcre2-8 2>/dev/null && [ ! -f /usr/include/pcre2.h ]; then
        log "Missing: pcre2 development libraries"
        missing_prereqs=1
    else
        log "Found: pcre2"
    fi

    if ! pkg-config --exists libcurl 2>/dev/null && [ ! -f /usr/include/curl/curl.h ]; then
        log "Missing: curl development libraries"
        missing_prereqs=1
    else
        log "Found: libcurl"
    fi

    if [ $missing_prereqs -eq 1 ]; then
        log "Some prerequisites are missing and need to be installed"
        return 1
    fi

    log "All prerequisites are present"
    return 0
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites for R source build..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package lists
    log "Updating package lists..."
    apt-get update || error "Failed to update package lists"

    # Install compilers and build tools
    log "Installing compilers and build tools..."
    apt-get install -y \
        build-essential \
        gfortran \
        g++ \
        gcc \
        make \
        perl \
        git \
        wget \
        curl \
        || error "Failed to install build tools"

    # Install essential development libraries required for R
    log "Installing essential development libraries..."
    apt-get install -y \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libpcre2-dev \
        libcurl4-openssl-dev \
        libreadline-dev \
        libxt-dev \
        libx11-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff-dev \
        libcairo2-dev \
        libpango1.0-dev \
        libblas-dev \
        liblapack-dev \
        || error "Failed to install development libraries"

    # Install additional utilities
    log "Installing additional utilities..."
    apt-get install -y \
        pkg-config \
        unzip \
        zip \
        gawk \
        rsync \
        file \
        || error "Failed to install utilities"

    # Install TeX Live for building documentation (minimal set)
    log "Installing TeX Live for documentation..."
    apt-get install -y \
        texinfo \
        texlive-base \
        texlive-latex-base \
        texlive-fonts-recommended \
        texlive-fonts-extra \
        texlive-latex-extra \
        || log "Warning: TeX Live installation failed, documentation may not build"

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

# Verify prerequisites are working
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify compilers
    gcc --version >/dev/null 2>&1 || error "gcc verification failed"
    g++ --version >/dev/null 2>&1 || error "g++ verification failed"
    gfortran --version >/dev/null 2>&1 || error "gfortran verification failed"
    make --version >/dev/null 2>&1 || error "make verification failed"

    # Verify tools
    git --version >/dev/null 2>&1 || error "git verification failed"
    perl --version >/dev/null 2>&1 || error "perl verification failed"
    pkg-config --version >/dev/null 2>&1 || error "pkg-config verification failed"

    log "All prerequisites verified successfully"
}

# Check if R is already installed
check_existing_installation() {
    log "Checking for existing R installation..."

    if command -v R >/dev/null 2>&1; then
        local installed_version
        installed_version=$(R --version 2>&1 | grep "R version" | head -n1 || echo "unknown")
        log "Found existing R installation: $installed_version"

        # Check if it matches our target version
        if echo "$installed_version" | grep -q "${R_VERSION}"; then
            log "R ${R_VERSION} is already installed"
            return 0
        else
            log "Different R version installed, will proceed with installation"
            return 1
        fi
    fi

    log "R is not installed"
    return 1
}

# Download R source code
download_source() {
    log "Downloading R source code from ${R_TARBALL_URL}..."

    # Create build directory
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    # Download the tarball
    log "Downloading R ${R_VERSION} tarball..."
    wget -q --show-progress "${R_TARBALL_URL}" -O "R-${R_VERSION}.tar.gz" || error "Failed to download R tarball"

    # Extract the tarball
    log "Extracting R source code..."
    tar -xzf "R-${R_VERSION}.tar.gz" || error "Failed to extract R tarball"

    # Clean up tarball
    rm "R-${R_VERSION}.tar.gz"

    log "Source code downloaded and extracted successfully"
}

# Build R from source
build_r() {
    log "Building R from source (this will take 10-30 minutes)..."

    cd "${BUILD_DIR}/R-${R_VERSION}"

    # Configure R with recommended options
    log "Configuring R..."
    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --enable-R-shlib \
        --enable-memory-profiling \
        --with-blas \
        --with-lapack \
        --with-readline \
        --with-x=yes \
        --with-cairo \
        --with-libpng \
        --with-jpeglib \
        --with-libtiff \
        || error "Configuration failed. Check that all prerequisites are installed."

    # Build R
    log "Compiling R (this takes time, please be patient)..."
    make -j"$(nproc)" || error "Compilation failed"

    log "Build completed successfully"
}

# Install R
install_tool() {
    log "Installing R ${R_VERSION}..."

    # Download source if not already present
    if [ ! -d "${BUILD_DIR}/R-${R_VERSION}" ]; then
        download_source
    fi

    # Build if not already built
    if [ ! -f "${BUILD_DIR}/R-${R_VERSION}/bin/R" ]; then
        build_r
    fi

    # Install R
    cd "${BUILD_DIR}/R-${R_VERSION}"
    log "Installing R to ${INSTALL_PREFIX}..."
    make install || error "Installation failed"

    # Clean up build directory
    log "Cleaning up build directory..."
    rm -rf "${BUILD_DIR}"

    log "R installation completed"
}

# Validate installation
validate() {
    log "Validating R installation..."

    # Check if R command exists
    if ! command -v R >/dev/null 2>&1; then
        error "R command not found in PATH after installation"
    fi

    # Get R version
    local version_output
    version_output=$(R --version 2>&1 | head -n1)
    log "Installed: $version_output"

    # Verify version contains expected version number
    if echo "$version_output" | grep -q "${R_VERSION}"; then
        log "Version verification successful"
    else
        log "Warning: Version output doesn't match expected version ${R_VERSION}"
        log "This may be acceptable if you're installing latest development version"
    fi

    # Test R can execute basic commands
    printf 'cat("R is working correctly\\n")\n' | R --vanilla --slave >/dev/null 2>&1 || error "R execution test failed"

    log "Validation successful - R is installed and working"

    # Note about the validation command
    log "NOTE: The validation command specified was 'r-source --version', but R is installed as 'R'"
    log "Use 'R --version' to check the R version"
}

# Main installation flow
main() {
    log "Starting ${TOOL_NAME} ${R_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        log "R is already installed with the correct version"
        validate
        log "Installation script completed (no changes needed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
    log "You can now use R by running: R"
}

# Run main function
main "$@"
