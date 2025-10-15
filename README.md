## Tool Installation Automation System (Claude Built‑in Tools)

A production‑grade system to generate, validate, and test idempotent installers (`tool_setup.sh`) for tools discovered from GitHub repositories listed in Google Sheets. Claude Code (Agent SDK) performs repository analysis, prerequisite detection, script authoring, linting, and Docker testing using its built‑in tools.

---

### ⭐ Highlights
- GitHub‑focused analysis (web search scoped to the repo; clones if needed)
- Idempotent, POSIX‑compliant installers with prerequisite handling
- Static validation (shellcheck, bash -n)
- Container validation: build base image, COPY the script, run at container runtime
- Artifacts per run with provenance and complexity assessment
- Scales with concurrency and rate‑limit aware GitHub access

---

### 🧭 Architecture (Current)
```
Google Sheet (pending/failed tools only)
   │   columns: github_url, status
   ▼
Orchestrator (Python)
   │  - read sheet (filters pending/failed)
   │  - minimal GitHub metadata via GitHub API (name/desc/version)
   │  - pass tool spec + standards + base Dockerfile to Claude
   ▼
Claude Agent (Built‑in Tools)
   1) Analyze repo (GitHub‑focused web search; clone if needed)
   2) Detect & install prerequisites (Python/Node/Go/Build tools/etc.)
   3) Author script: artifacts/runs/<run_id>/tools/<tool>/tool_setup.sh
   4) Lint: shellcheck + bash -n
   5) Docker test:
      - Build image from base.Dockerfile (COPY script only)
      - Run container: execute script, then validate_cmd
   6) Self‑heal on failures (per‑tool):
      - Safe initialization under `set -euo pipefail`; avoid unbound variables
      - Runtime linkage checks with `ldd`; map missing `.so` to Ubuntu packages; install; `ldconfig`; recheck
      - Fix quoting/validation issues; retry
   7) Complexity assessment → claude_result.json
   8) Save artifacts, update Google Sheet status
   ▼
Artifacts
   - runs/<run_id>/summary.json
   - runs/<run_id>/tools/<tool>/{tool_setup.sh, claude_result.json}
```

---

### 📂 Project Structure (key paths)
```
.
├─ main.py                         # Entry point (V3)
├─ config/
│  ├─ base.Dockerfile             # Base image used for Docker tests
│  ├─ install_standards.md        # Solutions Team install standards
│  ├─ acceptance_checklist.yaml   # Acceptance criteria
│  └─ settings.py                 # Pydantic Settings models
├─ src/
│  ├─ core/
│  │  ├─ orchestrator.py          # V3 orchestration (built‑in tools)
│  │  ├─ artifact_manager.py
│  │  ├─ claude_tools.py          # Built‑in tool wrappers
│  │  ├─ docker_runner.py         # (legacy helper; V3 prefers Claude Bash)
│  │  └─ script_validator.py
│  ├─ integrations/
│  │  ├─ claude_agent.py          # ClaudeInstallationAgent (V3)
│  │  └─ google_sheets.py         # Google Sheets integration
│  ├─ analyzers/
│  │  └─ github_analyzer.py       # Simplified: basic repo metadata only
│  └─ models/                     # Pydantic models
└─ artifacts/
   └─ runs/<run_id>/
      ├─ summary.json
      └─ tools/<tool>/
         ├─ tool_setup.sh
         └─ claude_result.json
```

---

### ✅ Requirements
- Python 3.9+
- Docker installed and running
- Git installed (for repo clone fallback)
- shellcheck installed (recommended)
- Anthropic API key (env `ANTHROPIC_API_KEY`)
- Optional GitHub token (env `GITHUB_TOKEN`) for higher API limits

---

### 🔐 Environment
Create `.env` with:
```
ANTHROPIC_API_KEY=sk-ant-...
# Optional but recommended to avoid GitHub rate limits
GITHUB_TOKEN=ghp_...
```

---

### ⚙️ Configuration
`config.json` example:
```json
{
  "google_sheets": {
    "credentials_path": "creds/service-account.json",
    "spreadsheet_id": "YOUR_SHEET_ID",
    "sheet_name": "Finance"
  },
  "claude": {
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 10000,
    "temperature": 0.2,
    "max_concurrent_jobs": 5,
    "retry_attempts": 3,
    "retry_delay_seconds": 2.0
  },
  "docker": {
    "base_image": "ubuntu:22.04",
    "build_timeout": 1800,
    "run_timeout": 900,
    "cleanup_containers": true
  },
  "artifacts": { "base_path": "artifacts", "keep_failed_attempts": true },
  "logging": { "level": "INFO", "file_path": "logs/tool_installer.log" },
  "dry_run": false,
  "parallel_jobs": 5
}
```
Notes:
- Timeouts allow long builds (up to 30 minutes)
- `sheet_name` can be overridden by `--sheet-name` CLI arg (optional)

---

### 🧪 Setup
```bash
# Clone and enter
git clone <repo>
cd tool_code_automation

# Create & activate venv (named "env")
python -m venv env
source env/bin/activate

# Install deps
pip install -r requirements.txt
```

---

### 🚀 Run
- Dry run with mock data (no Sheets, no Docker):
```bash
python main.py --mock-sheets --dry-run --log-level INFO --max-concurrent 2
```

- Real run with Google Sheets:
```bash
python main.py --config config.json --max-concurrent 4
```

- Override sheet name (optional):
```bash
python main.py --config config.json --sheet-name "Finance"
```

- Notes:
  - On Apple Silicon, Docker builds target `linux/amd64` automatically in Claude’s flow
  - Build output uses `--progress=plain` for verbose logs

