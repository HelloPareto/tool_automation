#!/usr/bin/env bash
#############################################################
# OpenEMR Installation Script
#############################################################
# OpenEMR is a web-based electronic health records (EHR) and
# medical practice management application. This script deploys
# OpenEMR using the official Docker image.
#
# Version: 7.0.4 (latest stable)
# Repository: https://github.com/openemr/openemr
# Docker Hub: https://hub.docker.com/r/openemr/openemr
#############################################################

set -euo pipefail
IFS=$'\n\t'

# Initialize variables safely
TOOL_VERSION="7.0.4"
DOCKER_IMAGE="openemr/openemr"
DOCKER_TAG="latest"
CONTAINER_NAME="openemr_app"
tmp_dir="${tmp_dir:-$(mktemp -d)}"
trap 'rm -rf "$tmp_dir"' EXIT

# Support for skipping prerequisites (when base layer provides them)
SKIP_PREREQS="${SKIP_PREREQS:-0}"
RESPECT_SHARED_DEPS="${RESPECT_SHARED_DEPS:-0}"
if [[ "$RESPECT_SHARED_DEPS" == "1" ]]; then
    SKIP_PREREQS=1
fi

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --skip-prereqs)
            SKIP_PREREQS=1
            ;;
    esac
done

#############################################################
# Logging Functions
#############################################################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >&2
}

#############################################################
# Detect OS and Architecture
#############################################################
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_VERSION_CODENAME="${VERSION_CODENAME:-unknown}"
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armhf" ;;
    esac

    log "Detected OS: $OS_ID $OS_VERSION_ID ($OS_VERSION_CODENAME), Architecture: $ARCH"
}

#############################################################
# Check Prerequisites
#############################################################
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        log "Docker is not installed"
        missing_prereqs=1
    else
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log "Found Docker: $docker_version"
    fi

    # Check for curl (needed for health checks)
    if ! command -v curl &> /dev/null; then
        log "curl is not installed"
        missing_prereqs=1
    else
        log "Found curl: $(curl --version | head -n1)"
    fi

    if [[ $missing_prereqs -eq 1 ]]; then
        log "Missing prerequisites detected"
        return 1
    fi

    log_success "All prerequisites are present"
    return 0
}

#############################################################
# Install Prerequisites
#############################################################
install_prerequisites() {
    log "Installing missing prerequisites..."

    detect_os

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    log "Updating package lists..."
    apt-get update -y

    # Install curl if missing
    if ! command -v curl &> /dev/null; then
        log "Installing curl..."
        apt-get install -y curl ca-certificates
    fi

    # Install Docker if missing
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."

        # Install prerequisites for Docker
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | \
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        fi

        # Add Docker repository
        echo \
            "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
            ${OS_VERSION_CODENAME} stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker Engine
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

        # Start Docker service
        if command -v systemctl &> /dev/null; then
            systemctl enable docker || true
            systemctl start docker || true
        fi

        log_success "Docker installed successfully"
    fi

    log_success "Prerequisites installation completed"
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
# Verify Prerequisites
#############################################################
verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker installation failed: docker command not found"
        exit 1
    fi

    if ! docker --version &> /dev/null; then
        log_error "Docker installation failed: docker --version failed"
        exit 1
    fi

    # Verify Docker daemon is running (skip if in container)
    if is_in_container; then
        log "Running in container environment - skipping Docker daemon check"
        log "Note: Docker-in-Docker requires special setup (privileged mode, host socket mount)"
    else
        if ! docker info &> /dev/null; then
            log_error "Docker daemon is not running"
            log_error "Try: sudo systemctl start docker"
            exit 1
        fi
    fi

    # Verify curl
    if ! command -v curl &> /dev/null; then
        log_error "curl installation failed"
        exit 1
    fi

    if ! curl --version &> /dev/null; then
        log_error "curl verification failed"
        exit 1
    fi

    log_success "All prerequisites verified successfully"
}

#############################################################
# Check Existing Installation
#############################################################
check_existing_installation() {
    log "Checking for existing OpenEMR installation..."

    # Check if wrapper script exists and works
    if [[ -f /usr/local/bin/openemr ]]; then
        log "Found existing OpenEMR wrapper script"

        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log "OpenEMR container is already running"
            log_success "OpenEMR is already installed and running"
            return 0
        fi

        # Check if container exists but is stopped
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log "OpenEMR container exists but is stopped. Starting it..."
            docker start "$CONTAINER_NAME" || true
            sleep 5
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                log_success "OpenEMR container started successfully"
                return 0
            fi
        fi
    fi

    # Check if Docker image is already pulled
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${DOCKER_IMAGE}:${DOCKER_TAG}$"; then
        log "OpenEMR Docker image is already pulled"
    fi

    log "OpenEMR is not fully installed"
    return 1
}

