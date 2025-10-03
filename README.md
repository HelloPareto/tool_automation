# Tool Installation Automation System

A production-ready system for automating tool installation across multiple environments using Claude AI to generate idempotent, standards-compliant installation scripts.

## 🚀 Overview

This system automates the process of:
1. Reading tool specifications from Google Sheets
2. Generating installation scripts using Claude AI
3. Validating scripts with static analysis
4. Testing installations in Docker containers
5. Storing artifacts and updating status

### High-Level Flow

```
Google Sheet → Orchestrator → (fan-out async) → Claude Code jobs
                                |
                                ├─ standards + base Dockerfile + tool spec (context)
                                ├─ script synthesis → self-review → JSON envelope
                                ├─ shellcheck + bash -n
                                ├─ docker build & run script (install & check)
                                └─ artifacts + logs + status back to Sheet
```

## 📋 Prerequisites

- Python 3.8+
- Docker installed and running
- Google Cloud service account (for Sheets access)
- Anthropic API key
- `shellcheck` installed (optional but recommended)

## 🔧 Installation

1. **Clone the repository:**
```bash
git clone <repository_url>
cd tool_code_automation
```

2. **Create virtual environment:**
```bash
python -m venv env
source env/bin/activate  # On Windows: env\Scripts\activate
```

3. **Install dependencies:**
```bash
pip install -r requirements.txt
```

4. **Install shellcheck (recommended):**
```bash
# Ubuntu/Debian
sudo apt-get install shellcheck

# macOS
brew install shellcheck
```

## ⚙️ Configuration

### 1. Environment Variables

Create a `.env` file:
```bash
ANTHROPIC_API_KEY=your_api_key_here
```

### 2. Google Sheets Setup

1. Create a Google Cloud service account
2. Download the credentials JSON file
3. Share your Google Sheet with the service account email
4. Note your spreadsheet ID from the URL

### 3. Google Sheets Format

Your sheet should have these columns:
- **Name**: Tool name (required)
- **Version**: Version to install (required)
- **ValidateCommand**: Command to validate installation (required)
- **Description**: Tool description (optional)
- **PackageManager**: Package manager to use (optional)
- **RepositoryURL**: Repository URL if applicable (optional)
- **GPGKeyURL**: GPG key URL for verification (optional)
- **Status**: Current status (auto-updated by system)
- **Message**: Status message (auto-updated)
- **ArtifactPath**: Path to artifacts (auto-updated)

### 4. Configuration File (Optional)

Create `config.json`:
```json
{
  "google_sheets": {
    "credentials_path": "path/to/credentials.json",
    "spreadsheet_id": "your-spreadsheet-id",
    "sheet_name": "Tools"
  },
  "claude": {
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 4096,
    "temperature": 0.2,
    "max_concurrent_jobs": 5
  },
  "docker": {
    "base_image": "ubuntu:22.04",
    "build_timeout": 300,
    "run_timeout": 600
  },
  "artifacts": {
    "base_path": "artifacts",
    "keep_failed_attempts": true
  }
}
```

## 🎯 Usage

### Basic Usage

```bash
python main.py \
  --google-creds path/to/credentials.json \
  --spreadsheet-id your-spreadsheet-id
```

### With Configuration File

```bash
python main.py --config config.json
```

### Dry Run Mode

Test without Docker execution:
```bash
python main.py --config config.json --dry-run
```

### Mock Mode (Testing)

Test without Google Sheets:
```bash
python main.py --mock-sheets --dry-run
```

### Advanced Options

```bash
python main.py \
  --google-creds credentials.json \
  --spreadsheet-id your-id \
  --sheet-name "Production Tools" \
  --max-concurrent 10 \
  --artifacts-dir /path/to/artifacts \
  --log-level DEBUG
```

## 📁 Project Structure