#### End‑to‑end with automated multi‑tool validation
- Full run including composition and Claude‑driven validation with self‑healing:
```bash
python main.py --config config.json --log-level INFO --reprocess-all --compose-validate
```
Behavior:
- Per‑tool: Claude analyzes repo, generates `tool_setup.sh` and `tool_manifest.json`, lints, Docker‑tests, and self‑heals common issues (unbound variables, missing `.so` via apt + `ldconfig`, quoting).
- Shared deps: Aggregator creates `shared/shared_manifest.json` and `shared/shared_setup.sh` (runs `ldconfig` after apt installs).
- Composition: Composer generates `compose/Dockerfile` and `compose/run_all.sh` (runs `shared_setup.sh` then each `tool_setup.sh --skip-prereqs`, then validations). Quoting handled robustly.
- Validation: Claude builds the composed image and runs the container; on failure it diagnoses, edits, rebuilds, and retries (up to 2x) until success.

---

### 🧱 Artifacts
Per run:
```
artifacts/runs/<run_id>/
  summary.json
  tools/<tool>/
    tool_setup.sh
    claude_result.json
    tool_manifest.json
  shared/
    shared_manifest.json
    shared_setup.sh
  compose/
    Dockerfile
    run_all.sh
    tools/...
```
`claude_result.json` includes `complexity_assessment`, e.g.:
```json
{
  "complexity_assessment": {
    "summary": "Medium complexity. Binary release requiring arch detection and checksum verification.",
    "score": 5,
    "key_factors": ["arch-specific", "checksum", "multi-step"],
    "installation_method": "binary",
    "prerequisites_count": 3,
    "requires_compilation": false
  }
}
```

---

### 🤖 What Claude Does (per tool)
1. Research installation for the specific GitHub URL (prefers official repo docs)
2. Clone repo if needed for deeper analysis; read README/INSTALL, setup files, etc.
3. Detect prerequisites; generate an idempotent `tool_setup.sh` with:
   - check_prerequisites → install_prerequisites → verify_prerequisites
   - check_existing_installation → install_tool → validate
4. Lint the script (`shellcheck`, `bash -n`)
5. Docker test:
   - Build image from `config/base.Dockerfile`
   - COPY the script only (no RUN during build)
   - Run container and execute: `/workspace/tool_setup.sh && <validate_cmd>`
6. Self‑heal on failures:
   - Initialize variables safely; add temp dir and trap cleanup
   - Use `ldd` to find missing libs → apt install correct packages for the detected base OS → `ldconfig` → recheck
   - Fix quoting/validation commands; retry
7. Write artifacts and a complexity assessment

---

### 📑 Google Sheets Format (GitHub URLs)
- Columns: `github_url`, `status`
- The system:
  - Filters to `pending` or `failed`
  - Fetches minimal repo info (name/description/latest release)
  - Lets Claude decide install method dynamically
  - Updates status and artifact path on completion

---

### 🛠️ Troubleshooting
- Docker build takes too long
  - Timeouts increased to 30 min build / 15 min run via config
  - Claude uses `--progress=plain` for visibility
- GitHub API rate‑limited (60/hr)
  - Set `GITHUB_TOKEN` (5,000/hr)
- KeyError in summary
  - Early return path includes `orchestrator_version` and `run_id` (fixed)
- Script not created for some tools
  - Artifacts path made absolute; Claude writes to `artifacts/runs/<run_id>/tools/<tool>`
- Apple Silicon builds
  - Docker build uses `--platform linux/amd64`

---

### 📌 Notes
- Legacy V1/V2 code paths have been removed.
- Dockerfiles in repo root are optional; current flow builds ephemeral test images from `config/base.Dockerfile`.

---

### 📜 License
Internal project (add license if needed).

---

### 🔗 Multi‑tool Composition (shared deps + per‑tool installers)

```
Google Sheet (pending/failed tools)
   │
   ▼
Claude per‑tool runs → tools/<tool>/{tool_setup.sh, tool_manifest.json}
   │
   ▼
Aggregator → shared/shared_manifest.json → shared/shared_setup.sh
   │
   ▼
Composer → compose/{Dockerfile, run_all.sh, tools/...}
   │
   ▼
Docker build image (copy installers only)
   │
   ▼
Docker run container → run_all.sh
   1) shared_setup.sh (install deduped system deps)
   2) for each tool: tool_setup.sh --skip-prereqs → validate_cmd
```

- **shared_setup.sh**: installs deduplicated system prerequisites once (apt packages, runtimes, libs, PATH exports). No background services; no apt cache cleaning.
- **run_all.sh**: executes the multi‑tool plan inside the container: runs `shared_setup.sh`, then each `tool_setup.sh` with `--skip-prereqs`, then each tool’s `validate_cmd`; prints `COMPOSE_VALIDATION_SUCCESS` at the end.
- **Artifacts** (per run):
  - `artifacts/runs/<run_id>/shared/{shared_manifest.json, shared_setup.sh}`
  - `artifacts/runs/<run_id>/compose/{Dockerfile, run_all.sh, tools/...}`

Commands (latest run example):
```bash
# Build composed image
docker build --platform linux/amd64 --progress=plain \
  -t tools_compose:latest artifacts/runs/<run_id>/compose

# Install+validate all tools inside the container
docker run --rm -e DEBIAN_FRONTEND=noninteractive \
  tools_compose:latest bash -lc "/workspace/run_all.sh"
```

Notes:
- Tool scripts must support `--skip-prereqs` and avoid `apt-get clean`; services should not start within tool scripts.
- The composer quotes validation commands safely; Python validations can use `python3 -c "import pkg; print(pkg.__version__)"`.
- Apple Silicon builds: base workflow builds for `linux/amd64`.
 - `shared_setup.sh` runs `ldconfig` after apt installs to refresh the dynamic linker cache.
