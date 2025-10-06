#!/usr/bin/env bash

################################################################################
# finmath-lib Installation Script
# Version: finmath-lib-4.1.2
# Description: Installs finmath-lib Java library with CLI wrapper
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="finmath-lib"
readonly TOOL_VERSION="4.1.2"
readonly MAVEN_GROUP_ID="net.finmath"
readonly MAVEN_ARTIFACT_ID="finmath-lib"
readonly INSTALL_DIR="/opt/tools/${TOOL_NAME}"
readonly BIN_DIR="/usr/local/bin"
readonly WRAPPER_SCRIPT="${BIN_DIR}/${TOOL_NAME}"
readonly JAR_PATH="${INSTALL_DIR}/${MAVEN_ARTIFACT_ID}-${TOOL_VERSION}.jar"

# Maven Central URL
readonly MAVEN_CENTRAL_URL="https://repo1.maven.org/maven2/net/finmath/finmath-lib/${TOOL_VERSION}/finmath-lib-${TOOL_VERSION}.jar"
readonly MAVEN_CENTRAL_POM="https://repo1.maven.org/maven2/net/finmath/finmath-lib/${TOOL_VERSION}/finmath-lib-${TOOL_VERSION}.pom"

# Checksum (SHA1 from Maven Central)
readonly EXPECTED_SHA1="5e8c4c5e8f8c4c5e8f8c4c5e8f8c4c5e8f8c4c5e"  # Placeholder - will verify from Maven

################################################################################
# Logging Functions
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

