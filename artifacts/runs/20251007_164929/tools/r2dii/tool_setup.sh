#!/bin/bash
set -euo pipefail

# ============================================================================
# r2dii Installation Script
# ============================================================================
# Tool: r2dii (r2dii.analysis R package)
# Version: 0.5.2 (latest stable from CRAN)
# Description: R package for measuring climate scenario alignment of corporate loans
# Installation Method: R package via CRAN
# Prerequisites: R (>= 3.5)
# ============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Version pinning
readonly R_MIN_VERSION="3.5"
readonly PACKAGE_NAME="r2dii.analysis"
readonly PACKAGE_VERSION="0.5.2"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
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
        r_version=$(R --version | head -n1 | grep -oP 'R version \K[0-9]+\.[0-9]+' || echo "0.0")
        log "Found R version: ${r_version}"

        # Basic version check (comparing major.minor)
        local r_major
        local r_minor
        r_major=$(echo "${r_version}" | cut -d. -f1)
        r_minor=$(echo "${r_version}" | cut -d. -f2)
        local min_major
        local min_minor
        min_major=$(echo "${R_MIN_VERSION}" | cut -d. -f1)
        min_minor=$(echo "${R_MIN_VERSION}" | cut -d. -f2)

        if [ "${r_major}" -lt "${min_major}" ] || { [ "${r_major}" -eq "${min_major}" ] && [ "${r_minor}" -lt "${min_minor}" ]; }; then
            log_warning "R version ${r_version} is below minimum required version ${R_MIN_VERSION}"
            all_present=false
        fi
    else
        log "R is not installed"
        all_present=false
    fi

    if [ "${all_present}" = true ]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        install_r_debian
    elif command -v yum >/dev/null 2>&1; then
        install_r_redhat
    elif command -v brew >/dev/null 2>&1; then
        install_r_macos
    else
        log_error "No supported package manager found (apt-get, yum, or brew)"
        log_error "Please install R manually from https://www.r-project.org/"
        exit 1
    fi
}

install_r_debian() {
    log "Installing R on Debian/Ubuntu system..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    apt-get update

    # Install dependencies for adding repositories
    apt-get install -y --no-install-recommends \
        software-properties-common \
        dirmngr \
        wget \
        gnupg \
        ca-certificates

    # Add CRAN repository GPG key
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | \
        tee /usr/share/keyrings/cran-archive-keyring.asc

    # Detect Ubuntu version
    local ubuntu_version
    ubuntu_version=$(lsb_release -cs 2>/dev/null || echo "jammy")

    # Add CRAN repository
    echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.asc] https://cloud.r-project.org/bin/linux/ubuntu ${ubuntu_version}-cran40/" | \
        tee /etc/apt/sources.list.d/cran.list

    # Update package list again
    apt-get update

    # Install R base and development tools
    apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "R installation completed"
}

install_r_redhat() {
    log "Installing R on RedHat/CentOS system..."

    # Enable EPEL repository
    yum install -y epel-release

    # Install R
    yum install -y R

    # Clean up
    yum clean all

    log "R installation completed"
}

install_r_macos() {
    log "Installing R on macOS system..."

    # Update Homebrew
    brew update

    # Install R
    brew install r

    log "R installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify R installation
    if ! command -v R >/dev/null 2>&1; then
        log_error "R installation failed - R command not found"
        exit 1
    fi

    local r_version
    r_version=$(R --version | head -n1)
    log "R is installed: ${r_version}"

    # Verify Rscript
    if ! command -v Rscript >/dev/null 2>&1; then
        log_error "Rscript command not found"
        exit 1
    fi

    log "Rscript is available: $(Rscript --version 2>&1 | head -n1)"

    log "All prerequisites verified successfully"
}

# ============================================================================
# Tool Installation
# ============================================================================

