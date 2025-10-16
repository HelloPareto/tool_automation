#!/bin/bash
################################################################################
# Apache Superset Helm Chart Installation Script
# Version: superset-helm-chart-0.15.1
# Description: Installs Apache Superset Helm chart for Kubernetes deployment
################################################################################

set -euo pipefail

# Configuration
readonly TOOL_NAME="superset"
readonly TOOL_VERSION="superset-helm-chart-0.15.1"
readonly HELM_CHART_VERSION="0.15.1"
readonly HELM_VERSION="3.16.3"
readonly HELM_REPO_NAME="superset"
readonly HELM_REPO_URL="https://apache.github.io/superset"
readonly HELM_BINARY="/usr/local/bin/helm"

# Check for skip prerequisites flag
SKIP_PREREQS=0
if [[ "${1:-}" == "--skip-prereqs" ]] || [[ "${RESPECT_SHARED_DEPS:-0}" == "1" ]]; then
    SKIP_PREREQS=1
fi

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
# Prerequisite Management
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    local missing_prereqs=0

    # Check for curl
    if ! command -v curl &> /dev/null; then
        log "curl is not installed"
        missing_prereqs=1
    else
        log "Found curl: $(curl --version | head -n1)"
    fi

    # Check for wget
    if ! command -v wget &> /dev/null; then
        log "wget is not installed"
        missing_prereqs=1
    else
        log "Found wget: $(wget --version | head -n1)"
    fi

    # Check for tar
    if ! command -v tar &> /dev/null; then
        log "tar is not installed"
        missing_prereqs=1
    else
        log "Found tar: $(tar --version | head -n1)"
    fi

    # Check for git (needed for chart version 0.15.1)
    if ! command -v git &> /dev/null; then
        log "git is not installed"
        missing_prereqs=1
    else
        log "Found git: $(git --version)"
    fi

    if [[ $missing_prereqs -eq 0 ]]; then
        log "All prerequisites are already installed"
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

    # Install required packages
    log "Installing curl, wget, tar, and git..."
    apt-get install -y -qq \
        curl \
        wget \
        tar \
        git \
        ca-certificates \
        gnupg2

    log "Prerequisites installed successfully"
}

verify_prerequisites() {
    log "Verifying prerequisites..."

    # Verify curl
    if ! curl --version &> /dev/null; then
        log_error "curl verification failed"
        exit 1
    fi
    log "curl verified: $(curl --version | head -n1)"

    # Verify wget
    if ! wget --version &> /dev/null; then
        log_error "wget verification failed"
        exit 1
    fi
    log "wget verified: $(wget --version | head -n1)"

    # Verify tar
    if ! tar --version &> /dev/null; then
        log_error "tar verification failed"
        exit 1
    fi
    log "tar verified: $(tar --version | head -n1)"

    # Verify git
    if ! git --version &> /dev/null; then
        log_error "git verification failed"
        exit 1
    fi
    log "git verified: $(git --version)"

    log_success "All prerequisites verified successfully"
}

################################################################################
# Installation Functions
################################################################################

check_existing_installation() {
    log "Checking for existing Helm installation..."

    if [[ -f "$HELM_BINARY" ]]; then
        local installed_version
        installed_version=$("$HELM_BINARY" version --template='{{.Version}}' 2>/dev/null | sed 's/^v//' || echo "unknown")

        if [[ "$installed_version" == "$HELM_VERSION" ]]; then
            log "Helm $HELM_VERSION is already installed"

            # Check if Superset repo is already added
            if "$HELM_BINARY" repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}[[:space:]]"; then
                log "Superset Helm repository is already configured"
                log_success "Superset Helm chart setup is already complete"
                return 0
            else
                log "Superset Helm repository not configured, will add it"
                return 1
            fi
        else
            log "Found Helm version $installed_version, but need $HELM_VERSION"
            return 1
        fi
    else
        log "Helm is not installed"
        return 1
    fi
}

