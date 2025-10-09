"""
Google Sheets integration for reading tool lists and updating status.
"""

import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
import json

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
    GOOGLE_AVAILABLE = True
except ImportError:
    GOOGLE_AVAILABLE = False
    logging.warning("Google API libraries not available. Install with: pip install google-api-python-client google-auth")

from ..models.tool import Tool, ToolSpec, ToolStatus
from ..analyzers.github_analyzer import GitHubAnalyzer


class GoogleSheetsClient:
    """Client for interacting with Google Sheets."""
    
    def __init__(self, credentials_path: Path, spreadsheet_id: str, sheet_name: str = "Tools"):
        """
        Initialize Google Sheets client.
        
        Args:
            credentials_path: Path to service account credentials JSON
            spreadsheet_id: ID of the Google Sheets spreadsheet
            sheet_name: Name of the sheet containing tools
        """
        if not GOOGLE_AVAILABLE:
            raise ImportError("Google API libraries not installed")
            
        self.logger = logging.getLogger(__name__)
        self.spreadsheet_id = spreadsheet_id
        self.sheet_name = sheet_name
        
        # Initialize credentials and service
        self.credentials = service_account.Credentials.from_service_account_file(
            str(credentials_path),
            scopes=['https://www.googleapis.com/auth/spreadsheets']
        )
        self.service = build('sheets', 'v4', credentials=self.credentials)
        self.sheet = self.service.spreadsheets()
    
    def read_tools(self) -> List[Tool]:
        """
        Read tool list from Google Sheets.
        
        Expected columns:
        - github_url: GitHub repository URL (required)
        - status: Current status (updated by this system)
        
        OR legacy columns:
        - Name: Tool name
        - Version: Version to install
        - ValidateCommand: Command to validate installation
        - Description: Optional description
        - PackageManager: Package manager to use (apt, direct, etc.)
        - RepositoryURL: Repository URL if applicable
        - GPGKeyURL: GPG key URL for verification
        - Status: Current status (updated by this system)
        
        Returns:
            List of Tool objects
        """
        try:
            # Read header row and data
            range_name = f"{self.sheet_name}!A1:Z1000"
            result = self.sheet.values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()
            
            values = result.get('values', [])
            if not values or len(values) < 2:
                self.logger.warning("No data found in sheet")
                return []
            
            # Parse header row
            headers = [h.lower().replace(' ', '_') for h in values[0]]
            header_map = {h: i for i, h in enumerate(headers)}
            
            # Check if this is GitHub URL format or legacy format
            is_github_format = 'github_url' in header_map
            
            if is_github_format:
                # New GitHub URL format
                if 'github_url' not in header_map:
                    raise ValueError("Missing required column: github_url")
                
                # Initialize GitHub analyzer
                analyzer = GitHubAnalyzer()
                
                # Parse tools from GitHub URLs
                tools = []
                
                # First pass: Read all rows and identify which need analysis
                rows_to_process = []
                for row_idx, row in enumerate(values[1:], start=2):
                    if not row or len(row) == 0:
                        continue
                    
                    # Get GitHub URL (column A = index 0)
                    github_url = row[header_map['github_url']] if header_map['github_url'] < len(row) else None
                    if not github_url:
                        continue
                    
                    # Get status if available
                    status_str = row[header_map['status']] if 'status' in header_map and header_map['status'] < len(row) else 'pending'
                    
                    # Parse status
                    status = self._parse_status(status_str)
                    
                    # Only analyze repositories that are pending or failed (need processing)
                    if status in [ToolStatus.PENDING, ToolStatus.FAILED]:
                        rows_to_process.append((row_idx, github_url, status_str))
                        self.logger.debug(f"Queued for analysis: {github_url} (status: {status_str})")
                    else:
                        # For completed/in_progress tools, create minimal Tool object without GitHub analysis
                        repo_name = github_url.split('/')[-1].replace('.git', '')
                        tool = Tool(
                            id=f"{repo_name}-existing",
                            spec=ToolSpec(
                                name=repo_name,
                                version="unknown",
                                validate_cmd=f"{repo_name} --version",
                                description=f"Tool from {github_url}",
                                github_url=github_url
                            ),
                            row_number=row_idx,
                            status=status
                        )
                        tools.append(tool)
                        self.logger.debug(f"Skipped analysis for {github_url} (status: {status_str})")
                
                # Second pass: Fetch basic info only (Claude handles installation analysis)
                self.logger.info(f"Found {len(rows_to_process)} tools requiring processing (out of {len(values)-1} total)")
                
                for row_idx, github_url, status_str in rows_to_process:
                    try:
                        # Fetch basic repository info
                        self.logger.info(f"Fetching basic info for: {github_url}")
                        repo_info = analyzer.get_basic_info(github_url)
                        
                        # Create ToolSpec with minimal info - Claude will analyze installation
                        spec = ToolSpec(
                            name=repo_info.repo_name,
                            version=repo_info.latest_version or "latest",
                            validate_cmd=f"{repo_info.repo_name} --version",  # Claude will refine
                            description=repo_info.description or f"Tool from {github_url}",
                            github_url=github_url
                        )
                        
                        tool = Tool(
                            id=f"{spec.name}-{spec.version}",
                            spec=spec,
                            row_number=row_idx,
                            status=self._parse_status(status_str)
                        )
                        tools.append(tool)
                        
                    except Exception as e:
                        self.logger.error(f"Failed to fetch info for {github_url}: {e}")
                        # Create a basic tool entry - Claude will still try
                        repo_name = github_url.split('/')[-1].replace('.git', '')
                        tool = Tool(
                            id=f"{repo_name}-unknown",
                            spec=ToolSpec(
                                name=repo_name,
                                version="latest",
                                validate_cmd=f"{repo_name} --version",
                                description=f"Tool from {github_url}",
                                github_url=github_url
                            ),
                            row_number=row_idx,
                            status=ToolStatus.PENDING
                        )
                        tools.append(tool)
            else:
                # Legacy format
                required = ['name', 'version', 'validatecommand']
                missing = [r for r in required if r not in header_map]
                if missing:
                    raise ValueError(f"Missing required columns: {missing}")
                
                # Parse tools
                tools = []
                for row_idx, row in enumerate(values[1:], start=2):
                    if not row or not row[header_map['name']]:
                        continue
                    
                    # Extract tool data
                    tool_data = {}
                    for field, idx in header_map.items():
                        if idx < len(row):
                            tool_data[field] = row[idx]
                    
                    # Create ToolSpec
                    spec = ToolSpec(
                        name=tool_data['name'],
                        version=tool_data['version'],
                        validate_cmd=tool_data.get('validatecommand', ''),
                        description=tool_data.get('description'),
                        package_manager=tool_data.get('packagemanager'),
                        repository_url=tool_data.get('repositoryurl'),
                        gpg_key_url=tool_data.get('gpgkeyurl'),
                        dependencies=self._parse_list(tool_data.get('dependencies')),
                        post_install_steps=self._parse_list(tool_data.get('postinstallsteps'))
                    )
                    
                    # Create Tool
                    tool = Tool(
                        id=f"{spec.name}-{spec.version}",
                        spec=spec,
                        row_number=row_idx,
                        status=self._parse_status(tool_data.get('status', 'pending'))
                    )
                    
                    tools.append(tool)
            
            self.logger.info(f"Read {len(tools)} tools from Google Sheets")
            return tools
            
        except HttpError as e:
            self.logger.error(f"Google Sheets API error: {e}")
            raise
        except Exception as e:
            self.logger.error(f"Error reading tools: {e}")
            raise
    
    def update_tool_status(self, tool: Tool, status: ToolStatus, 
                          message: Optional[str] = None,
                          artifact_path: Optional[str] = None) -> None:
        """
        Update tool status in Google Sheets.
        
        Args:
            tool: Tool to update
            status: New status
            message: Optional status message
            artifact_path: Optional path to artifacts
        """
        if not tool.row_number:
            self.logger.warning(f"Tool {tool.id} has no row number, skipping update")
            return
        
        try:
            # Find status column
            range_name = f"{self.sheet_name}!A1:Z1"
            result = self.sheet.values().get(
                spreadsheetId=self.spreadsheet_id,
                range=range_name
            ).execute()
            
            headers = [h.lower().replace(' ', '_') for h in result.get('values', [[]])[0]]
            status_col = headers.index('status') if 'status' in headers else None
            message_col = headers.index('message') if 'message' in headers else None
            artifact_col = headers.index('artifactpath') if 'artifactpath' in headers else None
            
            # Prepare updates
            updates = []
            
            if status_col is not None:
                col_letter = chr(ord('A') + status_col)
                updates.append({
                    'range': f"{self.sheet_name}!{col_letter}{tool.row_number}",
                    'values': [[status.value]]
                })
            
            if message and message_col is not None:
                col_letter = chr(ord('A') + message_col)
                updates.append({
                    'range': f"{self.sheet_name}!{col_letter}{tool.row_number}",
                    'values': [[message]]
                })
            
            if artifact_path and artifact_col is not None:
                col_letter = chr(ord('A') + artifact_col)
                updates.append({
                    'range': f"{self.sheet_name}!{col_letter}{tool.row_number}",
                    'values': [[artifact_path]]
                })
            
            # Batch update
            if updates:
                body = {'data': updates, 'valueInputOption': 'RAW'}
                self.sheet.values().batchUpdate(
                    spreadsheetId=self.spreadsheet_id,
                    body=body
                ).execute()
                
                self.logger.info(f"Updated status for {tool.id} to {status.value}")
                
        except Exception as e:
            self.logger.error(f"Error updating tool status: {e}")
            # Don't raise - status update failure shouldn't stop processing
    
    def _parse_status(self, status_str: str) -> ToolStatus:
        """Parse status string to enum."""
        status_map = {s.value: s for s in ToolStatus}
        return status_map.get(status_str.lower(), ToolStatus.PENDING)
    
    def _parse_list(self, value: Optional[str]) -> List[str]:
        """Parse comma-separated list."""
        if not value:
            return []
        return [item.strip() for item in value.split(',') if item.strip()]


