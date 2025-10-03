#!/bin/bash
# Test script for Tool Installation Automation - Claude Built-in Tools

set -e

echo "======================================="
echo "Testing Tool Installation"
echo "Claude Using Built-in Tools"
echo "======================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to project root
cd "$(dirname "$0")/.."

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source env/bin/activate [[memory:8299098]]

# Check if ANTHROPIC_API_KEY is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}Loading API key from .env file...${NC}"
    if [ -f .env ]; then
        export $(cat .env | grep ANTHROPIC_API_KEY | xargs)
    fi
fi

# Clean up previous artifacts for a fresh test
echo -e "${YELLOW}Cleaning up previous artifacts...${NC}"
rm -rf artifacts/terraform artifacts/kubectl artifacts/helm
rm -rf /tmp/docker_test_*

# Run with mock sheets and dry-run to test without external dependencies
echo -e "${GREEN}Running with mock sheets and dry-run mode...${NC}"
python main.py --mock-sheets --dry-run --log-level INFO --max-concurrent 1

echo -e "${GREEN}✓ Test completed!${NC}"
echo ""
echo "Check the artifacts directory for generated scripts:"
ls -la artifacts/*/
echo ""
echo "To run with real Google Sheets:"
echo "  python main.py --config config.json"
echo ""
echo "To run in production mode (with Docker):"
echo "  python main.py --config config.json --dry-run false"