install_tool() {
    log "Installing Helm $HELM_VERSION..."

    # Determine architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    # Determine OS
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    local helm_tarball="helm-v${HELM_VERSION}-${os}-${arch}.tar.gz"
    local download_url="https://get.helm.sh/${helm_tarball}"
    local checksum_url="${download_url}.sha256sum"

    log "Downloading Helm from $download_url"

    # Download to /tmp
    cd /tmp

    # Download Helm tarball
    if ! curl -fsSL -o "$helm_tarball" "$download_url"; then
        log_error "Failed to download Helm from $download_url"
        exit 1
    fi

    # Download checksum
    if ! curl -fsSL -o "${helm_tarball}.sha256sum" "$checksum_url"; then
        log_error "Failed to download Helm checksum from $checksum_url"
        exit 1
    fi

    # Verify checksum
    log "Verifying checksum..."
    local expected_checksum
    expected_checksum=$(awk '{print $1}' "${helm_tarball}.sha256sum")
    local actual_checksum
    actual_checksum=$(sha256sum "$helm_tarball" | awk '{print $1}')

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        log_error "Checksum verification failed!"
        log_error "Expected: $expected_checksum"
        log_error "Actual: $actual_checksum"
        rm -f "$helm_tarball" "${helm_tarball}.sha256sum"
        exit 1
    fi
    log_success "Checksum verified successfully"

    # Extract Helm binary
    log "Extracting Helm binary..."
    tar -zxf "$helm_tarball"

    # Install to /usr/local/bin
    log "Installing Helm to $HELM_BINARY"
    mv "${os}-${arch}/helm" "$HELM_BINARY"
    chmod 755 "$HELM_BINARY"

    # Clean up
    log "Cleaning up temporary files..."
    rm -rf "$helm_tarball" "${helm_tarball}.sha256sum" "${os}-${arch}"

    log_success "Helm $HELM_VERSION installed successfully"

    # Add Superset Helm repository
    log "Adding Superset Helm repository..."
    "$HELM_BINARY" repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"

    # Update Helm repositories
    log "Updating Helm repositories..."
    "$HELM_BINARY" repo update

    # Verify the chart is available or fetch from GitHub
    log "Verifying Superset chart version $HELM_CHART_VERSION is available..."
    if "$HELM_BINARY" search repo "${HELM_REPO_NAME}/${TOOL_NAME}" --version "$HELM_CHART_VERSION" 2>/dev/null | grep -q "$HELM_CHART_VERSION"; then
        log_success "Superset Helm chart version $HELM_CHART_VERSION is available in Helm repository"
    else
        log "Superset chart version $HELM_CHART_VERSION not found in Helm repository"
        log "Note: Version 0.15.1 was released on GitHub but not published to the Helm repository"
        log "Installing chart directly from GitHub source..."

        # Download and package the chart from GitHub
        local chart_dir="/tmp/superset-helm-${HELM_CHART_VERSION}"
        local github_tag="superset-helm-chart-${HELM_CHART_VERSION}"

        log "Cloning Superset repository at tag $github_tag..."
        git clone --depth 1 --branch "$github_tag" https://github.com/apache/superset.git "$chart_dir"

        # Package the Helm chart
        log "Packaging Helm chart from source..."
        "$HELM_BINARY" dependency update "${chart_dir}/helm/superset"
        "$HELM_BINARY" package "${chart_dir}/helm/superset" -d /tmp

        # Verify the package was created
        if [[ -f "/tmp/superset-${HELM_CHART_VERSION}.tgz" ]]; then
            log_success "Superset Helm chart version $HELM_CHART_VERSION packaged from GitHub source"
            log "Chart package location: /tmp/superset-${HELM_CHART_VERSION}.tgz"
        else
            log_error "Failed to package Superset Helm chart from GitHub source"
            rm -rf "$chart_dir"
            exit 1
        fi

        # Clean up cloned repository
        rm -rf "$chart_dir"
    fi
}

