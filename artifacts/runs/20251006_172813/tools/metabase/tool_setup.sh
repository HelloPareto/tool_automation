#!/usr/bin/env bash

###############################################################################
# Metabase v0.56.8 Installation Script
# Package Manager: npm
# Validate Command: npm list -g metabase
###############################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="metabase"
readonly TOOL_VERSION="0.56.8"
readonly VALIDATE_CMD="npm list -g metabase"
readonly MIN_NODE_VERSION="14"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

###############################################################################
# Prerequisites Management
###############################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local all_present=true

    # Check Node.js
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node --version | sed 's/v//')
        log "✓ Node.js found: v${node_version}"
    else
        log "✗ Node.js not found"
        all_present=false
    fi

    # Check npm
    if command -v npm >/dev/null 2>&1; then
        local npm_version
        npm_version=$(npm --version)
        log "✓ npm found: v${npm_version}"
    else
        log "✗ npm not found"
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
    log "Installing missing prerequisites..."

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "Cannot detect OS. /etc/os-release not found."
    fi

    case "$OS" in
        ubuntu|debian)
            install_nodejs_debian
            ;;
        centos|rhel|fedora)
            install_nodejs_rhel
            ;;
        *)
            error "Unsupported OS: $OS. Please install Node.js and npm manually."
            ;;
    esac
}

install_nodejs_debian() {
    log "Installing Node.js and npm on Debian/Ubuntu..."

    # Update package list
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || error "Failed to update apt package list"

    # Install Node.js from NodeSource repository (official Node.js binary distributions)
    # Using Node.js 18.x LTS for compatibility
    log "Adding NodeSource repository for Node.js 18.x..."

    # Install prerequisites for adding repository
    apt-get install -y -qq curl gnupg ca-certificates || error "Failed to install repository prerequisites"

    # Download and add NodeSource GPG key
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
        gpg --dearmor -o /usr/share/keyrings/nodesource.gpg || \
        error "Failed to add NodeSource GPG key"

    # Add NodeSource repository
    local NODE_MAJOR=18
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | \
        tee /etc/apt/sources.list.d/nodesource.list > /dev/null || \
        error "Failed to add NodeSource repository"

    # Update and install Node.js
    apt-get update -qq || error "Failed to update apt after adding NodeSource repo"
    apt-get install -y -qq nodejs || error "Failed to install Node.js"

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Node.js and npm installed successfully"
}

install_nodejs_rhel() {
    log "Installing Node.js and npm on RHEL/CentOS/Fedora..."

    # Install Node.js from NodeSource repository
    log "Adding NodeSource repository for Node.js 18.x..."

    # Download and run NodeSource setup script
    curl -fsSL https://rpm.nodesource.com/setup_18.x | bash - || \
        error "Failed to setup NodeSource repository"

    # Install Node.js
    yum install -y nodejs || error "Failed to install Node.js"

    # Clean up
    yum clean all
    rm -rf /var/cache/yum

    log "Node.js and npm installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Node.js
    if ! command -v node >/dev/null 2>&1; then
        error "Node.js verification failed: node command not found"
    fi

    local node_version
    node_version=$(node --version) || error "Failed to get Node.js version"
    log "✓ Node.js verified: ${node_version}"

    # Check minimum version
    local node_major
    node_major=$(echo "$node_version" | sed 's/v//' | cut -d. -f1)
    if [ "$node_major" -lt "$MIN_NODE_VERSION" ]; then
        error "Node.js version ${node_version} is too old. Minimum required: v${MIN_NODE_VERSION}.x"
    fi

    # Verify npm
    if ! command -v npm >/dev/null 2>&1; then
        error "npm verification failed: npm command not found"
    fi

    local npm_version
    npm_version=$(npm --version) || error "Failed to get npm version"
    log "✓ npm verified: v${npm_version}"

    log "All prerequisites verified successfully"
}

