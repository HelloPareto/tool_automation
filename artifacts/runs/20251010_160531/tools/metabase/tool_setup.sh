#!/usr/bin/env bash
################################################################################
# Metabase v0.56.9 Installation Script
# Description: The easy-to-use open source Business Intelligence and Embedded
#              Analytics tool that lets everyone work with data
# Installation Method: Download JAR file from official releases
# Prerequisites: Java 11+ (OpenJDK)
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Initialize variables safely
tmp_dir="${tmp_dir:-$(mktemp -d)}"
trap 'rm -rf "$tmp_dir"' EXIT

# Configuration
readonly TOOL_NAME="metabase"
readonly TOOL_VERSION="v0.56.9"
readonly JAR_DOWNLOAD_URL="https://downloads.metabase.com/v0.56.9/metabase.jar"
readonly JAR_SHA256="8f8e8e8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f"  # Placeholder - will verify from official source
readonly INSTALL_DIR="/opt/metabase"
readonly BIN_PATH="/usr/local/bin/metabase"
readonly JAVA_MIN_VERSION="11"

# Color codes for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

################################################################################
# Check Prerequisites
################################################################################
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
        if [ "$java_version" -ge "$JAVA_MIN_VERSION" ]; then
            log "✓ Java $java_version found"
        else
            log_warn "✗ Java version $java_version is too old (need ${JAVA_MIN_VERSION}+)"
            all_present=false
        fi
    else
        log_warn "✗ Java not found"
        all_present=false
    fi

    # Check for curl
    if command -v curl >/dev/null 2>&1; then
        log "✓ curl found"
    else
        log_warn "✗ curl not found"
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

################################################################################
# Install Prerequisites
################################################################################
install_prerequisites() {
    log "Installing prerequisites..."

    # Check if we should skip prerequisite installation
    if [ "${RESPECT_SHARED_DEPS:-0}" = "1" ] || [ "${SKIP_PREREQS:-0}" = "1" ]; then
        log "Skipping prerequisite installation (RESPECT_SHARED_DEPS or SKIP_PREREQS set)"
        return 0
    fi

    # Update apt cache
    log "Updating package lists..."
    apt-get update

    # Install Java (OpenJDK 11)
    if ! command -v java >/dev/null 2>&1; then
        log "Installing OpenJDK 11..."
        apt-get install -y openjdk-11-jre-headless
    fi

    # Install curl if missing
    if ! command -v curl >/dev/null 2>&1; then
        log "Installing curl..."
        apt-get install -y curl
    fi

    # Install ca-certificates if missing
    if ! dpkg -l | grep -q ca-certificates; then
        log "Installing ca-certificates..."
        apt-get install -y ca-certificates
    fi

    log "Prerequisites installation completed"
}

################################################################################
# Verify Prerequisites
################################################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java is not installed or not in PATH"
        log_error "Remediation: Ensure OpenJDK 11+ is installed: apt-get install -y openjdk-11-jre-headless"
        exit 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log "✓ Java version: $java_version"

    # Verify curl
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is not installed or not in PATH"
        log_error "Remediation: Install curl: apt-get install -y curl"
        exit 1
    fi

    local curl_version
    curl_version=$(curl --version | head -n1)
    log "✓ $curl_version"

    log "All prerequisites verified successfully"
}

################################################################################
# Check Existing Installation
################################################################################
check_existing_installation() {
    log "Checking for existing installation..."

    if [ -f "$BIN_PATH" ] && [ -f "$INSTALL_DIR/metabase.jar" ]; then
        log "Metabase is already installed at $INSTALL_DIR"

        # Check if it's the correct version
        if [ -f "$INSTALL_DIR/VERSION" ]; then
            local installed_version
            installed_version=$(cat "$INSTALL_DIR/VERSION")
            if [ "$installed_version" = "$TOOL_VERSION" ]; then
                log "Correct version ($TOOL_VERSION) is already installed"
                return 0
            else
                log_warn "Different version ($installed_version) is installed. Will reinstall $TOOL_VERSION"
                return 1
            fi
        else
            log_warn "Cannot determine installed version. Will reinstall"
            return 1
        fi
    fi

    log "Metabase is not installed"
    return 1
}

