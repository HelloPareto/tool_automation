#!/usr/bin/env python3
"""
Main entry point for Tool Installation Automation - Using Claude's Built-in Tools
"""

import asyncio
import argparse
import sys
from pathlib import Path
from typing import Optional
import json
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

from src.core.orchestrator import ToolInstallationOrchestrator
from src.core.artifact_manager import ArtifactManager
from src.integrations.google_sheets import GoogleSheetsClient, MockGoogleSheetsClient
from src.utils.logging import setup_root_logger
from config.settings import Settings


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Automated Tool Installation using Claude's Built-in Tools"
    )
    
    parser.add_argument(
        "--config",
        type=Path,
        help="Path to configuration file (JSON format)"
    )
    
    parser.add_argument(
        "--google-creds",
        type=Path,
        help="Path to Google service account credentials"
    )
    
    parser.add_argument(
        "--spreadsheet-id",
        type=str,
        help="Google Sheets spreadsheet ID"
    )
    
    parser.add_argument(
        "--sheet-name",
        type=str,
        default="Tools",
        help="Sheet name containing tool list (default: Tools)"
    )
    
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run in dry-run mode (skip Docker execution)"
    )
    
    parser.add_argument(
        "--max-concurrent",
        type=int,
        default=5,
        help="Maximum concurrent Claude agents (default: 5)"
    )
    
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )
    
    parser.add_argument(
        "--mock-sheets",
        action="store_true",
        help="Use mock Google Sheets client for testing"
    )
    
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        default=Path("artifacts"),
        help="Directory for storing artifacts (default: artifacts)"
    )
    
    return parser.parse_args()


def load_config(args) -> Settings:
    """Load configuration from file or command line."""
    if args.config and args.config.exists():
        # Load from config file
        with open(args.config) as f:
            config_data = json.load(f)
        
        # Override with command line args
        if args.google_creds:
            config_data.setdefault("google_sheets", {})["credentials_path"] = str(args.google_creds)
        if args.spreadsheet_id:
            config_data.setdefault("google_sheets", {})["spreadsheet_id"] = args.spreadsheet_id
        if args.sheet_name:
            config_data.setdefault("google_sheets", {})["sheet_name"] = args.sheet_name
        if args.dry_run:
            config_data["dry_run"] = args.dry_run
        if args.max_concurrent:
            config_data.setdefault("claude", {})["max_concurrent_jobs"] = args.max_concurrent
        if args.artifacts_dir:
            config_data.setdefault("artifacts", {})["base_path"] = str(args.artifacts_dir)
            
        # Handle mock mode
        if args.mock_sheets:
            config_data["google_sheets"]["credentials_path"] = "mock"
            config_data["google_sheets"]["spreadsheet_id"] = "mock"
        
        return Settings(**config_data)
    else:
        # Build config from command line args
        if not args.mock_sheets and (not args.google_creds or not args.spreadsheet_id):
            raise ValueError(
                "Either provide --config file or both --google-creds and --spreadsheet-id"
            )
        
        config_data = {
            "google_sheets": {
                "credentials_path": str(args.google_creds) if args.google_creds else "mock",
                "spreadsheet_id": args.spreadsheet_id or "mock",
                "sheet_name": args.sheet_name
            },
            "claude": {
                "max_concurrent_jobs": args.max_concurrent
            },
            "artifacts": {
                "base_path": str(args.artifacts_dir)
            },
            "dry_run": args.dry_run,
            "parallel_jobs": args.max_concurrent
        }
        
        return Settings(**config_data)


async def main():
    """Main entry point."""
    args = parse_arguments()
    
    # Setup logging
    log_file = Path("logs") / "tool_installer.log"
    setup_root_logger(log_file, args.log_level)
    
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info("Starting Tool Installation Automation - Claude Built-in Tools")
    logger.info(f"Arguments: {vars(args)}")
    
    try:
        # Load configuration
        settings = load_config(args)
        
        # Initialize components
        if args.mock_sheets:
            logger.info("Using mock Google Sheets client")
            sheets_client = MockGoogleSheetsClient()
        else:
            sheets_client = GoogleSheetsClient(
                credentials_path=settings.google_sheets.credentials_path,
                spreadsheet_id=settings.google_sheets.spreadsheet_id,
                sheet_name=settings.google_sheets.sheet_name
            )
        
        # Check for API key
        api_key = os.environ.get("ANTHROPIC_API_KEY") or settings.claude.api_key
        if not api_key:
            logger.error("ANTHROPIC_API_KEY not found in environment or config")
            sys.exit(1)
        
        artifact_manager = ArtifactManager(
            base_path=settings.artifacts.base_path,
            keep_failed_attempts=settings.artifacts.keep_failed_attempts
        )
        
        # Create orchestrator
        orchestrator = ToolInstallationOrchestrator(
            sheets_client=sheets_client,
            artifact_manager=artifact_manager,
            max_concurrent_jobs=settings.claude.max_concurrent_jobs,
            dry_run=settings.dry_run
        )
        
        # Run orchestration
        logger.info("Starting orchestration with Claude using built-in tools...")
        results = await orchestrator.run()
        
        # Print summary
        logger.info("=" * 60)
        logger.info("SUMMARY")
        logger.info("=" * 60)
        logger.info(f"Total tools: {results['total_tools']}")
        logger.info(f"Processed: {results['processed']}")
        logger.info(f"Successful: {results['successful']}")
        logger.info(f"Failed: {results['failed']}")
        logger.info(f"Duration: {results['duration_seconds']:.2f} seconds")
        logger.info(f"Version: {results['orchestrator_version']}")
        logger.info("=" * 60)
        
        # Exit with appropriate code
        if results['failed'] > 0:
            sys.exit(1)
        else:
            sys.exit(0)
            
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
