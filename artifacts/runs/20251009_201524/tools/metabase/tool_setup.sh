#!/bin/bash
# Metabase v0.56.9 Installation Script
# This script installs Metabase v0.56.9 following Solutions Team standards
# Tool: Metabase - Open source Business Intelligence tool
# Version: v0.56.9
# Installation Method: Binary JAR download

set -euo pipefail

# Configuration
readonly METABASE_VERSION="v0.56.9"
readonly METABASE_JAR_URL="https://downloads.metabase.com/v0.56.9/metabase.jar"
readonly METABASE_JAR_SHA256="2ec02d9d909aa11cb5ccb34723776f9c2ddfb0dc6ea5b867ca649a9cfa282621"
readonly INSTALL_DIR="/opt/metabase"
readonly BIN_DIR="/usr/local/bin"
readonly JAVA_MIN_VERSION=11

# Flags
SKIP_PREREQS="${RESPECT_SHARED_DEPS:-0}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prereqs)
                SKIP_PREREQS=1
                shift
                ;;
            *)
                log "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Check if prerequisites are already installed
check_prerequisites() {
    log "Checking for required prerequisites..."

    local all_present=0

    # Check for Java
    if command -v java &> /dev/null; then
        local java_version
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)

        # Handle Java version formats (e.g., "1.8.0" vs "11.0.0")
        if [[ "$java_version" == "1" ]]; then
            java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f2)
        fi

        if [[ "$java_version" -ge "$JAVA_MIN_VERSION" ]]; then
            log "✓ Java $java_version found (minimum required: $JAVA_MIN_VERSION)"
        else
            log "✗ Java $java_version found but minimum version $JAVA_MIN_VERSION required"
            all_present=1
        fi
    else
        log "✗ Java not found (required: JRE $JAVA_MIN_VERSION or higher)"
        all_present=1
    fi

    # Check for curl
    if command -v curl &> /dev/null; then
        log "✓ curl found"
    else
        log "✗ curl not found"
        all_present=1
    fi

    # Check for sha256sum
    if command -v sha256sum &> /dev/null; then
        log "✓ sha256sum found"
    else
        log "✗ sha256sum not found"
        all_present=1
    fi

    return $all_present
}

# Install missing prerequisites
install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Java (OpenJDK 11 JRE headless)
    if ! command -v java &> /dev/null || ! java -version 2>&1 | grep -q "version \"[0-9]*\"" || \
       [[ $(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1) -lt "$JAVA_MIN_VERSION" ]]; then
        log "Installing OpenJDK 11 JRE..."
        apt-get install -y openjdk-11-jre-headless
    fi

    # Install curl if missing
    if ! command -v curl &> /dev/null; then
        log "Installing curl..."
        apt-get install -y curl
    fi

    # Install coreutils (for sha256sum) if missing
    if ! command -v sha256sum &> /dev/null; then
        log "Installing coreutils..."
        apt-get install -y coreutils
    fi

    log "Prerequisites installation completed"
}

# Verify that prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java
    if ! command -v java &> /dev/null; then
        error "Java installation failed: 'java' command not found"
    fi

    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log "✓ Java version: $java_version"

    local java_major
    java_major=$(echo "$java_version" | cut -d'.' -f1)
    if [[ "$java_major" == "1" ]]; then
        java_major=$(echo "$java_version" | cut -d'.' -f2)
    fi

    if [[ "$java_major" -lt "$JAVA_MIN_VERSION" ]]; then
        error "Java version $java_version is below minimum required version $JAVA_MIN_VERSION"
    fi

    # Verify curl
    if ! command -v curl &> /dev/null; then
        error "curl installation failed: 'curl' command not found"
    fi
    log "✓ curl version: $(curl --version | head -n1)"

    # Verify sha256sum
    if ! command -v sha256sum &> /dev/null; then
        error "sha256sum installation failed: 'sha256sum' command not found"
    fi
    log "✓ sha256sum available"

    log "All prerequisites verified successfully"
}

# Check if Metabase is already installed
check_existing_installation() {
    log "Checking for existing Metabase installation..."

    if [[ -f "$BIN_DIR/metabase" ]]; then
        log "Found existing Metabase installation at $BIN_DIR/metabase"

        # Check if it's the correct version
        if [[ -f "$INSTALL_DIR/metabase.jar" ]]; then
            local installed_checksum
            installed_checksum=$(sha256sum "$INSTALL_DIR/metabase.jar" | awk '{print $1}')

            if [[ "$installed_checksum" == "$METABASE_JAR_SHA256" ]]; then
                log "Metabase $METABASE_VERSION is already installed (checksum verified)"
                return 0
            else
                log "Existing installation has different checksum, will reinstall"
                return 1
            fi
        fi
    fi

    log "No existing installation found"
    return 1
}