class MockGoogleSheetsClient:
    """Mock client for testing without Google Sheets access."""
    
    def __init__(self, *args, **kwargs):
        self.logger = logging.getLogger(__name__)
        self.logger.info("Using mock Google Sheets client")
    
    def read_tools(self) -> List[Tool]:
        """Return sample tools for testing with pending status only."""
        # Sample GitHub URLs from the user's spreadsheet
        # Format: (github_url, status)
        github_tools = [
            ("https://github.com/airbytehq/airbyte", "pending"),
            ("https://github.com/pandas-dev/pandas", "pending"),
            ("https://github.com/sktime/sktime", "pending"),
            # Examples of tools that would be skipped (already completed)
            # ("https://github.com/apache/airflow", "completed"),
            # ("https://github.com/dbt-labs/dbt-core", "completed"),
        ]
        
        analyzer = GitHubAnalyzer()
        tools = []
        
        # Filter to only analyze pending tools (simulating the optimization)
        pending_tools = [(idx+2, url, status) for idx, (url, status) in enumerate(github_tools) if status == "pending"]
        
        self.logger.info(f"Found {len(pending_tools)} pending tools to analyze (out of {len(github_tools)} total)")
        
        for idx, github_url, status in pending_tools:
            try:
                # Analyze the repository
                analysis = analyzer.analyze_repository(github_url)
                
                # Create tool spec based on analysis
                spec = ToolSpec(
                    name=analysis.repo_name,
                    version=analysis.latest_version or "latest",
                    validate_cmd=analysis.validation_command or f"{analysis.repo_name} --version",
                    description=analysis.description or f"Tool from {github_url}",
                    github_url=github_url,
                    detected_install_methods=[method.value for method in analysis.install_methods],
                    package_name=analysis.package_name,
                    docker_image=analysis.docker_image,
                    binary_pattern=analysis.binary_pattern,
                    installation_docs=analysis.installation_docs
                )
                
                # Determine primary package manager
                if analysis.install_methods:
                    primary_method = analysis.install_methods[0]
                    spec.package_manager = primary_method.value
                else:
                    spec.package_manager = "unknown"
                
                tool = Tool(
                    id=f"{analysis.repo_name}-{spec.version}",
                    spec=spec,
                    row_number=idx,
                    status=ToolStatus.PENDING
                )
                
                tools.append(tool)
                
            except Exception as e:
                self.logger.warning(f"Failed to analyze {github_url}: {e}")
                # Create a basic tool entry
                repo_name = github_url.split('/')[-1]
                tool = Tool(
                    id=f"{repo_name}-unknown",
                    spec=ToolSpec(
                        name=repo_name,
                        version="latest",
                        validate_cmd=f"{repo_name} --version",
                        description=f"Tool from {github_url}",
                        github_url=github_url
                    ),
                    row_number=idx,
                    status=ToolStatus.PENDING
                )
                tools.append(tool)
        
        return tools
    
    def update_tool_status(self, tool: Tool, status: ToolStatus, 
                          message: Optional[str] = None,
                          artifact_path: Optional[str] = None) -> None:
        """Log status update."""
        self.logger.info(f"[MOCK] Updated {tool.id} status to {status.value}")
        if message:
            self.logger.info(f"[MOCK] Message: {message}")
        if artifact_path:
            self.logger.info(f"[MOCK] Artifacts: {artifact_path}")
