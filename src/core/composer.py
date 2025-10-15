"""
Multi-tool composition: generate a composed Dockerfile and run_all.sh that
first runs shared_setup.sh, then installs each tool with --skip-prereqs, and
validates each tool.
"""

import json
import logging
import shutil
from pathlib import Path
from typing import Dict, List, Tuple


class MultiToolComposer:
    """Creates a composed image build context for multi-tool installation."""

    def __init__(self, run_base_path: Path, base_dockerfile_content: str):
        self.logger = logging.getLogger(__name__)
        self.run_base_path = Path(run_base_path)
        self.tools_dir = self.run_base_path / "tools"
        self.shared_dir = self.run_base_path / "shared"
        self.compose_dir = self.run_base_path / "compose"
        self.compose_dir.mkdir(parents=True, exist_ok=True)
        self.base_dockerfile_content = base_dockerfile_content or "FROM debian:12-slim\nWORKDIR /workspace\n"

    def _list_tools(self) -> List[str]:
        names: List[str] = []
        if self.tools_dir.exists():
            for tdir in sorted(self.tools_dir.iterdir()):
                if tdir.is_dir() and (tdir / "tool_setup.sh").exists():
                    names.append(tdir.name)
        return names

    def _read_manifest(self, tool_name: str) -> Dict:
        path = self.tools_dir / tool_name / "tool_manifest.json"
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text())
        except Exception:
            return {}

    def _copy_inputs(self, tool_names: List[str]) -> None:
        # Copy shared setup
        shared_src = self.shared_dir / "shared_setup.sh"
        if shared_src.exists():
            shutil.copy2(shared_src, self.compose_dir / "shared_setup.sh")
        # Copy tools
        tools_out = self.compose_dir / "tools"
        tools_out.mkdir(parents=True, exist_ok=True)
        for name in tool_names:
            src = self.tools_dir / name / "tool_setup.sh"
            if src.exists():
                dst_dir = tools_out / name
                dst_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst_dir / "tool_setup.sh")

    def _generate_run_all(self, tool_names: List[str]) -> Path:
        lines: List[str] = []
        lines.append("#!/usr/bin/env bash")
        lines.append("set -euo pipefail")
        lines.append("IFS=$'\n\t'")
        lines.append("log() { echo \"[compose][$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*\"; }")
        lines.append("export DEBIAN_FRONTEND=noninteractive")
        lines.append("chmod +x /workspace/shared_setup.sh || true")
        lines.append("log 'Running shared_setup.sh' && /workspace/shared_setup.sh")
        for name in tool_names:
            lines.append(f"log 'Installing {name}'")
            lines.append(f"chmod +x /workspace/tools/{name}/tool_setup.sh")
            # Prefer --skip-prereqs; fall back to plain if script doesn't support it
            lines.append(f"/workspace/tools/{name}/tool_setup.sh --skip-prereqs || /workspace/tools/{name}/tool_setup.sh")
            manifest = self._read_manifest(name)
            validate_cmd = manifest.get("validate_cmd") or f"{name} --version"
            # Run validation after install with safe quoting
            if '"' in validate_cmd and "'" not in validate_cmd:
                lines.append(f"log 'Validating {name}' && bash -lc '{validate_cmd}'")
            elif "'" in validate_cmd and '"' not in validate_cmd:
                lines.append(f"log 'Validating {name}' && bash -lc \"{validate_cmd}\"")
            else:
                esc = validate_cmd.replace('"', '\\"')
                lines.append(f"log 'Validating {name}' && bash -lc \"{esc}\"")
        run_all_path = self.compose_dir / "run_all.sh"
        run_all_path.write_text("\n".join(lines) + "\n")
        run_all_path.chmod(0o755)
        return run_all_path

    def _generate_dockerfile(self, tool_names: List[str]) -> Path:
        df_lines: List[str] = []
        # Base content
        df_lines.append(self.base_dockerfile_content.rstrip())
        # Ensure workspace exists
        df_lines.append("RUN mkdir -p /workspace && chmod 755 /workspace")
        # Copy shared and tools
        df_lines.append("COPY shared_setup.sh /workspace/shared_setup.sh")
        for name in tool_names:
            df_lines.append(f"COPY tools/{name}/tool_setup.sh /workspace/tools/{name}/tool_setup.sh")
        df_lines.append("COPY run_all.sh /workspace/run_all.sh")
        df_lines.append("RUN chmod +x /workspace/run_all.sh /workspace/shared_setup.sh || true")
        # Do not RUN installers during build; they will run at container start
        dockerfile_path = self.compose_dir / "Dockerfile"
        dockerfile_path.write_text("\n".join(df_lines) + "\n")
        return dockerfile_path

    def create_artifacts(self) -> Tuple[List[str], Path, Path, Path]:
        tool_names = self._list_tools()
        self._copy_inputs(tool_names)
        run_all = self._generate_run_all(tool_names)
        dockerfile = self._generate_dockerfile(tool_names)
        return tool_names, self.compose_dir, run_all, dockerfile