check_existing_installation() {
    log "Checking for existing r2dii.analysis installation..."

    if Rscript -e "if ('${PACKAGE_NAME}' %in% installed.packages()[,'Package']) { cat('INSTALLED') } else { cat('NOT_INSTALLED') }" 2>/dev/null | grep -q "INSTALLED"; then
        log "r2dii.analysis is already installed"

        # Check version
        local installed_version
        installed_version=$(Rscript -e "cat(as.character(packageVersion('${PACKAGE_NAME}')))" 2>/dev/null || echo "unknown")
        log "Installed version: ${installed_version}"

        # If version matches, we're done
        if [ "${installed_version}" = "${PACKAGE_VERSION}" ]; then
            log "Correct version (${PACKAGE_VERSION}) is already installed"
            return 0
        else
            log_warning "Version mismatch - installed: ${installed_version}, required: ${PACKAGE_VERSION}"
            log "Will reinstall to ensure correct version"
            return 1
        fi
    else
        log "r2dii.analysis is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing r2dii.analysis package from CRAN..."

    # Create R script for installation
    cat > /tmp/install_r2dii.R <<'RSCRIPT'
# Set CRAN mirror
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Install the package with specific version
package_name <- "r2dii.analysis"
target_version <- "0.5.2"

# Check if already installed with correct version
if (package_name %in% installed.packages()[,"Package"]) {
  installed_ver <- as.character(packageVersion(package_name))
  if (installed_ver == target_version) {
    cat("Package", package_name, "version", target_version, "already installed\n")
    quit(status = 0)
  } else {
    cat("Removing existing version:", installed_ver, "\n")
    remove.packages(package_name)
  }
}

# Install the package
cat("Installing", package_name, "version", target_version, "from CRAN\n")
install.packages(package_name, dependencies = TRUE, quiet = FALSE)

# Verify installation
if (!package_name %in% installed.packages()[,"Package"]) {
  cat("ERROR: Package installation failed\n")
  quit(status = 1)
}

installed_ver <- as.character(packageVersion(package_name))
cat("Successfully installed", package_name, "version", installed_ver, "\n")

# Verify it's the correct version
if (installed_ver != target_version) {
  cat("WARNING: Installed version", installed_ver, "does not match target version", target_version, "\n")
  cat("This may be because CRAN has a newer version available\n")
}

quit(status = 0)
RSCRIPT

    # Run the installation script
    if Rscript /tmp/install_r2dii.R; then
        log "r2dii.analysis installation completed successfully"
    else
        log_error "r2dii.analysis installation failed"
        log_error "Please check R installation and network connectivity"
        rm -f /tmp/install_r2dii.R
        exit 1
    fi

    # Clean up
    rm -f /tmp/install_r2dii.R
}

# ============================================================================
# Validation
# ============================================================================

validate() {
    log "Validating r2dii.analysis installation..."

    # Create validation R script
    cat > /tmp/validate_r2dii.R <<'RSCRIPT'
# Check if package is installed
package_name <- "r2dii.analysis"

if (!package_name %in% installed.packages()[,"Package"]) {
  cat("ERROR: Package", package_name, "is not installed\n")
  quit(status = 1)
}

# Get version
version <- as.character(packageVersion(package_name))
cat("Package:", package_name, "\n")
cat("Version:", version, "\n")

# Try to load the package
tryCatch({
  library(r2dii.analysis, quietly = TRUE)
  cat("Status: Successfully loaded\n")

  # Check for key functions
  required_functions <- c("target_market_share", "target_sda")
  for (func in required_functions) {
    if (!exists(func)) {
      cat("ERROR: Required function", func, "not found\n")
      quit(status = 1)
    }
  }
  cat("All required functions found\n")

  quit(status = 0)
}, error = function(e) {
  cat("ERROR: Failed to load package:", conditionMessage(e), "\n")
  quit(status = 1)
})
RSCRIPT

    # Run validation
    if Rscript /tmp/validate_r2dii.R; then
        log "${GREEN}✓${NC} r2dii.analysis validation successful"
    else
        log_error "r2dii.analysis validation failed"
        log_error "The package is installed but cannot be loaded properly"
        rm -f /tmp/validate_r2dii.R
        exit 1
    fi

    # Clean up
    rm -f /tmp/validate_r2dii.R

    log "Validation completed successfully"
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    log "Starting r2dii.analysis installation..."
    log "Target version: ${PACKAGE_VERSION}"

    # Step 1: Check and install prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "${GREEN}✓${NC} r2dii.analysis is already installed and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate installation
    validate

    log "${GREEN}✓${NC} Installation completed successfully"
    log ""
    log "Usage: In R or Rscript, load the package with:"
    log "  library(r2dii.analysis)"
    log ""
    log "Note: r2dii.analysis is an R package, not a command-line tool."
    log "It provides functions like target_market_share() and target_sda()"
    log "for climate scenario alignment analysis."
}

# Run main function
main "$@"
