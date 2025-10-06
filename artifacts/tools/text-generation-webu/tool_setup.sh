#!/usr/bin/env bash
#
# Installation script for text-generation-webui
# Version: v3.13
# Description: A Gradio web UI for running Large Language Models
# Repository: https://github.com/oobabooga/text-generation-webui
#

set -euo pipefail

# Configuration
TOOL_NAME="text-generation-webui"
VERSION="v3.13"
INSTALL_DIR="/opt/tools/${TOOL_NAME}"
VENV_DIR="${INSTALL_DIR}/venv"
BIN_PATH="/usr/local/bin/text-generation-webu"
REPO_URL="https://github.com/oobabooga/text-generation-webui.git"
PYTHON_MIN_VERSION="3.9"

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# Validation function
validate() {
    log_info "Validating ${TOOL_NAME} installation..."

    if [[ ! -f "${BIN_PATH}" ]]; then
        log_error "Binary not found at ${BIN_PATH}"
        return 1
    fi

    if [[ ! -x "${BIN_PATH}" ]]; then
        log_error "Binary at ${BIN_PATH} is not executable"
        return 1
    fi

    # Check if the installation directory exists and has the expected structure
    if [[ ! -d "${INSTALL_DIR}" ]]; then
        log_error "Installation directory not found at ${INSTALL_DIR}"
        return 1
    fi

    if [[ ! -f "${INSTALL_DIR}/server.py" ]]; then
        log_error "server.py not found in ${INSTALL_DIR}"
        return 1
    fi

    # Check git version tag
    local installed_version
    if ! installed_version=$(cd "${INSTALL_DIR}" && git describe --tags --exact-match 2>/dev/null); then
        installed_version=$(cd "${INSTALL_DIR}" && git rev-parse --short HEAD)
    fi

    if [[ "${installed_version}" != "${VERSION}" ]]; then
        log_error "Version mismatch: expected ${VERSION}, found ${installed_version}"
        return 1
    fi

    # Test the wrapper script
    local output
    if ! output=$("${BIN_PATH}" --version 2>&1); then
        log_error "Failed to execute ${BIN_PATH} --version"
        log_error "Output: ${output}"
        return 1
    fi

    log_success "Validation passed: ${TOOL_NAME} ${VERSION} is correctly installed"
    echo "${output}"
    return 0
}

# Check if already installed (idempotency)
check_existing_installation() {
    log_info "Checking for existing installation..."

    if [[ -f "${BIN_PATH}" ]] && [[ -d "${INSTALL_DIR}" ]]; then
        local installed_version
        if ! installed_version=$(cd "${INSTALL_DIR}" && git describe --tags --exact-match 2>/dev/null); then
            installed_version="unknown"
        fi

        if [[ "${installed_version}" == "${VERSION}" ]]; then
            log_info "${TOOL_NAME} ${VERSION} is already installed"
            if validate; then
                log_success "Existing installation is valid. Nothing to do."
                exit 0
            else
                log_info "Existing installation is invalid. Proceeding with reinstallation..."
            fi
        else
            log_info "Different version found (${installed_version}). Proceeding with installation of ${VERSION}..."
        fi
    else
        log_info "No existing installation found. Proceeding with fresh installation..."
    fi
}

# Check Python version
check_python_version() {
    log_info "Checking Python version..."

    if ! command -v python3 &> /dev/null; then
        log_error "python3 is not installed. Please install Python ${PYTHON_MIN_VERSION} or higher."
        return 1
    fi

    local python_version
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')

    log_info "Found Python ${python_version}"

    # Simple version comparison (works for X.Y format)
    if [[ "$(printf '%s\n' "${PYTHON_MIN_VERSION}" "${python_version}" | sort -V | head -n1)" != "${PYTHON_MIN_VERSION}" ]]; then
        log_error "Python ${PYTHON_MIN_VERSION}+ is required, but found ${python_version}"
        return 1
    fi

    log_success "Python version check passed"
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        git \
        build-essential \
        libssl-dev \
        libffi-dev \
        python3-dev

    apt-get clean
    rm -rf /var/lib/apt/lists/*

    log_success "System dependencies installed"
}

# Clone repository
clone_repository() {
    log_info "Cloning ${TOOL_NAME} repository..."

    # Remove existing directory if present
    if [[ -d "${INSTALL_DIR}" ]]; then
        log_info "Removing existing installation directory..."
        rm -rf "${INSTALL_DIR}"
    fi

    # Create parent directory
    mkdir -p "$(dirname "${INSTALL_DIR}")"

    # Clone repository
    git clone --depth 1 --branch "${VERSION}" "${REPO_URL}" "${INSTALL_DIR}"

    # Verify checkout
    cd "${INSTALL_DIR}"
    local actual_version
    if ! actual_version=$(git describe --tags --exact-match 2>/dev/null); then
        actual_version=$(git rev-parse --short HEAD)
    fi

    if [[ "${actual_version}" != "${VERSION}" ]]; then
        log_error "Failed to checkout version ${VERSION}, got ${actual_version}"
        return 1
    fi

    log_success "Repository cloned successfully at ${INSTALL_DIR}"
}

# Setup Python virtual environment
setup_venv() {
    log_info "Setting up Python virtual environment..."

    cd "${INSTALL_DIR}"

    # Create virtual environment
    python3 -m venv "${VENV_DIR}"

    # Activate virtual environment
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"

    # Upgrade pip
    pip install --no-cache-dir --upgrade pip setuptools wheel

    log_success "Virtual environment created"
}

# Install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies..."

    cd "${INSTALL_DIR}"

    # Activate virtual environment
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"

    # Install portable requirements (CPU-only, compatible with most systems)
    if [[ -f "requirements/portable/requirements.txt" ]]; then
        pip install --no-cache-dir -r requirements/portable/requirements.txt
    elif [[ -f "requirements.txt" ]]; then
        pip install --no-cache-dir -r requirements.txt
    else
        log_error "No requirements.txt found"
        return 1
    fi

    # Clean pip cache
    pip cache purge || true

    log_success "Python dependencies installed"
}

# Create wrapper script
create_wrapper() {
    log_info "Creating wrapper script..."

    cat > "${BIN_PATH}" << 'EOF'
#!/usr/bin/env bash
#
# Wrapper script for text-generation-webui
#

INSTALL_DIR="/opt/tools/text-generation-webui"
VENV_DIR="${INSTALL_DIR}/venv"

# Change to installation directory
cd "${INSTALL_DIR}" || exit 1

# Activate virtual environment
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

# Handle --version flag
if [[ "${1:-}" == "--version" ]]; then
    echo "text-generation-webui v3.13"
    exit 0
fi

# Execute server.py with all arguments
exec python3 server.py "$@"
EOF

    # Make executable
    chmod 755 "${BIN_PATH}"

    log_success "Wrapper script created at ${BIN_PATH}"
}

# Main installation function
main() {
    log_info "Starting installation of ${TOOL_NAME} ${VERSION}..."

    # Check for existing installation
    check_existing_installation

    # Check Python version
    check_python_version

    # Install system dependencies
    install_dependencies

    # Clone repository
    clone_repository

    # Setup virtual environment
    setup_venv

    # Install Python dependencies
    install_python_deps

    # Create wrapper script
    create_wrapper

    # Validate installation
    if validate; then
        log_success "${TOOL_NAME} ${VERSION} installed successfully!"
        log_info "You can now run: text-generation-webu --help"
        log_info "To start the web UI: text-generation-webu --auto-launch"
        return 0
    else
        log_error "Installation validation failed"
        return 1
    fi
}

# Run main function
main "$@"
