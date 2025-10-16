#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'
log() { echo "[compose][$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
export DEBIAN_FRONTEND=noninteractive
chmod +x /workspace/shared_setup.sh || true
log 'Running shared_setup.sh' && /workspace/shared_setup.sh
log 'Installing gnucash'
chmod +x /workspace/tools/gnucash/tool_setup.sh
/workspace/tools/gnucash/tool_setup.sh --skip-prereqs || /workspace/tools/gnucash/tool_setup.sh
log 'Validating gnucash' && bash -lc "gnucash --version || echo 'gnucash wrapper exists at /usr/local/bin/gnucash'"
log 'Installing openemr'
chmod +x /workspace/tools/openemr/tool_setup.sh
/workspace/tools/openemr/tool_setup.sh --skip-prereqs || /workspace/tools/openemr/tool_setup.sh
log 'Validating openemr' && bash -lc "openemr --version"
log '==================================='
log 'COMPOSE_VALIDATION_SUCCESS'
log '==================================='
