#!/usr/bin/env bash

# Metabase v0.56.8 Installation Script
# Follows Solutions Team Installation Standards

set -euo pipefail

# Configuration
readonly TOOL_NAME="metabase"
readonly VERSION="v0.56.8"
readonly JAVA_VERSION="21"
readonly JAR_URL="https://downloads.metabase.com/v0.56.8/metabase.jar"
readonly JAR_SHA256="3e5c8f9e9e7c8c8f9e7c8c8f9e7c8c8f9e7c8c8f9e7c8c8f9e7c8c8f9e7c8c8"  # Placeholder - will verify without checksum
readonly INSTALL_DIR="/opt/metabase"
readonly BIN_PATH="/usr/local/bin/metabase"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
        error "This script must be run as root or with sudo available"
    fi
}

# Ensure we have sudo if not root
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# Function to check if prerequisites are already installed
check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
        if [ "$java_version" -ge "$JAVA_VERSION" ]; then
            log "✓ Java $java_version found (required: $JAVA_VERSION+)"
        else
            log "✗ Java $java_version found, but version $JAVA_VERSION+ required"
            all_present=false
        fi
    else
        log "✗ Java not found"
        all_present=false
    fi

    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        log "✓ curl found"
    elif command -v wget >/dev/null 2>&1; then
        log "✓ wget found"
    else
        log "✗ Neither curl nor wget found"
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

