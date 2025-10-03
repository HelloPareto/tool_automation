# Quick Start Guide

This guide will help you get the Tool Installation Automation system running quickly.

## 🚀 5-Minute Setup

### 1. Install Dependencies

```bash
# Create and activate virtual environment
python -m venv env
source env/bin/activate  # On Windows: env\Scripts\activate

# Install Python packages
pip install -r requirements.txt

# Install shellcheck (optional but recommended)
# Ubuntu/Debian:
sudo apt-get install shellcheck
# macOS:
brew install shellcheck
```

### 2. Set API Key

```bash
# Create .env file
echo "ANTHROPIC_API_KEY=your_api_key_here" > .env
```

### 3. Test with Mock Data

```bash
# Run test script
./scripts/test_installation.sh

# Or manually:
python main.py --mock-sheets --dry-run
```

## 🔧 Real Setup (with Google Sheets)

### 1. Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable Google Sheets API:
   ```
   APIs & Services → Enable APIs → Search "Google Sheets API" → Enable
   ```
4. Create Service Account:
   ```
   IAM & Admin → Service Accounts → Create Service Account
   ```
5. Download credentials JSON file

### 2. Prepare Google Sheet

Create a sheet with these columns:
| Name | Version | ValidateCommand | Description | Status |
|------|---------|----------------|-------------|---------|
| terraform | 1.6.0 | terraform version | Infrastructure as Code | pending |
| kubectl | 1.28.0 | kubectl version --client | Kubernetes CLI | pending |
| helm | 3.13.0 | helm version | Kubernetes package manager | pending |

Share the sheet with your service account email (found in credentials JSON).

### 3. Configure and Run

```bash
# Copy example config
cp config.example.json config.json

# Edit config.json with your values
# - Update credentials_path
# - Update spreadsheet_id (from Sheet URL)

# Run!
python main.py --config config.json
```

## 📊 Sample Google Sheet Format

```
| Column | Description | Example |
|--------|-------------|---------|
| Name | Tool name | terraform |
| Version | Version to install | 1.6.0 |
| ValidateCommand | Validation command | terraform version |
| Description | Optional description | Infrastructure tool |
| PackageManager | Package manager | apt, direct, pip |
| RepositoryURL | Repo URL if needed | https://... |
| GPGKeyURL | GPG key for verification | https://... |
| Status | Auto-updated | pending → completed |
| Message | Auto-updated | Installation successful |
| ArtifactPath | Auto-updated | artifacts/terraform/1.6.0/ |
```

## 🎯 Common Use Cases

### Install Specific Tools

Filter your sheet to only include tools you want to install, or set Status to "skip" for tools to ignore.

### Retry Failed Tools

The system automatically retries tools with status "failed". Just run again!

### Dry Run First

Always test with `--dry-run` to see what would happen:
```bash
python main.py --config config.json --dry-run
```

### Debug Issues

```bash
# Verbose logging
python main.py --config config.json --log-level DEBUG

# Check specific tool artifacts
ls -la artifacts/terraform/1.6.0/
cat artifacts/terraform/1.6.0/tool_setup.sh
```

## 🔍 What to Check

After running, check:

1. **Google Sheet** - Status column updated
2. **artifacts/** - Generated scripts and logs
3. **logs/** - Application logs
4. **Docker images** - `docker images` to see built images

## ⚡ Performance Tips

- Start with `--max-concurrent 2` and increase gradually
- Use `--dry-run` for testing script generation
- Clean up old Docker images periodically
- Monitor API rate limits

## 🆘 Need Help?

Check:
- Full README.md for detailed documentation
- logs/tool_installer.log for errors
- artifacts/{tool}/{version}/result.json for details
- Issue tracker for known problems
