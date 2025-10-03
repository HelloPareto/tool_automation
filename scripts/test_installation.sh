#!/bin/bash
# Test script for running the tool installer in mock mode

set -euo pipefail

echo "==================================="
echo "Tool Installation Test Script"
echo "==================================="

# Activate virtual environment if it exists
if [ -d "env" ]; then
    echo "Activating virtual environment..."
    source env/bin/activate
fi

# Check if API key is set
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Warning: ANTHROPIC_API_KEY not set"
    echo "The system will fail when trying to generate scripts"
fi

# Run in mock mode with dry-run
echo ""
echo "Running tool installer in mock mode..."
echo ""

python main.py \
    --mock-sheets \
    --dry-run \
    --max-concurrent 2 \
    --log-level INFO

echo ""
echo "Test completed!"
echo "Check the artifacts/ directory for generated files"
