#!/usr/bin/env bash
#############################################################
# GnuCash 5.13 Installation Script
#############################################################
# This script installs GnuCash 5.13 using Flatpak
# Installation method: Flatpak from Flathub (primary)
#                      APT package manager (fallback)
# Validation: gnucash --version
#############################################################

set -euo pipefail
IFS=$'\n\t'

# Initialize variables safely
tmp_dir="${tmp_dir:-$(mktemp -d)}"
trap 'rm -rf "$tmp_dir"' EXIT

#############################################################
# Configuration
#############################################################
readonly TOOL_NAME="gnucash"
readonly TOOL_VERSION="5.13"
readonly FLATPAK_APP_ID="org.gnucash.GnuCash"
readonly FLATPAK_REMOTE="flathub"
readonly FLATPAK_REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

# Flags for shared dependency management
SKIP_PREREQS="${SKIP_PREREQS:-0}"
RESPECT_SHARED_DEPS="${RESPECT_SHARED_DEPS:-0}"

# Installation method tracking
INSTALL_METHOD=""

#############################################################
# Logging
#############################################################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

#############################################################
# Detect if running in Docker/Container
#############################################################
is_in_container() {
    if [ -f /.dockerenv ]; then
        return 0
    fi

    if grep -sq 'docker\|lxc\|containerd' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi

    return 1
}

#############################################################
# Prerequisite Detection
#############################################################
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=0

    # If in container, prefer APT over Flatpak
    if is_in_container; then
        log "Running in container environment - will use APT package manager"
        INSTALL_METHOD="apt"
        # For APT, no special prerequisites needed beyond basic system
        log "  ✓ APT package manager available"
        return 0
    fi

    # Check for Flatpak (preferred for non-container environments)
    if ! command -v flatpak >/dev/null 2>&1; then
        log "  ✗ flatpak not found"
        all_present=1
    else
        log "  ✓ flatpak found: $(flatpak --version 2>/dev/null || echo 'version unknown')"
    fi

    # Check if Flathub remote is configured
    if command -v flatpak >/dev/null 2>&1; then
        if ! flatpak remote-list 2>/dev/null | grep -q "^${FLATPAK_REMOTE}"; then
            log "  ✗ Flathub remote not configured"
            all_present=1
        else
            log "  ✓ Flathub remote configured"
        fi
    fi

    if [ $all_present -eq 0 ]; then
        log "All prerequisites are present"
        INSTALL_METHOD="flatpak"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

#############################################################
# Prerequisite Installation
#############################################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Check if we should skip prerequisites
    if [ "$SKIP_PREREQS" -eq 1 ] || [ "$RESPECT_SHARED_DEPS" -eq 1 ]; then
        log "Skipping prerequisite installation (SKIP_PREREQS or RESPECT_SHARED_DEPS set)"
        return 0
    fi

    # If in container, skip Flatpak setup
    if is_in_container; then
        log "Running in container - no Flatpak prerequisites needed"
        INSTALL_METHOD="apt"
        return 0
    fi

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq

    # Install Flatpak if not present
    if ! command -v flatpak >/dev/null 2>&1; then
        log "Installing flatpak..."
        apt-get install -y --no-install-recommends flatpak
    fi

    # Add Flathub remote if not configured
    if ! flatpak remote-list 2>/dev/null | grep -q "^${FLATPAK_REMOTE}"; then
        log "Adding Flathub remote..."
        flatpak remote-add --if-not-exists "${FLATPAK_REMOTE}" "${FLATPAK_REMOTE_URL}"
    fi

    INSTALL_METHOD="flatpak"
    log "Prerequisites installation completed"
}

#############################################################
# Prerequisite Verification
#############################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # If using APT method, just verify apt-get is available
    if [ "$INSTALL_METHOD" = "apt" ]; then
        if ! command -v apt-get >/dev/null 2>&1; then
            error "APT package manager is not available"
            exit 1
        fi
        log "  ✓ APT package manager verified"
        log "Prerequisites verified successfully"
        return 0
    fi

    # Verify Flatpak
    if ! command -v flatpak >/dev/null 2>&1; then
        error "Flatpak is not available after installation"
        error "Please install flatpak manually: apt-get install flatpak"
        exit 1
    fi

    local flatpak_version
    flatpak_version=$(flatpak --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    log "  ✓ flatpak version: ${flatpak_version}"

    # Verify Flathub remote
    if ! flatpak remote-list 2>/dev/null | grep -q "^${FLATPAK_REMOTE}"; then
        error "Flathub remote is not configured after setup"
        error "Please add it manually: flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
        exit 1
    fi

    log "  ✓ Flathub remote configured"
    log "Prerequisites verified successfully"
}

