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
            
            # Required columns
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
        """Return sample tools for testing."""
        sample_tools = [
            Tool(
                id="terraform-1.6.0",
                spec=ToolSpec(
                    name="terraform",
                    version="1.6.0",
                    validate_cmd="terraform version",
                    description="Infrastructure as Code tool",
                    package_manager="direct"
                ),
                row_number=2
            ),
            Tool(
                id="kubectl-1.28.0",
                spec=ToolSpec(
                    name="kubectl",
                    version="1.28.0", 
                    validate_cmd="kubectl version --client",
                    description="Kubernetes command-line tool",
                    package_manager="direct"
                ),
                row_number=3
            ),
            Tool(
                id="helm-3.13.0",
                spec=ToolSpec(
                    name="helm",
                    version="3.13.0",
                    validate_cmd="helm version",
                    description="Kubernetes package manager",
                    package_manager="direct"
                ),
                row_number=4
            )
        ]
        return sample_tools
    
    def update_tool_status(self, tool: Tool, status: ToolStatus, 
                          message: Optional[str] = None,
                          artifact_path: Optional[str] = None) -> None:
        """Log status update."""
        self.logger.info(f"[MOCK] Updated {tool.id} status to {status.value}")
        if message:
            self.logger.info(f"[MOCK] Message: {message}")
        if artifact_path:
            self.logger.info(f"[MOCK] Artifacts: {artifact_path}")