```
tool_code_automation/
├── src/
│   ├── core/               # Core business logic
│   │   ├── orchestrator.py # Main orchestration logic
│   │   ├── script_validator.py # Script validation
│   │   ├── docker_runner.py # Docker execution
│   │   └── artifact_manager.py # Artifact storage
│   ├── integrations/       # External integrations
│   │   ├── google_sheets.py # Google Sheets client
│   │   └── claude_client.py # Claude AI client
│   ├── models/             # Pydantic data models
│   │   ├── tool.py        # Tool specifications
│   │   ├── installation.py # Installation results
│   │   └── claude.py      # Claude responses
│   └── utils/              # Utilities
│       └── logging.py     # Logging configuration
├── config/                 # Configuration files
│   ├── settings.py        # Settings model
│   ├── install_standards.md # Installation standards
│   ├── base.Dockerfile    # Base Docker image
│   └── acceptance_checklist.yaml # Validation criteria
├── artifacts/              # Generated artifacts (auto-created)
├── logs/                   # Application logs (auto-created)
├── tests/                  # Test suite
├── scripts/                # Utility scripts
├── main.py                # Entry point
├── requirements.txt       # Python dependencies
└── README.md             # This file
```

## 🔄 Process Flow

### 1. Tool Discovery
- Reads tools from Google Sheets
- Filters tools with status "pending" or "failed"

### 2. Script Generation (Per Tool)
- Sends context to Claude:
  - Installation standards
  - Base Dockerfile
  - Tool specification
  - Acceptance checklist
- Claude generates installation script
- Validates Claude's self-review

### 3. Validation
- **Static Analysis:**
  - Shebang verification
  - Safety flags check (`set -euo pipefail`)
  - Bash syntax validation (`bash -n`)
  - Shellcheck analysis
  - Idempotency pattern detection
  - Secret scanning

### 4. Docker Testing
- Builds Docker image with script
- Runs installation
- Executes validation command
- Captures logs and exit codes

### 5. Artifact Storage
- Saves generated script
- Stores metadata and provenance
- Keeps installation logs
- Updates status in Google Sheets

## 📊 Output Structure

```
artifacts/
├── terraform/
│   └── 1.6.0/
│       ├── tool_setup.sh      # Generated script
│       ├── tool_setup.sh.sha256 # Checksum
│       ├── metadata.json      # Generation metadata
│       ├── provenance.json    # Full provenance
│       ├── result.json        # Installation result
│       ├── status.txt         # Quick status
│       └── installation_*.log # Execution logs
└── summary.json               # Overall run summary
```

## 🛡️ Security Features

- No secrets in scripts
- GPG verification for packages
- Checksum validation
- Non-root user execution
- Minimal base images
- Clean credential handling

## 🔍 Monitoring

### Logs
- Application logs: `logs/tool_installer.log`
- Per-tool logs: `artifacts/{tool}/{version}/installation_*.log`

### Status Tracking
- Real-time updates in Google Sheets
- Status files in artifact directories
- Summary JSON after each run

## 🧪 Testing

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=src --cov-report=html

# Run specific test
pytest tests/test_orchestrator.py
```

## 🐛 Troubleshooting

### Common Issues

1. **"Docker not found"**
   - Ensure Docker is installed and running
   - Check Docker permissions

2. **"shellcheck not found"**
   - Install shellcheck or validation will be skipped
   - Scripts will still be generated

3. **"Google Sheets API error"**
   - Verify credentials file path
   - Check service account permissions
   - Ensure Sheet is shared with service account

4. **"Claude API error"**
   - Check API key is set
   - Verify internet connection
   - Check rate limits

### Debug Mode

Run with debug logging:
```bash
python main.py --config config.json --log-level DEBUG
```

## 📈 Performance

- Concurrent processing (default: 5 jobs)
- Async I/O for API calls
- Docker layer caching
- Configurable timeouts
- Rate limit handling

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### Code Style
- Black for formatting
- isort for imports
- Type hints required
- Docstrings for all public functions

## 📝 License

[Your License Here]

## 🙏 Acknowledgments

- Claude AI by Anthropic
- Google Sheets API
- Docker
- The open source community