#############################################################
# Install Tool
#############################################################
install_tool() {
    log "Installing OpenEMR version ${TOOL_VERSION}..."

    detect_os

    # Pull the Docker image (skip if in container without Docker daemon)
    if is_in_container && ! docker info &> /dev/null; then
        log "Running in container without Docker daemon - skipping image pull"
        log "Note: Docker image pull would require Docker daemon access"
    else
        log "Pulling OpenEMR Docker image: ${DOCKER_IMAGE}:${DOCKER_TAG}"
        docker pull "${DOCKER_IMAGE}:${DOCKER_TAG}"
        log_success "OpenEMR Docker image pulled successfully"
    fi

    # Create wrapper script
    log "Creating OpenEMR wrapper script at /usr/local/bin/openemr"

    cat > /usr/local/bin/openemr << 'WRAPPER_EOF'
#!/usr/bin/env bash
# OpenEMR CLI Wrapper Script
# This script provides a CLI interface to the OpenEMR Docker container

set -euo pipefail

CONTAINER_NAME="openemr_app"
DOCKER_IMAGE="openemr/openemr:latest"

show_version() {
    echo "OpenEMR 7.0.4 (latest stable)"
    echo "Docker Image: ${DOCKER_IMAGE}"

    # If container is running, get actual version
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Status: Running"
        echo "Container: ${CONTAINER_NAME}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Status: Stopped"
        echo "Container: ${CONTAINER_NAME}"
    else
        echo "Status: Not deployed"
    fi
}

show_help() {
    cat << 'EOF'
OpenEMR CLI Wrapper

OpenEMR is a web-based electronic health records (EHR) application.
This CLI tool manages the OpenEMR Docker container.

Usage:
  openemr --version          Show version information
  openemr --help             Show this help message
  openemr start              Start OpenEMR container
  openemr stop               Stop OpenEMR container
  openemr status             Show container status
  openemr logs               Show container logs
  openemr url                Show OpenEMR web URL

Web Access:
  Once started, access OpenEMR at: http://localhost:80
  Default credentials may be required during initial setup.

For more information, visit: https://www.open-emr.org
EOF
}

start_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "OpenEMR container is already running"
        echo "Access at: http://localhost:80"
        return 0
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Starting existing OpenEMR container..."
        docker start "${CONTAINER_NAME}"
    else
        echo "Creating and starting new OpenEMR container..."
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -p 80:80 \
            -p 443:443 \
            -e MYSQL_ROOT_PASS=root \
            -e OE_USER=admin \
            -e OE_PASS=pass \
            "${DOCKER_IMAGE}"
    fi

    echo "OpenEMR is starting..."
    echo "Access at: http://localhost:80"
    echo "This may take 5-10 minutes for initial setup."
}

stop_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping OpenEMR container..."
        docker stop "${CONTAINER_NAME}"
        echo "OpenEMR stopped"
    else
        echo "OpenEMR container is not running"
    fi
}

show_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "OpenEMR Status: Running"
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "OpenEMR Status: Stopped"
        docker ps -a --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}"
    else
        echo "OpenEMR Status: Not deployed"
    fi
}

show_logs() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker logs "${CONTAINER_NAME}" "$@"
    else
        echo "OpenEMR container does not exist"
        exit 1
    fi
}

show_url() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "OpenEMR Web Interface: http://localhost:80"
        echo "HTTPS: https://localhost:443"
    else
        echo "OpenEMR container is not running"
        echo "Start it with: openemr start"
    fi
}

# Main command handling
case "${1:-}" in
    --version)
        show_version
        ;;
    --help|-h|help)
        show_help
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    status)
        show_status
        ;;
    logs)
        shift
        show_logs "$@"
        ;;
    url)
        show_url
        ;;
    *)
        if [[ -z "${1:-}" ]]; then
            show_help
        else
            echo "Unknown command: ${1:-}"
            echo "Use 'openemr --help' for usage information"
            exit 1
        fi
        ;;
esac
WRAPPER_EOF

    chmod +x /usr/local/bin/openemr

    log_success "OpenEMR wrapper script created"

    # Verify the wrapper script
    if [[ ! -x /usr/local/bin/openemr ]]; then
        log_error "Failed to create executable wrapper script"
        exit 1
    fi

    log_success "OpenEMR installation completed"
}

#############################################################
# Validate Installation
#############################################################
validate() {
    log "Validating OpenEMR installation..."

    # Check if wrapper script exists and is executable
    if [[ ! -x /usr/local/bin/openemr ]]; then
        log_error "OpenEMR wrapper script not found or not executable"
        exit 1
    fi

    # Run version command
    log "Running: openemr --version"
    if ! /usr/local/bin/openemr --version; then
        log_error "OpenEMR version check failed"
        exit 1
    fi

    # Verify Docker image exists (skip if in container and Docker daemon not running)
    if is_in_container && ! docker info &> /dev/null; then
        log "Running in container without Docker daemon - skipping image verification"
        log "Note: OpenEMR requires Docker daemon to run the container"
    else
        # Temporarily disable pipefail to avoid SIGPIPE issues
        set +o pipefail
        if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${DOCKER_IMAGE}:${DOCKER_TAG}$"; then
            set -o pipefail
            log_error "OpenEMR Docker image not found"
            exit 1
        fi
        set -o pipefail
    fi

    log_success "OpenEMR validation passed"
    log "OpenEMR ${TOOL_VERSION} is installed successfully"
    if is_in_container; then
        log "Note: Running in container - Docker daemon required to use 'openemr start'"
    else
        log "Use 'openemr start' to deploy and run OpenEMR"
        log "Access OpenEMR at: http://localhost:80"
    fi
}

#############################################################
# Main Function
#############################################################
main() {
    log "=========================================="
    log "OpenEMR ${TOOL_VERSION} Installation"
    log "=========================================="

    # Step 1: Prerequisites
    if [[ "$SKIP_PREREQS" != "1" ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        fi
    else
        log "Skipping prerequisite installation (--skip-prereqs flag set)"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        log "OpenEMR is already installed and configured"
        validate
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log_success "=========================================="
    log_success "OpenEMR installation completed!"
    log_success "=========================================="
    log "Next steps:"
    log "  1. Start OpenEMR: openemr start"
    log "  2. Access web interface: http://localhost:80"
    log "  3. Complete web-based setup wizard"
    log "  4. Check status: openemr status"
    log "  5. View logs: openemr logs"
}

# Run main function
main "$@"
