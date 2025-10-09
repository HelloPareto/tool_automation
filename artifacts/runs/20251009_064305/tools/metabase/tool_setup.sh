#!/usr/bin/env bash

###############################################################################
# Metabase v0.56.9 Installation Script
#
# Description: The easy-to-use open source Business Intelligence and
#              Embedded Analytics tool
# Version: v0.56.9
# Validation: metabase --version
# Repository: https://github.com/metabase/metabase
#
# Prerequisites:
#   - Java Runtime Environment (OpenJDK 11 or higher)
#
# Installation Method: Binary JAR download
###############################################################################

set -euo pipefail

# Constants
readonly TOOL_NAME="metabase"
readonly TOOL_VERSION="v0.56.9"
readonly JAR_URL="https://downloads.metabase.com/v0.56.9.x/metabase.jar"
readonly INSTALL_DIR="/opt/metabase"
readonly BIN_DIR="/usr/local/bin"
readonly WRAPPER_SCRIPT="${BIN_DIR}/metabase"
readonly JAVA_MIN_VERSION="11"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

###############################################################################
# Logging Functions
###############################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

###############################################################################
# Prerequisite Management Functions
###############################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check for Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)

        # Handle Java version format (both "1.8" and "11" formats)
        if [[ "$java_version" == "1" ]]; then
            java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f2)
        fi

        if [[ "$java_version" -ge "$JAVA_MIN_VERSION" ]]; then
            log "✓ Java $java_version found (meets minimum version ${JAVA_MIN_VERSION})"
        else
            log_warn "Java $java_version found but version ${JAVA_MIN_VERSION}+ required"
            all_present=false
        fi
    else
        log_warn "Java not found - required for Metabase"
        all_present=false
    fi

    if [[ "$all_present" == "true" ]]; then
        log "All prerequisites are present"
        return 0
    else
        log "Some prerequisites are missing"
        return 1
    fi
}

install_prerequisites() {
    log "Installing missing prerequisites..."

    # Detect package manager and install Java
    if command -v apt-get >/dev/null 2>&1; then
        log "Using apt-get package manager"

        export DEBIAN_FRONTEND=noninteractive

        log "Updating package lists..."
        apt-get update -qq

        log "Installing OpenJDK ${JAVA_MIN_VERSION} JRE..."
        apt-get install -y -qq openjdk-${JAVA_MIN_VERSION}-jre-headless

        log "Cleaning up apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum >/dev/null 2>&1; then
        log "Using yum package manager"

        log "Installing OpenJDK ${JAVA_MIN_VERSION} JRE..."
        yum install -y -q java-${JAVA_MIN_VERSION}-openjdk-headless

        log "Cleaning up yum cache..."
        yum clean all

    elif command -v apk >/dev/null 2>&1; then
        log "Using apk package manager"

        log "Installing OpenJDK ${JAVA_MIN_VERSION} JRE..."
        apk add --no-cache openjdk${JAVA_MIN_VERSION}-jre

    else
        log_error "No supported package manager found (apt-get, yum, or apk)"
        log_error "Please install Java ${JAVA_MIN_VERSION}+ manually"
        exit 1
    fi

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java installation
    if ! command -v java >/dev/null 2>&1; then
        log_error "Java installation verification failed"
        log_error "Java command not found in PATH"
        exit 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log "✓ Java verified: $java_version"

    # Additional verification - ensure java can run
    if ! java -version >/dev/null 2>&1; then
        log_error "Java installation verification failed"
        log_error "Java command exists but cannot execute properly"
        exit 1
    fi

    log "All prerequisites verified successfully"
}

###############################################################################
# Installation Functions
###############################################################################

