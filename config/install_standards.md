# Solutions Team Install Standards

## Overview
This document defines the installation standards for all tools deployed by the Solutions Team.

## General Requirements

1. **Prerequisite Detection & Installation**: Before installing any tool, detect and install all required prerequisites (programming languages, compilers, libraries, etc.). Always verify prerequisite installations before proceeding.

2. **Idempotency**: All installation scripts must be idempotent - running them multiple times should have no effect if the tool is already installed.

3. **Version Pinning**: Always pin specific versions. Never use "latest" or unpinned versions.

4. **Non-Interactive**: All installations must be non-interactive. Use appropriate flags (e.g., `DEBIAN_FRONTEND=noninteractive`).

5. **Verification**: All downloads must be verified using checksums or GPG signatures.

6. **Clean Up**: Clean package manager caches after installation to minimize image size.

## Prerequisite Management

### Detection Strategy
1. **Analyze tool requirements**: Determine what programming languages, runtimes, or libraries the tool needs
2. **Check existing installations**: Use `command -v`, `which`, or version checks to detect if prerequisites exist
3. **Install if missing**: Only install prerequisites that are not already present
4. **Verify installation**: After installing prerequisites, verify they work correctly
5. **Proceed with tool**: Only after all prerequisites are satisfied, install the actual tool

### Common Prerequisites

#### Python
- Check: `command -v python3` or `python3 --version`
- Install: `apt-get install -y python3 python3-pip python3-venv`
- Verify: `python3 --version && pip3 --version`

#### Node.js / NPM
- Check: `command -v node` or `node --version`
- Install: Use official NodeSource repository or `apt-get install -y nodejs npm`
- Verify: `node --version && npm --version`

#### Go
- Check: `command -v go` or `go version`
- Install: Download from official releases, extract to `/usr/local/go`
- Verify: `go version`

#### Java
- Check: `command -v java` or `java -version`
- Install: `apt-get install -y openjdk-11-jre-headless` (or appropriate version)
- Verify: `java -version`

#### Rust
- Check: `command -v rustc` or `rustc --version`
- Install: Use rustup or system package manager
- Verify: `rustc --version && cargo --version`

#### Build Tools
- Check: `command -v gcc` or `command -v make`
- Install: `apt-get install -y build-essential`
- Verify: `gcc --version && make --version`

#### Docker
- Check: `command -v docker` or `docker --version`
- Install: Follow official Docker installation for the platform
- Verify: `docker --version`

## Package Manager Standards

### APT (Debian/Ubuntu)
- Always run `apt-get update` before installing
- Use `apt-get install -y` for non-interactive installation
- Clean up with `apt-get clean && rm -rf /var/lib/apt/lists/*`
- GPG keys must be stored under `/usr/share/keyrings/`
- Repository configurations go in `/etc/apt/sources.list.d/`

### Direct Downloads
- Verify checksums (SHA256 minimum) or GPG signatures
- Download to `/tmp` for installation
- Clean up downloaded files after installation

## Directory Standards
- Binaries: `/usr/local/bin/`
- Configuration: `/etc/{tool}/`
- Data: `/var/lib/{tool}/`
- Logs: `/var/log/{tool}/`

## Validation Requirements
- Every installation must include a `validate()` function
- Validation must check the installed version matches the requested version
- Validation must exit with code 0 on success, non-zero on failure

## Logging Standards
- Log all major steps
- Include timestamps
- Provide clear error messages with remediation steps

## Security Standards
- Never embed secrets or credentials
- Use HTTPS for all downloads
- Verify all GPG keys from official sources
- Set appropriate file permissions (755 for executables, 644 for configs)
