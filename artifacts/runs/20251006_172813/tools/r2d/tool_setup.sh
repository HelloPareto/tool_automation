#!/bin/bash
# Installation script for r2d latest
# Following Solutions Team Install Standards

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
TOOL_NAME="r2d"
TOOL_VERSION="latest"
R_VERSION_SHORT="4.3"

# ============================================================================
# Logging
# ============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ============================================================================
# Prerequisite Management
# ============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for R
    if command -v R >/dev/null 2>&1; then
        local r_version
        r_version=$(R --version | head -n1 | grep -oP 'R version \K[0-9.]+' || echo "unknown")
        log "✓ R found (version: ${r_version})"
    else
        log "✗ R not found"
        all_present=false
    fi

    # Check for Rscript
    if command -v Rscript >/dev/null 2>&1; then
        log "✓ Rscript found"
    else
        log "✗ Rscript not found"
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
    log "Installing prerequisites..."

    # Update package list
    log "Updating package lists..."
    apt-get update -qq

    # Install dependencies for R
    log "Installing R dependencies..."
    apt-get install -y \
        dirmngr \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        gfortran \
        g++ \
        make

    # Add CRAN repository GPG key
    log "Adding CRAN repository GPG key..."
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | \
        gpg --dearmor -o /usr/share/keyrings/cran-archive-keyring.gpg

    # Add CRAN repository
    log "Adding CRAN repository..."
    local ubuntu_codename
    ubuntu_codename=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] https://cloud.r-project.org/bin/linux/ubuntu ${ubuntu_codename}-cran40/" | \
        tee /etc/apt/sources.list.d/cran.list

    # Update package list with new repository
    log "Updating package lists with CRAN repository..."
    apt-get update -qq

    # Install R
    log "Installing R ${R_VERSION_SHORT}..."
    apt-get install -y --no-install-recommends r-base r-base-dev

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify R installation
    if ! command -v R >/dev/null 2>&1; then
        error "R installation verification failed: R command not found"
        exit 1
    fi

    local r_version
    r_version=$(R --version | head -n1 | grep -oP 'R version \K[0-9.]+' || echo "unknown")
    log "✓ R verified (version: ${r_version})"

    # Verify Rscript
    if ! command -v Rscript >/dev/null 2>&1; then
        error "Rscript installation verification failed: Rscript command not found"
        exit 1
    fi
    log "✓ Rscript verified"

    # Test R can execute commands
    if ! Rscript -e "cat('R is working\n')" >/dev/null 2>&1; then
        error "R execution test failed"
        exit 1
    fi
    log "✓ R execution test passed"

    log "All prerequisites verified successfully"
}

# ============================================================================
# Installation Check (Idempotency)
# ============================================================================

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if r2dii.analysis package is installed
    if Rscript -e "if (!requireNamespace('r2dii.analysis', quietly = TRUE)) quit(status = 1)" 2>/dev/null; then
        local installed_version
        installed_version=$(Rscript -e "cat(as.character(packageVersion('r2dii.analysis')))" 2>/dev/null || echo "unknown")
        log "✓ r2dii.analysis package already installed (version: ${installed_version})"

        # Check if r2d command exists
        if [ -f /usr/local/bin/r2d ]; then
            log "✓ r2d command wrapper already exists"
            return 0
        else
            log "r2dii.analysis package is installed but r2d wrapper is missing, will create it"
            return 1
        fi
    else
        log "r2dii.analysis package not found"
        return 1
    fi
}

# ============================================================================
# Tool Installation
# ============================================================================

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Install r2dii.analysis package from CRAN
    log "Installing r2dii.analysis package from CRAN..."
    Rscript -e "install.packages('r2dii.analysis', repos='https://cloud.r-project.org/', dependencies=TRUE, clean=TRUE)"

    if ! Rscript -e "if (!requireNamespace('r2dii.analysis', quietly = TRUE)) quit(status = 1)" 2>/dev/null; then
        error "Failed to install r2dii.analysis package"
        exit 1
    fi

    local installed_version
    installed_version=$(Rscript -e "cat(as.character(packageVersion('r2dii.analysis')))" 2>/dev/null || echo "unknown")
    log "✓ r2dii.analysis package installed (version: ${installed_version})"

    # Create command wrapper for r2d
    log "Creating r2d command wrapper..."
    cat > /usr/local/bin/r2d << 'EOF'
#!/bin/bash
# r2d command wrapper for r2dii.analysis R package

if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    Rscript -e "cat('r2dii.analysis version:', as.character(packageVersion('r2dii.analysis')), '\n')"
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "r2d - R2DII Analysis Tool"
    echo ""
    echo "Usage: r2d [options]"
    echo ""
    echo "Options:"
    echo "  --version, -v    Show version information"
    echo "  --help, -h       Show this help message"
    echo "  --interactive    Start R with r2dii.analysis loaded"
    echo ""
    echo "This is a wrapper for the r2dii.analysis R package."
    echo "For detailed documentation, visit: https://github.com/RMI-PACTA/r2dii.analysis"
    exit 0
elif [ "$1" = "--interactive" ]; then
    Rscript -e "library(r2dii.analysis); cat('r2dii.analysis loaded. Type ?r2dii.analysis for help.\n')"
    exit 0
else
    echo "r2d - R2DII Analysis Tool"
    echo "Use --help for usage information"
    exit 0
fi
EOF

    chmod 755 /usr/local/bin/r2d
    log "✓ r2d command wrapper created at /usr/local/bin/r2d"

    log "${TOOL_NAME} ${TOOL_VERSION} installed successfully"
}

# ============================================================================
# Validation
# ============================================================================

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if r2d command exists and is executable
    if [ ! -x /usr/local/bin/r2d ]; then
        error "Validation failed: r2d command not found or not executable at /usr/local/bin/r2d"
        exit 1
    fi
    log "✓ r2d command exists and is executable"

    # Run version command
    local version_output
    if ! version_output=$(r2d --version 2>&1); then
        error "Validation failed: r2d --version command failed"
        error "Output: ${version_output}"
        exit 1
    fi

    log "✓ r2d --version output: ${version_output}"

    # Verify r2dii.analysis package can be loaded
    if ! Rscript -e "library(r2dii.analysis)" >/dev/null 2>&1; then
        error "Validation failed: Cannot load r2dii.analysis package in R"
        exit 1
    fi
    log "✓ r2dii.analysis package can be loaded in R"

    log "Validation completed successfully"
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "${TOOL_NAME} is already installed, validating..."
        validate
        log "Installation is current and valid"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# Run main function
main "$@"
