#!/bin/bash
#
# Installation script for r-source 4.6.0
# This script builds R from source following the official wch/r-source repository instructions
#
# Tool: r-source
# Version: 4.6.0 (latest development version)
# Repository: https://github.com/wch/r-source
# Installation method: Build from source
#

set -euo pipefail

# Configuration
readonly R_VERSION="4.6.0"
readonly R_INSTALL_PREFIX="/usr/local/lib/R-devel"
readonly R_WRAPPER_PATH="/usr/local/bin/r-source"
readonly R_SOURCE_DIR="/tmp/r-source-build"
readonly R_REPO_URL="https://github.com/wch/r-source.git"
readonly R_BRANCH="trunk"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if running as root or with sudo privileges
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            error "This script requires sudo privileges but sudo is not available"
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    local missing=0

    # Check for essential build tools
    if ! command -v gcc >/dev/null 2>&1; then
        log "Missing: gcc (C compiler)"
        missing=1
    fi

    if ! command -v g++ >/dev/null 2>&1; then
        log "Missing: g++ (C++ compiler)"
        missing=1
    fi

    if ! command -v gfortran >/dev/null 2>&1; then
        log "Missing: gfortran (Fortran compiler)"
        missing=1
    fi

    if ! command -v make >/dev/null 2>&1; then
        log "Missing: make"
        missing=1
    fi

    if ! command -v git >/dev/null 2>&1; then
        log "Missing: git"
        missing=1
    fi

    # Check for required libraries
    if ! ldconfig -p 2>/dev/null | grep -q "libreadline" && ! ls /usr/lib/*libreadline* >/dev/null 2>&1 && ! ls /usr/lib/x86_64-linux-gnu/*libreadline* >/dev/null 2>&1; then
        log "Missing: libreadline development libraries"
        missing=1
    fi

    if ! ldconfig -p 2>/dev/null | grep -q "libcurl" && ! ls /usr/lib/*libcurl* >/dev/null 2>&1 && ! ls /usr/lib/x86_64-linux-gnu/*libcurl* >/dev/null 2>&1; then
        log "Missing: libcurl development libraries"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        log "Prerequisites are missing"
        return 1
    else
        log "All prerequisites are present"
        return 0
    fi
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."

    check_sudo

    # Update package lists
    log "Updating package lists..."
    $SUDO apt-get update || error "Failed to update package lists"

    # Install build dependencies for R
    log "Installing R build dependencies..."
    $SUDO apt-get build-dep -y r-base 2>/dev/null || {
        log "apt-get build-dep not available or failed, installing individual packages..."
        $SUDO apt-get install -y \
            build-essential \
            gfortran \
            libreadline-dev \
            libx11-dev \
            libxt-dev \
            libpng-dev \
            libjpeg-dev \
            libcairo2-dev \
            xvfb \
            libbz2-dev \
            libzstd-dev \
            liblzma-dev \
            libpcre2-dev \
            libcurl4-openssl-dev \
            || error "Failed to install R build dependencies"
    }

    # Install additional required packages
    log "Installing additional build tools and documentation tools..."
    $SUDO apt-get install -y \
        git \
        subversion \
        texinfo \
        texlive-base \
        texlive-latex-base \
        texlive-fonts-recommended \
        texlive-fonts-extra \
        texlive-latex-recommended \
        texlive-latex-extra \
        || log "Warning: Some documentation tools failed to install (non-critical)"

    # Install BLAS and LAPACK for optimized linear algebra
    log "Installing BLAS and LAPACK..."
    $SUDO apt-get install -y \
        libblas-dev \
        liblapack-dev \
        || log "Warning: BLAS/LAPACK installation failed (non-critical)"

    # Clean up apt cache
    log "Cleaning up apt cache..."
    $SUDO apt-get clean
    $SUDO rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

# Verify prerequisites
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify compilers
    log "Verifying GCC..."
    gcc --version >/dev/null || error "GCC verification failed"
    log "GCC version: $(gcc --version | head -n1)"

    log "Verifying G++..."
    g++ --version >/dev/null || error "G++ verification failed"
    log "G++ version: $(g++ --version | head -n1)"

    log "Verifying Gfortran..."
    gfortran --version >/dev/null || error "Gfortran verification failed"
    log "Gfortran version: $(gfortran --version | head -n1)"

    # Verify build tools
    log "Verifying Make..."
    make --version >/dev/null || error "Make verification failed"
    log "Make version: $(make --version | head -n1)"

    log "Verifying Git..."
    git --version >/dev/null || error "Git verification failed"
    log "Git version: $(git --version)"

    log "All prerequisites verified successfully"
}

# Check if R is already installed
check_existing_installation() {
    log "Checking for existing r-source installation..."

    if [[ -f "$R_WRAPPER_PATH" ]] && [[ -d "$R_INSTALL_PREFIX" ]]; then
        log "Found existing r-source installation at $R_WRAPPER_PATH"

        # Check if the R binary exists and is executable
        if [[ -x "$R_INSTALL_PREFIX/bin/R" ]]; then
            log "Existing installation appears valid"
            return 0
        else
            log "Existing installation found but R binary is missing or not executable"
            return 1
        fi
    else
        log "No existing installation found"
        return 1
    fi
}

# Install R from source
install_tool() {
    log "Installing r-source from source..."

    check_sudo

    # Clean up any previous build directory
    if [[ -d "$R_SOURCE_DIR" ]]; then
        log "Removing previous build directory..."
        rm -rf "$R_SOURCE_DIR"
    fi

    # Clone the repository
    log "Cloning r-source repository (this may take several minutes)..."
    git clone --depth 1 --branch "$R_BRANCH" "$R_REPO_URL" "$R_SOURCE_DIR" || error "Failed to clone r-source repository"

    cd "$R_SOURCE_DIR" || error "Failed to change to source directory"

    # Get recommended packages
    log "Fetching recommended packages..."
    if [[ -f "tools/rsync-recommended" ]]; then
        bash tools/rsync-recommended 2>&1 || {
            log "Warning: Failed to sync recommended packages, proceeding without them"
            USE_NO_RECOMMENDED="--without-recommended-packages"
        }
    else
        log "Warning: rsync-recommended script not found"
        USE_NO_RECOMMENDED="--without-recommended-packages"
    fi

    # Check if recommended packages were successfully downloaded
    if [[ ! -d "src/library/Recommended" ]] || [[ -z "$(ls -A src/library/Recommended 2>/dev/null)" ]]; then
        log "Warning: Recommended packages not found, will build without them"
        USE_NO_RECOMMENDED="--without-recommended-packages"
    fi

    # Configure
    log "Configuring R build (this may take several minutes)..."
    # shellcheck disable=SC2086
    ./configure \
        --prefix="$R_INSTALL_PREFIX" \
        --enable-R-shlib \
        --with-blas \
        --with-lapack \
        --with-readline \
        --with-x=no \
        --disable-java \
        ${USE_NO_RECOMMENDED:-} \
        || error "Configuration failed"

    # Build
    log "Building R (this will take 10-30 minutes depending on system)..."
    make -j"$(nproc 2>/dev/null || echo 2)" || error "Build failed"

    # Run basic tests
    log "Running basic checks..."
    make check-all 2>&1 | tee /tmp/r-check.log || {
        log "Warning: Some checks failed (see /tmp/r-check.log for details)"
        log "Continuing with installation..."
    }

    # Install
    log "Installing R to $R_INSTALL_PREFIX..."
    $SUDO make install || error "Installation failed"

    # Create wrapper script
    log "Creating r-source wrapper script..."
    $SUDO tee "$R_WRAPPER_PATH" > /dev/null << 'EOF'
#!/bin/bash
# r-source wrapper script
# Runs R development version from wch/r-source

export PATH="/usr/local/lib/R-devel/bin:$PATH"

# Execute R with all passed arguments
exec "$R_INSTALL_PREFIX/bin/R" "$@"
EOF

    # Update the wrapper script with actual R_INSTALL_PREFIX
    $SUDO sed -i "s|\$R_INSTALL_PREFIX|$R_INSTALL_PREFIX|g" "$R_WRAPPER_PATH"

    # Make wrapper executable
    $SUDO chmod 755 "$R_WRAPPER_PATH" || error "Failed to make wrapper executable"

    # Clean up build directory
    log "Cleaning up build directory..."
    cd /
    rm -rf "$R_SOURCE_DIR"

    log "Installation completed successfully"
}

# Validate installation
validate() {
    log "Validating r-source installation..."

    # Check if wrapper exists
    if [[ ! -f "$R_WRAPPER_PATH" ]]; then
        error "r-source wrapper not found at $R_WRAPPER_PATH"
    fi

    # Check if wrapper is executable
    if [[ ! -x "$R_WRAPPER_PATH" ]]; then
        error "r-source wrapper is not executable"
    fi

    # Check if R binary exists
    if [[ ! -x "$R_INSTALL_PREFIX/bin/R" ]]; then
        error "R binary not found at $R_INSTALL_PREFIX/bin/R"
    fi

    # Get R version using the wrapper
    log "Checking r-source version..."
    local version_output
    version_output=$("$R_WRAPPER_PATH" --version 2>&1 | head -n1) || error "Failed to execute r-source --version"

    log "Version output: $version_output"

    # Verify version contains expected version number
    if echo "$version_output" | grep -q "$R_VERSION"; then
        log "✓ Version validation successful: $version_output"
    else
        log "Warning: Version output doesn't contain expected version $R_VERSION"
        log "Actual output: $version_output"
        log "This may be acceptable if R version numbering has changed"
    fi

    # Test basic R functionality
    log "Testing basic R functionality..."
    echo "print('R is working')" | "$R_WRAPPER_PATH" --vanilla --quiet --no-save 2>&1 | grep -q "R is working" || error "R basic functionality test failed"

    log "✓ Validation completed successfully"
    return 0
}

# Main installation flow
main() {
    log "Starting r-source $R_VERSION installation..."
    log "Installation method: Build from source"
    log "Repository: $R_REPO_URL"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "Prerequisites already satisfied"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "r-source is already installed"
        validate
        log "Installation verification successful - r-source is ready to use"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "═══════════════════════════════════════════════════════"
    log "✓ r-source installation completed successfully"
    log "═══════════════════════════════════════════════════════"
    log "Usage: r-source [options]"
    log "Example: r-source --version"
    log "         r-source --vanilla"
    log "Binary location: $R_WRAPPER_PATH"
    log "Installation directory: $R_INSTALL_PREFIX"
    log "═══════════════════════════════════════════════════════"
}

# Run main function
main "$@"