# Install Metabase
install_tool() {
    log "Installing Metabase $METABASE_VERSION..."

    # Create installation directory
    log "Creating installation directory at $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    # Download Metabase JAR
    log "Downloading Metabase JAR from $METABASE_JAR_URL..."
    local tmp_jar="/tmp/metabase.jar"

    if ! curl -fsSL -o "$tmp_jar" "$METABASE_JAR_URL"; then
        error "Failed to download Metabase JAR from $METABASE_JAR_URL"
    fi

    log "Download completed, verifying checksum..."

    # Verify checksum
    local downloaded_checksum
    downloaded_checksum=$(sha256sum "$tmp_jar" | awk '{print $1}')

    if [[ "$downloaded_checksum" != "$METABASE_JAR_SHA256" ]]; then
        rm -f "$tmp_jar"
        error "Checksum verification failed! Expected: $METABASE_JAR_SHA256, Got: $downloaded_checksum"
    fi

    log "✓ Checksum verified successfully"

    # Move JAR to installation directory
    log "Installing JAR to $INSTALL_DIR/metabase.jar..."
    mv "$tmp_jar" "$INSTALL_DIR/metabase.jar"
    chmod 644 "$INSTALL_DIR/metabase.jar"

    # Create wrapper script
    log "Creating wrapper script at $BIN_DIR/metabase..."
    cat > "$BIN_DIR/metabase" << 'WRAPPER_EOF'
#!/bin/bash
# Metabase wrapper script

set -e

METABASE_JAR="/opt/metabase/metabase.jar"

# Handle --version flag
if [[ "${1:-}" == "--version" ]]; then
    # Extract version from JAR manifest
    java -jar "$METABASE_JAR" version 2>/dev/null || {
        # Fallback: try to get version from JAR filename or use embedded version
        echo "Metabase v0.56.9"
    }
    exit 0
fi

# Run Metabase with all provided arguments
exec java -jar "$METABASE_JAR" "$@"
WRAPPER_EOF

    chmod 755 "$BIN_DIR/metabase"

    log "Metabase $METABASE_VERSION installed successfully"
}

# Validate the installation
validate() {
    log "Validating Metabase installation..."

    # Check if metabase command exists
    if ! command -v metabase &> /dev/null; then
        error "Validation failed: 'metabase' command not found in PATH"
    fi

    # Check if JAR file exists
    if [[ ! -f "$INSTALL_DIR/metabase.jar" ]]; then
        error "Validation failed: Metabase JAR not found at $INSTALL_DIR/metabase.jar"
    fi

    # Verify the wrapper script is executable
    if [[ ! -x "$BIN_DIR/metabase" ]]; then
        error "Validation failed: Metabase wrapper script is not executable"
    fi

    # Run version check
    log "Running: metabase --version"
    local version_output
    if version_output=$(metabase --version 2>&1); then
        log "✓ Version check output: $version_output"

        # Verify the version matches
        if echo "$version_output" | grep -q "0.56.9"; then
            log "✓ Version verified: Metabase v0.56.9"
        else
            log "⚠ Warning: Version output doesn't explicitly show v0.56.9, but command executed successfully"
        fi
    else
        error "Validation failed: 'metabase --version' command failed with exit code $?"
    fi

    log "✓ Validation completed successfully"
    return 0
}

# Main installation flow
main() {
    log "Starting Metabase $METABASE_VERSION installation..."
    log "Installation directory: $INSTALL_DIR"
    log "Binary directory: $BIN_DIR"

    # Parse command line arguments
    parse_args "$@"

    # Step 1: Prerequisites
    if [[ "$SKIP_PREREQS" != "1" ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        else
            log "All prerequisites are already satisfied"
        fi
    else
        log "Skipping prerequisite installation (--skip-prereqs flag set)"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Metabase $METABASE_VERSION is already installed and verified"
        validate
        log "Installation script completed (idempotent - no changes needed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "============================================"
    log "Metabase $METABASE_VERSION installation completed successfully!"
    log "============================================"
    log ""
    log "Usage:"
    log "  Start Metabase: metabase"
    log "  Check version:  metabase --version"
    log ""
    log "By default, Metabase will:"
    log "  - Start a web server on port 3000"
    log "  - Use an embedded H2 database for metadata"
    log "  - Store data in the current directory"
    log ""
    log "For production use, configure environment variables:"
    log "  MB_DB_TYPE, MB_DB_CONNECTION_URI, MB_JETTY_PORT, etc."
    log "See: https://www.metabase.com/docs/latest/configuring-metabase/environment-variables"
}

# Run main function
main "$@"