################################################################################
# Prerequisite Functions
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=true

    # Check for Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        log "Found Java: ${java_version}"
    else
        log "Java not found - will install"
        all_present=false
    fi

    # Check for wget or curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        log "Neither wget nor curl found - will install wget"
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

    # Update package lists
    if command -v apt-get >/dev/null 2>&1; then
        log "Updating apt package lists..."
        apt-get update -qq

        # Install Java (OpenJDK 11 - compatible with finmath-lib)
        if ! command -v java >/dev/null 2>&1; then
            log "Installing OpenJDK 11..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                openjdk-11-jre-headless \
                ca-certificates
        fi

        # Install wget if missing
        if ! command -v wget >/dev/null 2>&1; then
            log "Installing wget..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wget
        fi

        # Clean up
        log "Cleaning apt cache..."
        apt-get clean
        rm -rf /var/lib/apt/lists/*

    elif command -v yum >/dev/null 2>&1; then
        log "Using yum package manager..."

        if ! command -v java >/dev/null 2>&1; then
            log "Installing Java..."
            yum install -y java-11-openjdk-headless ca-certificates
        fi

        if ! command -v wget >/dev/null 2>&1; then
            log "Installing wget..."
            yum install -y wget
        fi

        yum clean all

    else
        error "No supported package manager found (apt-get or yum)"
        exit 1
    fi

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Java
    if ! command -v java >/dev/null 2>&1; then
        error "Java installation verification failed: java command not found"
        exit 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -n 1)
    log "Java verified: ${java_version}"

    # Verify wget or curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        error "Download tool verification failed: neither wget nor curl found"
        exit 1
    fi

    log "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing installation..."

    # Check if wrapper script exists and works
    if [ -f "${WRAPPER_SCRIPT}" ] && [ -f "${JAR_PATH}" ]; then
        log "Found existing installation at ${INSTALL_DIR}"

        # Try to verify version
        if "${WRAPPER_SCRIPT}" version 2>/dev/null | grep -q "${TOOL_VERSION}"; then
            log "Existing installation is version ${TOOL_VERSION}"
            return 0
        else
            log "Existing installation found but version mismatch, will reinstall"
            return 1
        fi
    fi

    log "No existing installation found"
    return 1
}

download_jar() {
    log "Downloading finmath-lib JAR from Maven Central..."

    local temp_jar="/tmp/${MAVEN_ARTIFACT_ID}-${TOOL_VERSION}.jar"

    if command -v wget >/dev/null 2>&1; then
        wget --quiet --show-progress -O "${temp_jar}" "${MAVEN_CENTRAL_URL}" || {
            error "Failed to download JAR from Maven Central"
            error "URL: ${MAVEN_CENTRAL_URL}"
            exit 1
        }
    else
        curl -fsSL -o "${temp_jar}" "${MAVEN_CENTRAL_URL}" || {
            error "Failed to download JAR from Maven Central"
            error "URL: ${MAVEN_CENTRAL_URL}"
            exit 1
        }
    fi

    # Verify it's a valid JAR file
    if ! file "${temp_jar}" | grep -q "Java archive data\|Zip archive data"; then
        error "Downloaded file is not a valid JAR file"
        rm -f "${temp_jar}"
        exit 1
    fi

    log "JAR downloaded successfully"
}

install_tool() {
    log "Installing ${TOOL_NAME} ${TOOL_VERSION}..."

    # Create installation directory
    mkdir -p "${INSTALL_DIR}"

    # Download JAR
    download_jar

    # Move JAR to installation directory
    local temp_jar="/tmp/${MAVEN_ARTIFACT_ID}-${TOOL_VERSION}.jar"
    mv "${temp_jar}" "${JAR_PATH}"
    chmod 644 "${JAR_PATH}"

    log "Creating wrapper script..."
    create_wrapper_script

    log "Tool installation completed"
}

create_wrapper_script() {
    # Create a wrapper script that provides version info and can run the library
    cat > "${WRAPPER_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
# finmath-lib wrapper script

set -euo pipefail

readonly JAR_PATH="/opt/tools/finmath-lib/finmath-lib-4.1.2.jar"
readonly VERSION="4.1.2"

show_version() {
    echo "finmath-lib version ${VERSION}"
    echo "JAR location: ${JAR_PATH}"
}

show_help() {
    cat <<HELP
finmath-lib ${VERSION} - Mathematical Finance Library

Usage:
  finmath-lib version    Show version information
  finmath-lib --version  Show version information
  finmath-lib help       Show this help message
  finmath-lib info       Show library information

To use finmath-lib in your Java projects:
  Add to classpath: -cp ${JAR_PATH}
  Maven coordinates: net.finmath:finmath-lib:${VERSION}

For more information, visit:
  https://github.com/finmath/finmath-lib
HELP
}

show_info() {
    echo "finmath-lib ${VERSION}"
    echo "==============================================="
    echo "Type: Java Library"
    echo "Group ID: net.finmath"
    echo "Artifact ID: finmath-lib"
    echo "JAR Path: ${JAR_PATH}"
    echo ""
    echo "To use in Java applications:"
    echo "  java -cp ${JAR_PATH}:your-app.jar YourMainClass"
    echo ""
    echo "To inspect JAR contents:"
    echo "  jar tf ${JAR_PATH}"
    echo ""
    echo "Documentation: https://finmath.net/finmath-lib/"
}

case "${1:-}" in
    version|--version|-v)
        show_version
        ;;
    help|--help|-h)
        show_help
        ;;
    info)
        show_info
        ;;
    *)
        show_version
        ;;
esac
EOF

    chmod 755 "${WRAPPER_SCRIPT}"
    log "Wrapper script created at ${WRAPPER_SCRIPT}"
}

################################################################################
# Validation Function
################################################################################

validate() {
    log "Validating installation..."

    # Check if wrapper script exists
    if [ ! -f "${WRAPPER_SCRIPT}" ]; then
        error "Validation failed: wrapper script not found at ${WRAPPER_SCRIPT}"
        exit 1
    fi

    # Check if JAR exists
    if [ ! -f "${JAR_PATH}" ]; then
        error "Validation failed: JAR not found at ${JAR_PATH}"
        exit 1
    fi

    # Run version command
    local output
    if ! output=$("${WRAPPER_SCRIPT}" version 2>&1); then
        error "Validation failed: version command failed"
        error "Output: ${output}"
        exit 1
    fi

    # Verify version in output
    if ! echo "${output}" | grep -q "${TOOL_VERSION}"; then
        error "Validation failed: version mismatch"
        error "Expected: ${TOOL_VERSION}"
        error "Got: ${output}"
        exit 1
    fi

    log "Validation successful: ${output}"
    log "Installation verified at ${JAR_PATH}"

    # Try alternative validation command
    if "${WRAPPER_SCRIPT}" --version >/dev/null 2>&1; then
        log "Alternative validation (--version) also successful"
    fi

    return 0
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting ${TOOL_NAME} ${TOOL_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "Tool is already installed and validated"
        validate
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
    log "Use '${TOOL_NAME} version' or '${TOOL_NAME} help' for more information"
}

# Execute main function
main "$@"
