# Solutions Team Install Standards

## Overview
This document defines the installation standards for all tools deployed by the Solutions Team.

## General Requirements

1. **Idempotency**: All installation scripts must be idempotent - running them multiple times should have no effect if the tool is already installed.

2. **Version Pinning**: Always pin specific versions. Never use "latest" or unpinned versions.

3. **Non-Interactive**: All installations must be non-interactive. Use appropriate flags (e.g., `DEBIAN_FRONTEND=noninteractive`).

4. **Verification**: All downloads must be verified using checksums or GPG signatures.

5. **Clean Up**: Clean package manager caches after installation to minimize image size.

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
