#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'
log() { echo "[compose][$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
export DEBIAN_FRONTEND=noninteractive
chmod +x /workspace/shared_setup.sh || true
log 'Running shared_setup.sh' && /workspace/shared_setup.sh
log 'Installing core'
chmod +x /workspace/tools/core/tool_setup.sh
/workspace/tools/core/tool_setup.sh --skip-prereqs || /workspace/tools/core/tool_setup.sh
log 'Validating core' && bash -lc "core --version"
log 'Installing metabase'
chmod +x /workspace/tools/metabase/tool_setup.sh
/workspace/tools/metabase/tool_setup.sh --skip-prereqs || /workspace/tools/metabase/tool_setup.sh
log 'Validating metabase' && bash -lc "metabase --version"
log 'Installing pymc'
chmod +x /workspace/tools/pymc/tool_setup.sh
/workspace/tools/pymc/tool_setup.sh --skip-prereqs || /workspace/tools/pymc/tool_setup.sh
log 'Validating pymc' && bash -lc 'python3 -c "import pymc; print(pymc.__version__)"'
echo "COMPOSE_VALIDATION_SUCCESS"