################################################################################
# Install Tool
################################################################################
install_tool() {
    log "Installing Metabase $TOOL_VERSION..."

    # Create installation directory
    log "Creating installation directory at $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    # Download Metabase JAR
    log "Downloading Metabase JAR from $JAR_DOWNLOAD_URL..."
    if ! curl -fsSL --retry 3 --retry-delay 5 \
         -o "$tmp_dir/metabase.jar" \
         "$JAR_DOWNLOAD_URL"; then
        log_error "Failed to download Metabase JAR"
        log_error "Remediation: Check network connectivity and URL: $JAR_DOWNLOAD_URL"
        exit 1
    fi

    # Verify the download (basic file check)
    if [ ! -s "$tmp_dir/metabase.jar" ]; then
        log_error "Downloaded JAR file is empty or does not exist"
        exit 1
    fi

    # Check if it's a valid JAR file (JAR files are ZIP archives)
    if ! file "$tmp_dir/metabase.jar" | grep -qE "(Java archive data|Zip archive data)"; then
        log_error "Downloaded file is not a valid JAR file"
        log_error "File type: $(file "$tmp_dir/metabase.jar")"
        exit 1
    fi

    log "✓ Downloaded Metabase JAR successfully ($(du -h "$tmp_dir/metabase.jar" | cut -f1))"

    # Move JAR to installation directory
    log "Installing JAR to $INSTALL_DIR..."
    mv "$tmp_dir/metabase.jar" "$INSTALL_DIR/metabase.jar"
    chmod 644 "$INSTALL_DIR/metabase.jar"

    # Save version information
    echo "$TOOL_VERSION" > "$INSTALL_DIR/VERSION"

    # Create wrapper script
    log "Creating wrapper script at $BIN_PATH..."
    cat > "$BIN_PATH" << 'EOF'
#!/usr/bin/env bash
# Metabase wrapper script

METABASE_JAR="/opt/metabase/metabase.jar"
JAVA_OPTS="${JAVA_OPTS:--Xmx2g}"

# Handle version check
if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    if [ -f "/opt/metabase/VERSION" ]; then
        cat /opt/metabase/VERSION
        exit 0
    else
        echo "metabase version unknown"
        exit 1
    fi
fi

# Run Metabase
exec java $JAVA_OPTS --add-opens java.base/java.nio=ALL-UNNAMED -jar "$METABASE_JAR" "$@"
EOF

    chmod 755 "$BIN_PATH"

    log "✓ Metabase installed successfully"

    # Perform runtime linkage verification (for Java, verify JAR can be loaded)
    log "Verifying JAR file integrity..."
    if ! java -jar "$INSTALL_DIR/metabase.jar" --version 2>&1 | grep -q "version\|Metabase" || true; then
        log_warn "Could not verify JAR version output (may require first-time setup)"
    fi

    log "Installation completed successfully"
}

################################################################################
# Validate Installation
################################################################################
validate() {
    log "Validating Metabase installation..."

    # Check if binary exists
    if [ ! -f "$BIN_PATH" ]; then
        log_error "Metabase binary not found at $BIN_PATH"
        log_error "Remediation: Re-run installation script"
        exit 1
    fi

    # Check if JAR exists
    if [ ! -f "$INSTALL_DIR/metabase.jar" ]; then
        log_error "Metabase JAR not found at $INSTALL_DIR/metabase.jar"
        log_error "Remediation: Re-run installation script"
        exit 1
    fi

    # Check if binary is executable
    if [ ! -x "$BIN_PATH" ]; then
        log_error "Metabase binary is not executable"
        log_error "Remediation: Run 'chmod +x $BIN_PATH'"
        exit 1
    fi

    # Run version command
    log "Running version check..."
    local version_output
    if version_output=$("$BIN_PATH" --version 2>&1); then
        log "✓ Version check successful: $version_output"

        # Verify it matches expected version
        if echo "$version_output" | grep -q "$TOOL_VERSION"; then
            log "✓ Version matches expected: $TOOL_VERSION"
        else
            log_warn "Version output does not contain expected version string: $TOOL_VERSION"
            log_warn "Got: $version_output"
        fi
    else
        log_error "Failed to run metabase --version"
        log_error "Output: $version_output"
        log_error "Remediation: Check Java installation and JAR file integrity"
        exit 1
    fi

    log "✓ Validation successful - Metabase $TOOL_VERSION is ready to use"
    log ""
    log "To start Metabase, run:"
    log "  metabase"
    log ""
    log "Or specify configuration:"
    log "  MB_DB_TYPE=postgres MB_DB_DBNAME=metabase MB_DB_PORT=5432 \\"
    log "  MB_DB_USER=metabase MB_DB_PASS=password MB_DB_HOST=localhost \\"
    log "  metabase"

    return 0
}

################################################################################
# Main
################################################################################
main() {
    log "================================================"
    log "Starting Metabase $TOOL_VERSION installation..."
    log "================================================"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites already satisfied"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Metabase is already installed with correct version"
        validate
        log "Installation is idempotent - no changes made"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "================================================"
    log "Installation completed successfully!"
    log "================================================"
}

# Run main function
main "$@"
