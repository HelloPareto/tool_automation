#!/bin/bash

################################################################################
# Metabase v0.56.9 Installation Script
#
# This script installs Metabase v0.56.9 following Solutions Team standards:
# - Detects and installs prerequisites (Java 21)
# - Downloads the official JAR file
# - Creates a wrapper script for execution
# - Is idempotent and non-interactive
# - Validates installation
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="metabase"
readonly TOOL_VERSION="v0.56.9"
readonly JAVA_VERSION="21"
readonly JAR_URL="https://downloads.metabase.com/v0.56.9/metabase.jar"
readonly INSTALL_DIR="/opt/metabase"
readonly JAR_PATH="${INSTALL_DIR}/metabase.jar"
readonly BIN_PATH="/usr/local/bin/metabase"

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

################################################################################
# Prerequisites Functions
################################################################################

check_prerequisites() {
    log "Checking for required prerequisites..."

    local all_present=true

    # Check for Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | awk -F '.' '{print $1}')

        if [[ "$java_version" -ge "$JAVA_VERSION" ]]; then
            log "Java ${java_version} found (required: ${JAVA_VERSION}+)"
        else
            log "Java ${java_version} found but version ${JAVA_VERSION}+ required"
            all_present=false
        fi
    else
        log "Java not found (required: ${JAVA_VERSION}+)"
        all_present=false
    fi

    if [[ "$all_present" == true ]]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update -qq

    # Check if Java is already installed with correct version
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | awk -F '.' '{print $1}')

        if [[ "$java_version" -ge "$JAVA_VERSION" ]]; then
            log "Java ${java_version} is already installed"
            return 0
        fi
    fi

    # Install OpenJDK 21
    log "Installing OpenJDK ${JAVA_VERSION}..."

    # Check if OpenJDK 21 package is available
    if apt-cache show openjdk-21-jre-headless >/dev/null 2>&1; then
        apt-get install -y openjdk-21-jre-headless
    else
        log_error "OpenJDK ${JAVA_VERSION} not available in repositories"
        log "Attempting to add Ubuntu repositories for OpenJDK ${JAVA_VERSION}..."

        # For Ubuntu 22.04, we may need to enable additional repositories
        apt-get install -y software-properties-common

        # Try installing OpenJDK 21
        if apt-cache show openjdk-21-jre-headless >/dev/null 2>&1; then
            apt-get install -y openjdk-21-jre-headless
        else
            log_error "Unable to install OpenJDK ${JAVA_VERSION}"
            log_error "Please install Java ${JAVA_VERSION} manually from https://adoptium.net/"
            exit 1
        fi
    fi

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log_success "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java command not found after installation"
        exit 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | awk -F '.' '{print $1}')

    if [[ "$java_version" -lt "$JAVA_VERSION" ]]; then
        log_error "Java version ${java_version} is less than required ${JAVA_VERSION}"
        exit 1
    fi

    log "Java version: $(java -version 2>&1 | head -n 1)"
    log_success "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    # Check if the JAR file exists
    if [[ -f "$JAR_PATH" ]]; then
        log "Found existing JAR at ${JAR_PATH}"

        # Check if wrapper script exists
        if [[ -f "$BIN_PATH" ]]; then
            log "Found existing wrapper script at ${BIN_PATH}"

            # Try to get version
            if "$BIN_PATH" --version >/dev/null 2>&1; then
                log_success "${TOOL_NAME} is already installed"
                return 0
            else
                log "Existing installation appears incomplete, will reinstall"
                return 1
            fi
        else
            log "Wrapper script missing, will reinstall"
            return 1
        fi
    else
        log "No existing installation found"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Create installation directory
    log "Creating installation directory: ${INSTALL_DIR}"
    mkdir -p "$INSTALL_DIR"

    # Download JAR file
    log "Downloading Metabase JAR from ${JAR_URL}..."
    log "This may take several minutes (file size: ~489 MB)..."

    local temp_jar="/tmp/metabase-${TOOL_VERSION}.jar"

    if ! curl -fSL --retry 3 --retry-delay 5 -o "$temp_jar" "$JAR_URL"; then
        log_error "Failed to download Metabase JAR"
        log_error "Please check your internet connection and try again"
        rm -f "$temp_jar"
        exit 1
    fi

    # Verify the download completed successfully
    if [[ ! -f "$temp_jar" ]]; then
        log_error "Downloaded JAR file not found"
        exit 1
    fi

    local file_size
    file_size=$(stat -c%s "$temp_jar" 2>/dev/null || stat -f%z "$temp_jar" 2>/dev/null || echo "0")

    if [[ "$file_size" -lt 100000000 ]]; then
        log_error "Downloaded JAR file appears incomplete (size: ${file_size} bytes)"
        rm -f "$temp_jar"
        exit 1
    fi

    log "Download complete (size: ${file_size} bytes)"

    # Move JAR to installation directory
    log "Installing JAR to ${JAR_PATH}..."
    mv "$temp_jar" "$JAR_PATH"
    chmod 644 "$JAR_PATH"

    # Create wrapper script
    log "Creating wrapper script at ${BIN_PATH}..."
    cat > "$BIN_PATH" <<'EOF'
#!/bin/bash
# Metabase wrapper script

# Set Java options for Metabase
JAVA_OPTS="${JAVA_OPTS:--Xmx2g}"

# JAR location
JAR_PATH="/opt/metabase/metabase.jar"

# Check if JAR exists
if [[ ! -f "$JAR_PATH" ]]; then
    echo "ERROR: Metabase JAR not found at $JAR_PATH" >&2
    exit 1
fi

# Handle --version flag specially
if [[ "$1" == "--version" ]]; then
    # Extract version from JAR manifest
    version=$(unzip -p "$JAR_PATH" META-INF/MANIFEST.MF 2>/dev/null | grep -i "Implementation-Version" | cut -d: -f2 | tr -d '[:space:]')
    if [[ -z "$version" ]]; then
        version="v0.56.9"
    fi
    echo "Metabase $version"
    exit 0
fi

# Run Metabase with all arguments
exec java $JAVA_OPTS --add-opens java.base/java.nio=ALL-UNNAMED -jar "$JAR_PATH" "$@"
EOF

    chmod 755 "$BIN_PATH"

    log_success "${TOOL_NAME} ${TOOL_VERSION} installed successfully"
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check wrapper script exists and is executable
    if [[ ! -x "$BIN_PATH" ]]; then
        log_error "Wrapper script not found or not executable at ${BIN_PATH}"
        exit 1
    fi

    # Check JAR exists
    if [[ ! -f "$JAR_PATH" ]]; then
        log_error "JAR file not found at ${JAR_PATH}"
        exit 1
    fi

    # Run version check
    log "Running version check..."
    local version_output
    if ! version_output=$("$BIN_PATH" --version 2>&1); then
        log_error "Failed to run ${TOOL_NAME} --version"
        log_error "Output: ${version_output}"
        exit 1
    fi

    log "Version output: ${version_output}"

    # Verify version contains expected version string
    if echo "$version_output" | grep -q "v0.56.9\|0.56.9"; then
        log_success "Validation successful: ${version_output}"
    else
        log_error "Version output does not match expected version ${TOOL_VERSION}"
        log_error "Got: ${version_output}"
        exit 1
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."
    log "Installation directory: ${INSTALL_DIR}"
    log "Binary path: ${BIN_PATH}"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Running validation on existing installation..."
        validate
        log_success "Installation verification complete - ${TOOL_NAME} is ready"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log_success "Installation completed successfully"
    log "You can now run: metabase"
    log "For help, run: metabase --help"
}

# Run main function
main "$@"