validate() {
    log "Validating Helm installation..."

    # Check if Helm binary exists
    if [[ ! -f "$HELM_BINARY" ]]; then
        log_error "Helm binary not found at $HELM_BINARY"
        exit 1
    fi

    # Check Helm version
    local installed_version
    installed_version=$("$HELM_BINARY" version --template='{{.Version}}' 2>/dev/null | sed 's/^v//' || echo "unknown")

    if [[ "$installed_version" != "$HELM_VERSION" ]]; then
        log_error "Helm version mismatch. Expected: $HELM_VERSION, Found: $installed_version"
        exit 1
    fi

    log "Helm version: v$installed_version"

    # Verify Superset repository is configured
    if ! "$HELM_BINARY" repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}[[:space:]]"; then
        log_error "Superset Helm repository not configured"
        exit 1
    fi

    log "Superset Helm repository: configured"

    # Verify the specific chart version is available (either in repo or as packaged file)
    if "$HELM_BINARY" search repo "${HELM_REPO_NAME}/${TOOL_NAME}" --version "$HELM_CHART_VERSION" 2>/dev/null | grep -q "$HELM_CHART_VERSION"; then
        log "Superset Helm chart version: $HELM_CHART_VERSION (available in repository)"
    elif [[ -f "/tmp/superset-${HELM_CHART_VERSION}.tgz" ]]; then
        log "Superset Helm chart version: $HELM_CHART_VERSION (packaged from GitHub source)"
        log "Chart package: /tmp/superset-${HELM_CHART_VERSION}.tgz"
    else
        log_error "Superset Helm chart version $HELM_CHART_VERSION not available"
        exit 1
    fi

    log_success "Validation completed successfully"
    log_success "Helm $HELM_VERSION with Superset chart $HELM_CHART_VERSION is ready"

    # Display usage information
    echo ""
    echo "============================================"
    echo "Apache Superset Helm Chart Setup Complete"
    echo "============================================"
    echo ""

    if [[ -f "/tmp/superset-${HELM_CHART_VERSION}.tgz" ]]; then
        echo "Note: Version 0.15.1 was packaged from GitHub source as it's not"
        echo "      published to the official Helm repository."
        echo ""
        echo "To deploy Superset to a Kubernetes cluster, use:"
        echo ""
        echo "  helm install my-superset /tmp/superset-${HELM_CHART_VERSION}.tgz \\"
        echo "    --namespace superset \\"
        echo "    --create-namespace"
        echo ""
        echo "For custom configuration, create a values.yaml file and use:"
        echo ""
        echo "  helm install my-superset /tmp/superset-${HELM_CHART_VERSION}.tgz \\"
        echo "    --values values.yaml \\"
        echo "    --namespace superset \\"
        echo "    --create-namespace"
    else
        echo "To deploy Superset to a Kubernetes cluster, use:"
        echo ""
        echo "  helm install my-superset ${HELM_REPO_NAME}/${TOOL_NAME} \\"
        echo "    --version $HELM_CHART_VERSION \\"
        echo "    --namespace superset \\"
        echo "    --create-namespace"
        echo ""
        echo "For custom configuration, create a values.yaml file and use:"
        echo ""
        echo "  helm install my-superset ${HELM_REPO_NAME}/${TOOL_NAME} \\"
        echo "    --version $HELM_CHART_VERSION \\"
        echo "    --values values.yaml \\"
        echo "    --namespace superset \\"
        echo "    --create-namespace"
    fi

    echo ""
    echo "For more information, visit:"
    echo "  https://superset.apache.org/docs/installation/kubernetes/"
    echo ""

    return 0
}

################################################################################
# Main Function
################################################################################

main() {
    log "Starting $TOOL_NAME $TOOL_VERSION installation..."

    # Step 1: Prerequisites
    if [[ $SKIP_PREREQS -eq 0 ]]; then
        if ! check_prerequisites; then
            install_prerequisites
            verify_prerequisites
        fi
    else
        log "Skipping prerequisite installation (--skip-prereqs or RESPECT_SHARED_DEPS=1)"
    fi

    # Step 2: Check if already installed
    if check_existing_installation; then
        validate
        exit 0
    fi

    # Step 3: Install the tool
    install_tool

    # Step 4: Validate
    validate

    log_success "Installation completed successfully"
}

# Run main function
main "$@"
