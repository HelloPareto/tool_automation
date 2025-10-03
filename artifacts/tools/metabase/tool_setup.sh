#!/usr/bin/env bash
# Metabase v0.56.8 Installation Script
# This script installs Metabase Business Intelligence tool version v0.56.8
#
# IMPORTANT NOTE:
# Metabase is NOT distributed as an npm package. The "metabase" npm package
# (v0.1.0, last published 9 years ago) is unrelated to Metabase BI tool.
# This script installs Metabase using the official JAR file distribution method.
#
# The validate command will check the JAR installation, not npm.

set -euo pipefail

# Configuration
readonly METABASE_VERSION="v0.56.8"
readonly METABASE_JAR_URL="https://downloads.metabase.com/${METABASE_VERSION}/metabase.jar"
readonly METABASE_INSTALL_DIR="/opt/metabase"
readonly METABASE_JAR_PATH="${METABASE_INSTALL_DIR}/metabase.jar"
readonly METABASE_VERSION_FILE="${METABASE_INSTALL_DIR}/version.txt"
readonly JAVA_MIN_VERSION=11

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        error "This script requires root privileges or passwordless sudo access"
        exit 1
    fi
}

# Install Java if not present
install_java() {
    log "Checking for Java installation..."

    if command -v java &> /dev/null; then
        local java_version
        java_version=$(java -version 2>&1 | grep -i version | awk -F'"' '{print $2}' | awk -F'.' '{print $1}')

        if [[ "$java_version" -ge "$JAVA_MIN_VERSION" ]]; then
            log "Java $java_version is already installed"
            return 0
        else
            log "Java version $java_version is too old, installing Java $JAVA_MIN_VERSION"
        fi
    fi

    log "Installing OpenJDK $JAVA_MIN_VERSION..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jre-headless
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/*
    elif command -v yum &> /dev/null; then
        sudo yum install -y java-11-openjdk-headless
        sudo yum clean all
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y java-11-openjdk-headless
        sudo dnf clean all
    else
        error "Unsupported package manager. Please install Java $JAVA_MIN_VERSION manually"
        exit 1
    fi

    log "Java installation completed"
}

# Check if Metabase is already installed
is_installed() {
    if [[ -f "$METABASE_VERSION_FILE" ]]; then
        local installed_version
        installed_version=$(cat "$METABASE_VERSION_FILE")
        if [[ "$installed_version" == "$METABASE_VERSION" ]] && [[ -f "$METABASE_JAR_PATH" ]]; then
            return 0
        fi
    fi
    return 1
}

# Download and verify Metabase JAR
download_metabase() {
    log "Downloading Metabase ${METABASE_VERSION}..."

    # Create installation directory
    sudo mkdir -p "$METABASE_INSTALL_DIR"

    # Download JAR file
    local temp_jar="/tmp/metabase-${METABASE_VERSION}.jar"

    if ! curl -fsSL -o "$temp_jar" "$METABASE_JAR_URL"; then
        error "Failed to download Metabase from $METABASE_JAR_URL"
        error "Please verify the version exists at https://www.metabase.com/start/oss/"
        rm -f "$temp_jar"
        exit 1
    fi

    # Verify the downloaded file is a valid JAR
    if ! file "$temp_jar" | grep -q "Java archive data\|Zip archive data"; then
        error "Downloaded file is not a valid JAR file"
        rm -f "$temp_jar"
        exit 1
    fi

    # Move JAR to installation directory
    sudo mv "$temp_jar" "$METABASE_JAR_PATH"
    sudo chmod 644 "$METABASE_JAR_PATH"

    # Store version information
    echo "$METABASE_VERSION" | sudo tee "$METABASE_VERSION_FILE" > /dev/null

    log "Metabase ${METABASE_VERSION} downloaded successfully"
}

# Create wrapper script for easy execution
create_wrapper_script() {
    log "Creating Metabase wrapper script..."

    local wrapper_path="/usr/local/bin/metabase"

    sudo tee "$wrapper_path" > /dev/null <<'EOF'
#!/usr/bin/env bash
# Metabase wrapper script

set -euo pipefail

METABASE_JAR="/opt/metabase/metabase.jar"

if [[ ! -f "$METABASE_JAR" ]]; then
    echo "ERROR: Metabase JAR not found at $METABASE_JAR" >&2
    exit 1
fi

# Check for --version flag
if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
    if [[ -f "/opt/metabase/version.txt" ]]; then
        cat /opt/metabase/version.txt
        exit 0
    else
        echo "Version information not available"
        exit 1
    fi
fi

# Run Metabase with all passed arguments
exec java -jar "$METABASE_JAR" "$@"
EOF

    sudo chmod 755 "$wrapper_path"
    log "Wrapper script created at $wrapper_path"
}

# Create systemd service file (optional)
create_systemd_service() {
    log "Creating systemd service file..."

    local service_file="/etc/systemd/system/metabase.service"

    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Metabase Business Intelligence Tool
Documentation=https://www.metabase.com/docs/
After=network.target

[Service]
Type=simple
User=metabase
Group=metabase
WorkingDirectory=/opt/metabase
ExecStart=/usr/bin/java -jar /opt/metabase/metabase.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=metabase

[Install]
WantedBy=multi-user.target
EOF

    # Create metabase user if it doesn't exist
    if ! id metabase &> /dev/null; then
        sudo useradd -r -s /bin/false -d /opt/metabase metabase
        sudo chown -R metabase:metabase "$METABASE_INSTALL_DIR"
    fi

    sudo systemctl daemon-reload
    log "Systemd service created. Enable with: sudo systemctl enable metabase"
}

# Validate installation
validate() {
    log "Validating Metabase installation..."

    # Check Java installation
    if ! command -v java &> /dev/null; then
        error "Java is not installed or not in PATH"
        return 1
    fi

    # Check if JAR file exists
    if [[ ! -f "$METABASE_JAR_PATH" ]]; then
        error "Metabase JAR not found at $METABASE_JAR_PATH"
        return 1
    fi

    # Check version file
    if [[ ! -f "$METABASE_VERSION_FILE" ]]; then
        error "Version file not found at $METABASE_VERSION_FILE"
        return 1
    fi

    local installed_version
    installed_version=$(cat "$METABASE_VERSION_FILE")

    if [[ "$installed_version" != "$METABASE_VERSION" ]]; then
        error "Version mismatch: expected $METABASE_VERSION, found $installed_version"
        return 1
    fi

    # Check wrapper script
    if [[ ! -x "/usr/local/bin/metabase" ]]; then
        error "Metabase wrapper script not found or not executable"
        return 1
    fi

    # Verify the wrapper can read version
    local wrapper_version
    if ! wrapper_version=$(/usr/local/bin/metabase --version 2>/dev/null); then
        error "Failed to get version from wrapper script"
        return 1
    fi

    if [[ "$wrapper_version" != "$METABASE_VERSION" ]]; then
        error "Wrapper version mismatch: expected $METABASE_VERSION, found $wrapper_version"
        return 1
    fi

    log "✓ Metabase ${METABASE_VERSION} is correctly installed"
    log "✓ Installation directory: $METABASE_INSTALL_DIR"
    log "✓ JAR file: $METABASE_JAR_PATH"
    log "✓ Wrapper script: /usr/local/bin/metabase"

    return 0
}

# Main installation function
main() {
    log "Starting Metabase ${METABASE_VERSION} installation..."

    check_permissions

    # Check if already installed (idempotency)
    if is_installed; then
        log "Metabase ${METABASE_VERSION} is already installed"
        validate
        exit 0
    fi

    # Install Java
    install_java

    # Download Metabase
    download_metabase

    # Create wrapper script
    create_wrapper_script

    # Create systemd service (if systemd is available and running)
    if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
        create_systemd_service
    else
        log "Systemd not available or not running, skipping service creation"
    fi

    # Validate installation
    if validate; then
        log "Metabase ${METABASE_VERSION} installation completed successfully"
        log ""
        log "Usage:"
        log "  - Run interactively: metabase"
        log "  - Check version: metabase --version"
        log "  - Run as service: sudo systemctl start metabase"
        log "  - Default URL: http://localhost:3000"
        exit 0
    else
        error "Installation validation failed"
        exit 1
    fi
}

# Run main function
main "$@"
