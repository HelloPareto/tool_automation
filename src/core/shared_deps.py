"""
Shared dependency aggregation for multi-tool composition.
"""

import json
import logging
from pathlib import Path
from typing import Dict, List, Set, Tuple


class SharedDependencyAggregator:
    """Aggregates per-tool manifests into a shared dependency set and emits a shared installer."""

    def __init__(self, run_base_path: Path):
        self.logger = logging.getLogger(__name__)
        self.run_base_path = Path(run_base_path)
        self.tools_dir = self.run_base_path / "tools"
        self.shared_dir = self.run_base_path / "shared"
        self.shared_dir.mkdir(parents=True, exist_ok=True)

    def _find_manifests(self) -> List[Path]:
        manifests: List[Path] = []
        if not self.tools_dir.exists():
            return manifests
        for tool_dir in self.tools_dir.iterdir():
            if tool_dir.is_dir():
                manifest_path = tool_dir / "tool_manifest.json"
                if manifest_path.exists():
                    manifests.append(manifest_path)
        return manifests

    def _load_manifest(self, path: Path) -> Dict:
        try:
            return json.loads(path.read_text())
        except Exception as exc:
            self.logger.warning(f"Failed to load manifest {path}: {exc}")
            return {}

    def aggregate(self) -> Dict:
        apt: Set[str] = set()
        runtimes: Set[str] = set()
        libs: Set[str] = set()
        services: Set[str] = set()
        env_path_entries: Set[str] = set()
        python_libs: Set[str] = set()

        manifests = self._find_manifests()
        for mpath in manifests:
            data = self._load_manifest(mpath)
            prereq = data.get("prerequisites", {})
            apt.update(prereq.get("apt", []) or [])
            runtimes.update(prereq.get("runtimes", []) or [])
            libs.update(prereq.get("libs", []) or [])
            services.update(prereq.get("services", []) or [])
            env = data.get("env_exports", {}) or {}
            for entry in env.get("PATH", []) or []:
                env_path_entries.add(entry)

        # Normalize generic/alias names and split python-only libs out
        apt_norm, python_norm, unknown = self._normalize_shared_requirements(apt, libs)

        aggregated = {
            "apt": sorted(apt_norm),
            "runtimes": sorted(runtimes),
            "libs": sorted(libs),  # raw libs for reference
            "python": sorted(python_norm),
            "unknown": sorted(unknown),
            "services": sorted(services),
            "env": {"PATH": sorted(env_path_entries)}
        }
        # Save aggregated manifest
        (self.shared_dir / "shared_manifest.json").write_text(json.dumps(aggregated, indent=2))
        return aggregated

    def _runtime_apt_map(self) -> Dict[str, List[str]]:
        # Conservative runtime providers via apt; customize as needed
        return {
            "python": ["python3", "python3-pip", "python3-venv"],
            "node": ["nodejs", "npm"],
            "go": ["golang"],
            "java": ["openjdk-11-jre-headless"],
            "rust": ["rustc", "cargo"],
            "dotnet": ["dotnet-sdk-6.0"],
        }

    def _normalize_shared_requirements(self, apt: Set[str], libs: Set[str]) -> Tuple[Set[str], Set[str], Set[str]]:
        """Normalize common aliases to Debian/Ubuntu package names.

        Returns (apt_pkgs, python_only, unknown)
        """
        apt_pkgs: Set[str] = set()
        python_only: Set[str] = set()
        unknown: Set[str] = set()

        # Aliases for known meta-libs → apt packages
        alias_map = {
            "gdal": ["gdal-bin", "libgdal-dev"],
            "cartopy": ["python3-cartopy"],  # python package; skip to python_only
            "geopandas": ["python3-geopandas"],  # python package
            "h5py": ["python3-h5py"],  # python package
            "libboost": ["libboost-all-dev"],
            "libcurl": ["libcurl4", "libcurl4-openssl-dev"],
            "libffi": ["libffi-dev"],
            "libfontconfig": ["libfontconfig1-dev"],
            "libfreetype": ["libfreetype6-dev"],
            "libfribidi": ["libfribidi-dev"],
            "libharfbuzz": ["libharfbuzz-dev"],
            "libjpeg": ["libjpeg-dev"],
            "libkrb5": ["libkrb5-dev"],
            "libpng": ["libpng-dev"],
            "libpq": ["libpq-dev"],
            "libsasl2": ["libsasl2-dev"],
            "libssl": ["libssl-dev"],
            "libtiff": ["libtiff5-dev"],
            "libxml2": ["libxml2-dev"],
            "libxslt": ["libxslt1-dev"],
            "zlib": ["zlib1g-dev"],
            "netcdf4": ["libnetcdf-dev"],
        }

        # Python-only identifiers to exclude from apt layer
        python_names = {"cartopy", "geopandas", "h5py"}

        # Direct apt list normalization (e.g., libsasl2 → libsasl2-dev)
        for a in apt:
            key = a.strip()
            lk = key.lower()
            if lk in alias_map:
                # If alias maps to python packages, put into python_only
                mapped = alias_map[lk]
                if any(pkg.startswith("python3-") for pkg in mapped):
                    python_only.add(key)
                else:
                    apt_pkgs.update(mapped)
            elif lk in python_names:
                python_only.add(key)
            else:
                apt_pkgs.add(key)

        # Library names normalization
        for l in libs:
            key = l.strip()
            lk = key.lower()
            if lk in python_names:
                python_only.add(key)
                continue
            if lk in alias_map:
                mapped = alias_map[lk]
                # Only include non-python apt packages here
                apt_pkgs.update([m for m in mapped if not m.startswith("python3-")])
            else:
                # If it looks like an apt libdev name, pass through; otherwise mark unknown
                if lk.startswith("lib") or lk.endswith("-dev"):
                    apt_pkgs.add(key)
                else:
                    unknown.add(key)

        # Cleanup: remove invalid generic names if better dev packages exist
        replacements = {
            "libsasl2": "libsasl2-dev",
            "libssl": "libssl-dev",
            "libpng": "libpng-dev",
            "libtiff": "libtiff5-dev",
            "libxml2": "libxml2-dev",
            "libxslt": "libxslt1-dev",
        }
        for bad, good in replacements.items():
            if bad in apt_pkgs:
                apt_pkgs.discard(bad)
                apt_pkgs.add(good)

        return apt_pkgs, python_only, unknown

    def _generate_script(self, aggregated: Dict) -> str:
        apt_pkgs = set(aggregated.get("apt", []))
        # Note: aggregated["libs"] are raw names; installation aliases resolved into apt_pkgs
        runtimes = aggregated.get("runtimes", [])

        runtime_map = self._runtime_apt_map()
        for rt in runtimes:
            apt_pkgs.update(runtime_map.get(rt, []))

        all_apt = sorted(apt_pkgs)

        apt_install_block = ""
        if all_apt:
            # Single apt transaction; no apt clean here to preserve cache during multi-tool composition
            pkgs = " ".join(all_apt)
            apt_install_block = f"""
    if [ ! -d /var/lib/apt/lists ] || [ -z "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]; then
        log "Refreshing apt lists..."
        apt-get update -y
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y {pkgs}
    # Refresh dynamic linker cache to pick up newly installed libs
    ldconfig
"""

        path_exports = "".join([f"    export PATH=\"{p}:$PATH\"\n" for p in aggregated.get("env", {}).get("PATH", [])])
        python_note = ""
        if aggregated.get("python"):
            py_list = ", ".join(aggregated["python"])[:200]
            python_note = f"    log \"Python-only libraries to be installed by individual tools: {py_list}\"\n"
        unknown_note = ""
        if aggregated.get("unknown"):
            unk_list = ", ".join(aggregated["unknown"])[:200]
            unknown_note = f"    log \"Unknown/alias deps skipped in shared layer: {unk_list}\"\n"

        script = f"""#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() {{
    echo "[shared][$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}}

ensure_root() {{
    if [ "$(id -u)" -ne 0 ]; then
        log "This script must run as root."
        exit 1
    fi
}}

install_shared_dependencies() {{
{apt_install_block}
{path_exports}
{python_note}{unknown_note}
    log "Shared dependencies installed."
}}

main() {{
    log "Starting shared setup..."
    ensure_root
    install_shared_dependencies
    log "Shared setup completed successfully."
}}

main "$@"
"""
        return script

    def write_shared_setup(self, aggregated: Dict) -> Path:
        script = self._generate_script(aggregated)
        out_path = self.shared_dir / "shared_setup.sh"
        out_path.write_text(script)
        out_path.chmod(0o755)
        self.logger.info(f"Wrote shared setup to {out_path}")
        return out_path

    def aggregate_and_write(self) -> Tuple[Dict, Path]:
        aggregated = self.aggregate()
        script_path = self.write_shared_setup(aggregated)
        return aggregated, script_path