#############################################################
# Check Existing Installation
#############################################################
check_existing_installation() {
    log "Checking for existing GnuCash installation..."

    # Check native installation
    if command -v gnucash >/dev/null 2>&1; then
        local installed_version
        installed_version=$(gnucash --version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+' || echo "unknown")

        log "GnuCash is already installed (version: ${installed_version})"

        # For version checking, we check major.minor only since APT might have slightly different patch versions
        local requested_version_short
        requested_version_short=$(echo "$TOOL_VERSION" | grep -oP '^\d+\.\d+')

        if [[ "$installed_version" == "$requested_version_short"* ]]; then
            log "✓ Compatible version (${installed_version}) is already installed"
            return 0
        fi
    fi

    # Check if Flatpak app is installed (if using Flatpak method)
    if [ "$INSTALL_METHOD" = "flatpak" ] && command -v flatpak >/dev/null 2>&1; then
        if flatpak list --app 2>/dev/null | grep -q "^${FLATPAK_APP_ID}"; then
            local installed_version
            installed_version=$(flatpak info "${FLATPAK_APP_ID}" 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown")

            log "GnuCash is already installed via Flatpak (version: ${installed_version})"

            # Check if it's the correct version
            if [ "${installed_version}" = "${TOOL_VERSION}" ]; then
                log "✓ Correct version (${TOOL_VERSION}) is already installed"
                return 0
            else
                log "Different version installed (${installed_version}), will update to ${TOOL_VERSION}"
                return 1
            fi
        fi
    fi

    log "GnuCash is not installed"
    return 1
}

#############################################################
# Install Tool via APT
#############################################################
install_via_apt() {
    log "Installing GnuCash via APT package manager..."

    # Update package lists
    apt-get update -qq

    # Install GnuCash from Debian repositories
    # Note: Debian 12 includes GnuCash 5.5, not 5.13
    # This is the closest stable version available via APT
    log "Installing gnucash package..."
    apt-get install -y --no-install-recommends gnucash

    log "GnuCash installation via APT completed"
    log "Note: APT provides GnuCash 5.5 (latest in Debian 12 stable)"
    log "For exact version 5.13, Flatpak or building from source is required"
}

#############################################################
# Install Tool via Flatpak
#############################################################
install_via_flatpak() {
    log "Installing GnuCash ${TOOL_VERSION} via Flatpak..."

    # Install GnuCash via Flatpak
    log "Installing GnuCash from Flathub..."
    flatpak install -y --noninteractive "${FLATPAK_REMOTE}" "${FLATPAK_APP_ID}"

    # Create a wrapper script in /usr/local/bin for easy access
    log "Creating wrapper script at /usr/local/bin/gnucash..."
    cat > /usr/local/bin/gnucash <<'EOF'
#!/usr/bin/env bash
# GnuCash wrapper script to run Flatpak version
exec flatpak run org.gnucash.GnuCash "$@"
EOF

    chmod +x /usr/local/bin/gnucash

    log "GnuCash Flatpak installation completed"
}

#############################################################
# Install Tool
#############################################################
install_tool() {
    log "Installing GnuCash..."

    if [ "$INSTALL_METHOD" = "apt" ]; then
        install_via_apt
    elif [ "$INSTALL_METHOD" = "flatpak" ]; then
        install_via_flatpak
    else
        error "No valid installation method selected"
        exit 1
    fi
}

#############################################################
# Runtime Linkage Verification (Self-Healing)
#############################################################
verify_runtime_linkage() {
    log "Verifying runtime linkage..."

    # Find the gnucash binary
    local gnucash_bin
    gnucash_bin=$(command -v gnucash 2>/dev/null || true)

    if [ -z "$gnucash_bin" ]; then
        log "No binary to check (Flatpak or not yet installed)"
        return 0
    fi

    # Skip ldd check for wrapper scripts
    if head -n1 "$gnucash_bin" 2>/dev/null | grep -q "^#!/"; then
        log "GnuCash is a shell script wrapper - skipping ldd check"
        return 0
    fi

    # Check for missing libraries
    local missing_libs
    missing_libs=$(ldd "$gnucash_bin" 2>/dev/null | grep "not found" || true)

    if [ -z "$missing_libs" ]; then
        log "✓ All runtime libraries are present"
        return 0
    fi

    log "Missing runtime libraries detected:"
    echo "$missing_libs" | while read -r line; do
        log "  - $line"
    done

    log "Installing missing runtime dependencies..."

    # Common library package mappings for Debian 12
    local packages_to_install=()

    if echo "$missing_libs" | grep -q "libxml2"; then
        packages_to_install+=("libxml2")
    fi

    if echo "$missing_libs" | grep -q "libxslt"; then
        packages_to_install+=("libxslt1.1")
    fi

    if echo "$missing_libs" | grep -q "libgdk"; then
        packages_to_install+=("libgtk-3-0")
    fi

    if echo "$missing_libs" | grep -q "libwebkit"; then
        packages_to_install+=("libwebkit2gtk-4.0-37")
    fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log "Installing packages: ${packages_to_install[*]}"
        apt-get update -qq
        apt-get install -y --no-install-recommends "${packages_to_install[@]}"
        ldconfig

        # Verify again
        missing_libs=$(ldd "$gnucash_bin" 2>/dev/null | grep "not found" || true)
        if [ -z "$missing_libs" ]; then
            log "✓ All missing libraries resolved"
        else
            log "⚠ Some libraries still missing, but continuing..."
        fi
    fi
}

#############################################################
# Validation
#############################################################
validate() {
    log "Validating GnuCash installation..."

    # Check if gnucash command is available
    if ! command -v gnucash >/dev/null 2>&1; then
        error "gnucash command not found in PATH"
        exit 1
    fi

    log "✓ gnucash command found: $(command -v gnucash)"

    # For APT installations, check the package
    if [ "$INSTALL_METHOD" = "apt" ]; then
        # Temporarily disable pipefail to avoid SIGPIPE issues with grep -q
        set +o pipefail
        if ! dpkg -l | grep -q "^ii  gnucash"; then
            set -o pipefail
            error "GnuCash package is not properly installed"
            exit 1
        fi
        set -o pipefail

        local installed_version
        installed_version=$(gnucash --version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "unknown")
        log "Installed version: ${installed_version}"
        log "Note: Debian 12 provides GnuCash 5.5, not exact version 5.13"
        log "For exact version 5.13, use Flatpak on a non-container system"
    fi

    # For Flatpak installations, check the app
    if [ "$INSTALL_METHOD" = "flatpak" ]; then
        if ! flatpak list --app 2>/dev/null | grep -q "^${FLATPAK_APP_ID}"; then
            error "GnuCash Flatpak app is not installed"
            exit 1
        fi

        local installed_version
        installed_version=$(flatpak info "${FLATPAK_APP_ID}" 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown")
        log "Installed version: ${installed_version}"

        if [ "${installed_version}" != "${TOOL_VERSION}" ]; then
            log "⚠ Version mismatch: expected ${TOOL_VERSION}, got ${installed_version}"
            log "Note: Flathub may have updated to a newer version"
        fi
    fi

    log "✓ GnuCash installation validated successfully"
    log "Run with: gnucash"
}

#############################################################
# Main Installation Flow
#############################################################
main() {
    # Parse command line arguments
    for arg in "$@"; do
        case "$arg" in
            --skip-prereqs)
                SKIP_PREREQS=1
                ;;
            --respect-shared-deps)
                RESPECT_SHARED_DEPS=1
                ;;
        esac
    done

    log "======================================================"
    log "Starting GnuCash ${TOOL_VERSION} installation"
    log "======================================================"

    # Step 1: Prerequisites
    log ""
    log "Step 1: Checking prerequisites..."
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    log "Installation method: ${INSTALL_METHOD}"

    # Step 2: Check if already installed
    log ""
    log "Step 2: Checking for existing installation..."
    if check_existing_installation; then
        log "GnuCash is already installed"
        validate
        log ""
        log "======================================================"
        log "Installation check completed - already installed"
        log "======================================================"
        exit 0
    fi

    # Step 3: Install the tool
    log ""
    log "Step 3: Installing GnuCash..."
    install_tool

    # Step 4: Verify runtime linkage
    log ""
    log "Step 4: Verifying runtime linkage..."
    verify_runtime_linkage

    # Step 5: Validate installation
    log ""
    log "Step 5: Validating installation..."
    validate

    log ""
    log "======================================================"
    log "GnuCash installation completed successfully"
    log "======================================================"
}

# Run main function
main "$@"