###############################################################################
# Tool Installation
###############################################################################

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if command -v metabase >/dev/null 2>&1; then
        log "Found metabase command in PATH"

        # Check if it's installed via npm globally
        if npm list -g metabase >/dev/null 2>&1; then
            local installed_version
            installed_version=$(npm list -g metabase --depth=0 2>/dev/null | grep metabase@ | sed 's/.*metabase@//' | sed 's/ .*//')

            if [ -n "$installed_version" ]; then
                log "✓ ${TOOL_NAME} is already installed: v${installed_version}"

                if [ "$installed_version" = "$TOOL_VERSION" ]; then
                    log "Installed version matches requested version v${TOOL_VERSION}"
                    return 0
                else
                    log "Installed version v${installed_version} differs from requested v${TOOL_VERSION}"
                    log "Proceeding with installation of v${TOOL_VERSION}..."
                    return 1
                fi
            fi
        fi
    fi

    log "✗ ${TOOL_NAME} is not installed"
    return 1
}

install_tool() {
    log "Installing ${TOOL_NAME} v${TOOL_VERSION}..."

    # Check if the version exists on npm
    log "Checking if ${TOOL_NAME}@${TOOL_VERSION} exists on npm registry..."
    if ! npm view "${TOOL_NAME}@${TOOL_VERSION}" version >/dev/null 2>&1; then
        log "ERROR: Package ${TOOL_NAME}@${TOOL_VERSION} does not exist on npm registry"
        log ""
        log "DIAGNOSTIC INFORMATION:"
        log "---------------------------------------------------"

        # Show available versions
        local available_versions
        available_versions=$(npm view "${TOOL_NAME}" versions --json 2>/dev/null || echo "[]")
        log "Available versions of '${TOOL_NAME}' on npm:"
        echo "$available_versions" | grep -E '^\s*"[0-9]' | head -10 || echo "  No versions found"

        log ""
        log "IMPORTANT NOTE:"
        log "The official Metabase analytics platform (https://www.metabase.com)"
        log "version v0.56.8 is NOT distributed as an npm package."
        log ""
        log "Metabase is a Java application available via:"
        log "  - Docker: docker pull metabase/metabase:v0.56.8"
        log "  - JAR file: https://downloads.metabase.com/v0.56.8/metabase.jar"
        log "  - Cloud: https://www.metabase.com/start/"
        log ""
        log "The 'metabase' npm package (v0.1.0) is an unrelated package from 2015."
        log "---------------------------------------------------"

        error "Cannot install non-existent package ${TOOL_NAME}@${TOOL_VERSION}"
    fi

    # Install specific version globally
    npm install -g "${TOOL_NAME}@${TOOL_VERSION}" || \
        error "Failed to install ${TOOL_NAME} v${TOOL_VERSION} via npm"

    log "✓ ${TOOL_NAME} v${TOOL_VERSION} installed successfully"
}

###############################################################################
# Validation
###############################################################################

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if metabase command exists
    if ! command -v metabase >/dev/null 2>&1; then
        error "Validation failed: metabase command not found in PATH"
    fi

    # Run the validation command
    log "Running validation command: ${VALIDATE_CMD}"
    if ! eval "${VALIDATE_CMD}" >/dev/null 2>&1; then
        error "Validation command failed: ${VALIDATE_CMD}"
    fi

    # Extract and verify version
    local installed_version
    installed_version=$(npm list -g metabase --depth=0 2>/dev/null | grep metabase@ | sed 's/.*metabase@//' | sed 's/ .*//')

    if [ -z "$installed_version" ]; then
        error "Could not determine installed version"
    fi

    log "✓ Validation successful: ${TOOL_NAME} v${installed_version} is installed"

    if [ "$installed_version" != "$TOOL_VERSION" ]; then
        log "WARNING: Installed version (v${installed_version}) differs from requested version (v${TOOL_VERSION})"
        return 1
    fi

    log "✓ Version matches: v${TOOL_VERSION}"
    return 0
}

###############################################################################
# Main
###############################################################################

main() {
    log "Starting ${TOOL_NAME} v${TOOL_VERSION} installation..."
    log "================================================================"

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "================================================================"
        log "Installation completed successfully (already installed)"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "================================================================"
    log "Installation completed successfully"
}

# Run main function
main "$@"