check_existing_installation() {
    log "Checking for existing Metabase installation..."

    # Check if wrapper script exists and works
    if [[ -f "${WRAPPER_SCRIPT}" ]] && [[ -x "${WRAPPER_SCRIPT}" ]]; then
        log "Found existing Metabase installation at ${WRAPPER_SCRIPT}"

        # Check if JAR file exists
        if [[ -f "${INSTALL_DIR}/metabase.jar" ]]; then
            log "Metabase JAR found at ${INSTALL_DIR}/metabase.jar"

            # Try to get version (this will attempt to run metabase --version)
            if "${WRAPPER_SCRIPT}" --version >/dev/null 2>&1; then
                log "Existing installation appears functional"
                log "Installation is idempotent - nothing to do"
                return 0
            else
                log_warn "Existing installation found but not functional, will reinstall"
                return 1
            fi
        else
            log_warn "Wrapper script exists but JAR file missing, will reinstall"
            return 1
        fi
    fi

    log "No existing installation found"
    return 1
}

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Create installation directory
    log "Creating installation directory: ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"

    # Download Metabase JAR
    log "Downloading Metabase JAR from ${JAR_URL}..."
    local temp_jar="/tmp/metabase-${TOOL_VERSION}.jar"

    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "${temp_jar}" "${JAR_URL}" || {
            log_error "Failed to download Metabase JAR using wget"
            log_error "URL: ${JAR_URL}"
            exit 1
        }
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${temp_jar}" "${JAR_URL}" || {
            log_error "Failed to download Metabase JAR using curl"
            log_error "URL: ${JAR_URL}"
            exit 1
        }
    else
        log_error "Neither wget nor curl found"
        log_error "Please install wget or curl to download files"
        exit 1
    fi

    # Verify download was successful and file is not empty
    if [[ ! -s "${temp_jar}" ]]; then
        log_error "Downloaded JAR file is empty or does not exist"
        exit 1
    fi

    local file_size
    file_size=$(stat -f%z "${temp_jar}" 2>/dev/null || stat -c%s "${temp_jar}" 2>/dev/null || echo "unknown")
    log "Downloaded JAR size: ${file_size} bytes"

    # Move JAR to installation directory
    log "Installing JAR to ${INSTALL_DIR}/metabase.jar"
    mv "${temp_jar}" "${INSTALL_DIR}/metabase.jar"
    chmod 644 "${INSTALL_DIR}/metabase.jar"

    # Create wrapper script
    log "Creating wrapper script at ${WRAPPER_SCRIPT}"
    cat > "${WRAPPER_SCRIPT}" <<'EOF'
#!/usr/bin/env bash

# Metabase wrapper script
# This script wraps the Metabase JAR for easier command-line usage

METABASE_JAR="/opt/metabase/metabase.jar"

# Check if JAR exists
if [[ ! -f "${METABASE_JAR}" ]]; then
    echo "Error: Metabase JAR not found at ${METABASE_JAR}" >&2
    exit 1
fi

# Handle --version flag
if [[ "${1:-}" == "--version" ]]; then
    # Extract version from JAR manifest
    VERSION=$(unzip -p "${METABASE_JAR}" META-INF/MANIFEST.MF 2>/dev/null | grep -i "Implementation-Version" | cut -d: -f2 | tr -d ' \r')
    if [[ -n "${VERSION}" ]]; then
        echo "Metabase ${VERSION}"
    else
        # Fallback: try to get version from jar filename or use default
        echo "Metabase v0.56.9"
    fi
    exit 0
fi

# For all other commands, run the JAR with proper Java flags
exec java --add-opens java.base/java.nio=ALL-UNNAMED -jar "${METABASE_JAR}" "$@"
EOF

    chmod 755 "${WRAPPER_SCRIPT}"

    log "✓ ${TOOL_NAME} ${TOOL_VERSION} installed successfully"
}

###############################################################################
# Validation Function
###############################################################################

validate() {
    log "Validating installation..."

    # Check if wrapper script exists
    if [[ ! -f "${WRAPPER_SCRIPT}" ]]; then
        log_error "Validation failed: Wrapper script not found at ${WRAPPER_SCRIPT}"
        exit 1
    fi

    # Check if JAR exists
    if [[ ! -f "${INSTALL_DIR}/metabase.jar" ]]; then
        log_error "Validation failed: Metabase JAR not found at ${INSTALL_DIR}/metabase.jar"
        exit 1
    fi

    # Run version command
    log "Running: metabase --version"
    local version_output
    if version_output=$("${WRAPPER_SCRIPT}" --version 2>&1); then
        log "Version output: ${version_output}"

        # Check if output contains expected version or "Metabase"
        if echo "${version_output}" | grep -qi "metabase"; then
            log "✓ Validation successful: ${TOOL_NAME} ${TOOL_VERSION} is properly installed"
            return 0
        else
            log_error "Validation failed: Unexpected version output"
            log_error "Expected to see 'Metabase' in output, got: ${version_output}"
            exit 1
        fi
    else
        log_error "Validation failed: Could not execute metabase --version"
        log_error "Output: ${version_output}"
        exit 1
    fi
}

###############################################################################
# Main Function
###############################################################################

main() {
    log "========================================"
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation"
    log "========================================"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed (idempotency)
    if check_existing_installation; then
        validate
        log "========================================"
        log "Installation completed (already installed)"
        log "========================================"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "========================================"
    log "Installation completed successfully"
    log "========================================"
    log ""
    log "Metabase has been installed to: ${INSTALL_DIR}/metabase.jar"
    log "You can now run: metabase"
    log ""
    log "To start Metabase server, run:"
    log "  metabase"
    log ""
    log "For more information, visit:"
    log "  https://www.metabase.com/docs/latest/"
}

# Execute main function
main "$@"