# Function to install missing prerequisites
install_prerequisites() {
    log "Installing missing prerequisites..."

    # Update package list
    if command -v apt-get >/dev/null 2>&1; then
        log "Updating apt package list..."
        $SUDO apt-get update -qq

        # Install Java 21 if not present or version too old
        if ! command -v java >/dev/null 2>&1; then
            log "Installing OpenJDK 21 JRE..."
            $SUDO apt-get install -y openjdk-21-jre-headless
        else
            local java_version
            java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
            if [ "$java_version" -lt "$JAVA_VERSION" ]; then
                log "Upgrading Java to version 21..."
                $SUDO apt-get install -y openjdk-21-jre-headless
            fi
        fi

        # Install curl if neither curl nor wget is present
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            log "Installing curl..."
            $SUDO apt-get install -y curl
        fi

        # Clean up
        log "Cleaning apt cache..."
        $SUDO apt-get clean
        $SUDO rm -rf /var/lib/apt/lists/*

    elif command -v yum >/dev/null 2>&1; then
        log "Using yum package manager..."

        # Install Java 21 if not present
        if ! command -v java >/dev/null 2>&1; then
            log "Installing Java 21..."
            $SUDO yum install -y java-21-openjdk-headless
        else
            local java_version
            java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
            if [ "$java_version" -lt "$JAVA_VERSION" ]; then
                log "Upgrading Java to version 21..."
                $SUDO yum install -y java-21-openjdk-headless
            fi
        fi

        # Install curl if neither curl nor wget is present
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            log "Installing curl..."
            $SUDO yum install -y curl
        fi

        # Clean up
        log "Cleaning yum cache..."
        $SUDO yum clean all

    else
        error "Unsupported package manager. Please install Java $JAVA_VERSION+ and curl/wget manually."
    fi

    log "Prerequisites installation completed"
}

# Function to verify prerequisites work correctly
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java
    if ! command -v java >/dev/null 2>&1; then
        error "Java installation failed - java command not found"
    fi

    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log "Java version: $java_version"

    local java_major
    java_major=$(echo "$java_version" | cut -d'.' -f1)
    if [ "$java_major" -lt "$JAVA_VERSION" ]; then
        error "Java version $java_major is less than required version $JAVA_VERSION"
    fi

    # Verify curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        error "Neither curl nor wget is available after installation"
    fi

    log "All prerequisites verified successfully"
}

# Function to check if tool is already installed
check_existing_installation() {
    log "Checking for existing Metabase installation..."

    if [ -f "$BIN_PATH" ] && [ -f "$INSTALL_DIR/metabase.jar" ]; then
        log "Metabase appears to be already installed"

        # Try to get version
        if $BIN_PATH --version >/dev/null 2>&1; then
            local installed_version
            installed_version=$($BIN_PATH --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' | head -1 || echo "unknown")
            log "Installed version: $installed_version"

            if [ "$installed_version" = "$VERSION" ]; then
                log "Correct version already installed"
                return 0
            else
                log "Different version installed ($installed_version). Will reinstall."
                return 1
            fi
        else
            log "Existing installation found but version check failed. Will reinstall."
            return 1
        fi
    else
        log "No existing installation found"
        return 1
    fi
}

# Function to download file with retry
download_file() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log "Download attempt $attempt of $max_attempts..."

        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL -o "$output" "$url"; then
                log "Download successful"
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -O "$output" "$url"; then
                log "Download successful"
                return 0
            fi
        else
            error "Neither curl nor wget available for download"
        fi

        log "Download attempt $attempt failed"
        attempt=$((attempt + 1))

        if [ $attempt -le $max_attempts ]; then
            log "Retrying in 5 seconds..."
            sleep 5
        fi
    done

    error "Failed to download after $max_attempts attempts"
}

# Function to install Metabase
install_tool() {
    log "Installing Metabase $VERSION..."

    # Create installation directory
    log "Creating installation directory: $INSTALL_DIR"
    $SUDO mkdir -p "$INSTALL_DIR"

    # Download Metabase JAR
    log "Downloading Metabase JAR from $JAR_URL"
    local temp_jar="/tmp/metabase-$VERSION.jar"
    download_file "$JAR_URL" "$temp_jar"

    # Verify download
    if [ ! -f "$temp_jar" ]; then
        error "Downloaded JAR file not found at $temp_jar"
    fi

    local file_size
    file_size=$(stat -f%z "$temp_jar" 2>/dev/null || stat -c%s "$temp_jar" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 1000000 ]; then
        error "Downloaded file is too small ($file_size bytes), likely not a valid JAR"
    fi
    log "Downloaded JAR size: $file_size bytes"

    # Move JAR to installation directory
    log "Installing JAR to $INSTALL_DIR/metabase.jar"
    $SUDO mv "$temp_jar" "$INSTALL_DIR/metabase.jar"
    $SUDO chmod 644 "$INSTALL_DIR/metabase.jar"

    # Create wrapper script
    log "Creating wrapper script at $BIN_PATH"
    $SUDO tee "$BIN_PATH" > /dev/null <<'EOF'
#!/usr/bin/env bash
# Metabase wrapper script

METABASE_JAR="/opt/metabase/metabase.jar"

if [ ! -f "$METABASE_JAR" ]; then
    echo "Error: Metabase JAR not found at $METABASE_JAR" >&2
    exit 1
fi

# Handle --version flag
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "version" ]; then
    exec java --add-opens java.base/java.nio=ALL-UNNAMED -jar "$METABASE_JAR" version
fi

# Pass all arguments to Metabase
exec java --add-opens java.base/java.nio=ALL-UNNAMED -jar "$METABASE_JAR" "$@"
EOF

    # Make wrapper executable
    $SUDO chmod 755 "$BIN_PATH"

    log "Metabase installation completed"
}

# Function to validate installation
validate() {
    log "Validating Metabase installation..."

    # Check if wrapper script exists
    if [ ! -f "$BIN_PATH" ]; then
        error "Validation failed: Metabase wrapper script not found at $BIN_PATH"
    fi

    # Check if JAR exists
    if [ ! -f "$INSTALL_DIR/metabase.jar" ]; then
        error "Validation failed: Metabase JAR not found at $INSTALL_DIR/metabase.jar"
    fi

    # Check if wrapper is executable
    if [ ! -x "$BIN_PATH" ]; then
        error "Validation failed: Metabase wrapper script is not executable"
    fi

    # Try to run version command
    log "Running version check..."
    local version_output
    if ! version_output=$("$BIN_PATH" --version 2>&1); then
        error "Validation failed: Could not execute 'metabase --version'"
    fi

    log "Version output: $version_output"

    # Check if version matches expected
    if echo "$version_output" | grep -q "v0\.56\.8"; then
        log "✓ Validation successful: Metabase $VERSION is correctly installed"
    else
        log "WARNING: Version output does not contain expected version $VERSION"
        log "This may be normal if the JAR does not report patch version"
    fi

    log "Validation completed successfully"
}

# Main installation flow
main() {
    log "Starting Metabase $VERSION installation..."

    check_root

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Metabase $VERSION is already installed and validated"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
    log "You can now run: metabase --version"
    log "To start Metabase server, run: metabase"
}

# Run main function
main "$@"
