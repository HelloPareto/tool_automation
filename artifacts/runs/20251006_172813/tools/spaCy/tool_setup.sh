#!/bin/bash
# spaCy Installation Script
# Version: release-v3.8.7
# Installation Standards Compliant

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
TOOL_NAME="spaCy"
SPACY_VERSION="3.8.7"

# ============================================================================
# Logging Functions
# ============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# ============================================================================
# Prerequisite Management
# ============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    local all_present=0

    # Check Python3
    if command -v python3 &> /dev/null; then
        log "✓ Python3 found: $(python3 --version)"
    else
        log "✗ Python3 not found"
        all_present=1
    fi

    # Check pip3
    if command -v pip3 &> /dev/null; then
        log "✓ pip3 found: $(pip3 --version)"
    else
        log "✗ pip3 not found"
        all_present=1
    fi

    # Check gcc (build tools)
    if command -v gcc &> /dev/null; then
        log "✓ gcc found: $(gcc --version | head -n1)"
    else
        log "✗ gcc not found"
        all_present=1
    fi

    # Check make
    if command -v make &> /dev/null; then
        log "✓ make found: $(make --version | head -n1)"
    else
        log "✗ make not found"
        all_present=1
    fi

    return $all_present
}

install_prerequisites() {
    log "Installing prerequisites..."

    # Update package lists
    log "Updating package lists..."
    apt-get update

    # Install Python3 and pip if not present
    if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
        log "Installing Python3 and pip3..."
        apt-get install -y python3 python3-pip python3-venv python3-dev
    fi

    # Install build tools if not present
    if ! command -v gcc &> /dev/null || ! command -v make &> /dev/null; then
        log "Installing build-essential..."
        apt-get install -y build-essential
    fi

    # Clean up
    log "Cleaning up package cache..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log "Prerequisites installation completed"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Python3
    if ! python3 --version &> /dev/null; then
        error "Python3 verification failed"
        exit 1
    fi
    log "✓ Python3 verified: $(python3 --version)"

    # Verify pip3
    if ! pip3 --version &> /dev/null; then
        error "pip3 verification failed"
        exit 1
    fi
    log "✓ pip3 verified: $(pip3 --version)"

    # Verify gcc
    if ! gcc --version &> /dev/null; then
        error "gcc verification failed"
        exit 1
    fi
    log "✓ gcc verified: $(gcc --version | head -n1)"

    # Verify make
    if ! make --version &> /dev/null; then
        error "make verification failed"
        exit 1
    fi
    log "✓ make verified: $(make --version | head -n1)"

    log "All prerequisites verified successfully"
}

# ============================================================================
# Installation Functions
# ============================================================================

check_existing_installation() {
    log "Checking for existing ${TOOL_NAME} installation..."

    if python3 -c "import spacy" &> /dev/null; then
        local installed_version
        installed_version=$(python3 -c "import spacy; print(spacy.__version__)" 2>/dev/null || echo "unknown")

        if [[ "$installed_version" == "$SPACY_VERSION" ]]; then
            log "✓ ${TOOL_NAME} ${SPACY_VERSION} is already installed"
            return 0
        else
            log "Found ${TOOL_NAME} version ${installed_version}, but expected ${SPACY_VERSION}"
            return 1
        fi
    else
        log "${TOOL_NAME} is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing ${TOOL_NAME} ${SPACY_VERSION}..."

    # Upgrade pip to latest version
    log "Upgrading pip..."
    pip3 install --upgrade pip

    # Install spaCy with pinned version
    log "Installing spaCy==${SPACY_VERSION}..."
    pip3 install --no-cache-dir "spacy==${SPACY_VERSION}"

    log "${TOOL_NAME} installation completed"
}

validate() {
    log "Validating ${TOOL_NAME} installation..."

    # Check if spaCy can be imported
    if ! python3 -c "import spacy" &> /dev/null; then
        error "Failed to import spacy module"
        error "Please check the installation logs above for errors"
        exit 1
    fi

    # Check version
    local installed_version
    installed_version=$(python3 -c "import spacy; print(spacy.__version__)" 2>/dev/null || echo "unknown")

    if [[ "$installed_version" != "$SPACY_VERSION" ]]; then
        error "Version mismatch: expected ${SPACY_VERSION}, got ${installed_version}"
        exit 1
    fi

    log "✓ ${TOOL_NAME} ${installed_version} validated successfully"

    # Additional validation: check that spaCy CLI is available
    if command -v spacy &> /dev/null; then
        log "✓ spaCy CLI is available: $(spacy --version 2>&1 || echo 'version check')"
    fi

    return 0
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log "Starting ${TOOL_NAME} ${SPACY_VERSION} installation..."

    # Step 1: Prerequisites
    if ! check_prerequisites; then
        install_prerequisites
        verify_prerequisites
    else
        log "All prerequisites are already present"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        log "Installation check completed - ${TOOL_NAME} is already installed and valid"
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log "Installation completed successfully"
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
