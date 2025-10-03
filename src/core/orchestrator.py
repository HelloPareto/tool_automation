"""
Orchestrator v3 - Uses Claude's built-in tools for autonomous installation.
"""

import asyncio
import logging
from typing import List, Dict, Any
from datetime import datetime
from pathlib import Path

from ..models.tool import Tool, ToolStatus
from ..integrations.google_sheets import GoogleSheetsClient
from ..integrations.claude_agent import ClaudeInstallationAgent
from ..core.artifact_manager import ArtifactManager
from ..utils.logging import setup_logger


class ToolInstallationOrchestrator:
    """Orchestrates tool installation using Claude's built-in tools."""
    
    def __init__(self, 
                 sheets_client: GoogleSheetsClient,
                 artifact_manager: ArtifactManager,
                 max_concurrent_jobs: int = 5,
                 dry_run: bool = False):
        """
        Initialize the orchestrator.
        
        Args:
            sheets_client: Google Sheets client
            artifact_manager: Artifact storage manager
            max_concurrent_jobs: Maximum concurrent Claude agents
            dry_run: If True, skip Docker execution
        """
        self.logger = setup_logger(__name__)
        self.sheets_client = sheets_client
        self.artifact_manager = artifact_manager
        self.max_concurrent_jobs = max_concurrent_jobs
        self.dry_run = dry_run
        
        # Load standards and configs
        self.install_standards = self._load_file("config/install_standards.md")
        self.base_dockerfile = self._load_file("config/base.Dockerfile") 
        self.acceptance_checklist = self._load_file("config/acceptance_checklist.yaml")
        
        # Semaphore for rate limiting
        self.semaphore = asyncio.Semaphore(max_concurrent_jobs)
        
        # Create Claude agent
        self.claude_agent = ClaudeInstallationAgent(
            artifacts_base_path=artifact_manager.base_path
        )
    
    async def run(self) -> Dict[str, Any]:
        """
        Main orchestration method.
        
        Returns:
            Summary of results
        """
        self.logger.info("Starting Tool Installation Orchestrator (Claude Built-in Tools)")
        start_time = datetime.utcnow()
        
        # Read tools from Google Sheets
        tools = self.sheets_client.read_tools()
        self.logger.info(f"Found {len(tools)} tools to process")
        
        # Filter tools that need processing
        pending_tools = [t for t in tools if t.status in [ToolStatus.PENDING, ToolStatus.FAILED]]
        self.logger.info(f"{len(pending_tools)} tools need processing")
        
        if not pending_tools:
            self.logger.info("No tools to process")
            return {
                "total_tools": len(tools),
                "processed": 0,
                "successful": 0,
                "failed": 0,
                "duration_seconds": 0
            }
        
        # Process tools concurrently with Claude agents
        tasks = [self._process_tool_with_claude(tool) for tool in pending_tools]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Aggregate results
        successful = sum(1 for r in results if isinstance(r, dict) and r.get("success"))
        failed = sum(1 for r in results if isinstance(r, Exception) or 
                    (isinstance(r, dict) and not r.get("success")))
        
        duration = (datetime.utcnow() - start_time).total_seconds()
        
        summary = {
            "total_tools": len(tools),
            "processed": len(pending_tools),
            "successful": successful,
            "failed": failed,
            "duration_seconds": duration,
            "orchestrator_version": "builtin_tools"
        }
        
        self.logger.info(f"Orchestration complete: {summary}")
        
        # Save summary
        summary_path = self.artifact_manager.save_json(
            "summary.json", summary, 
            subdirs=["runs", datetime.utcnow().strftime("%Y%m%d_%H%M%S")]
        )
        self.logger.info(f"Summary saved to {summary_path}")
        
        return summary
    
    async def _process_tool_with_claude(self, tool: Tool) -> Dict[str, Any]:
        """Process a single tool using Claude with built-in tools."""
        async with self.semaphore:
            try:
                self.logger.info(f"Launching Claude agent for {tool.id}")
                
                # Update status to in_progress
                tool.update_status(ToolStatus.IN_PROGRESS)
                self.sheets_client.update_tool_status(
                    tool, ToolStatus.IN_PROGRESS,
                    message="Claude agent working with built-in tools..."
                )
                
                # Launch Claude agent with built-in tools
                self.logger.info(f"Claude using built-in tools for {tool.id}")
                
                result = await self.claude_agent.install_tool(
                    tool_spec=tool.spec,
                    install_standards=self.install_standards,
                    base_dockerfile=self.base_dockerfile,
                    acceptance_checklist=self.acceptance_checklist,
                    dry_run=self.dry_run
                )
                
                # Process Claude's result
                if result["success"]:
                    tool.update_status(ToolStatus.COMPLETED)
                    self.sheets_client.update_tool_status(
                        tool, ToolStatus.COMPLETED,
                        message=f"Installation successful (Claude built-in tools)",
                        artifact_path=result.get("script_path", f"artifacts/tools/{tool.spec.name}/tool_setup.sh")
                    )
                    self.logger.info(f"Claude successfully installed {tool.id}")
                else:
                    error_msg = "; ".join(result.get("errors", ["Unknown error"]))[:200]
                    tool.update_status(ToolStatus.FAILED, error_msg)
                    self.sheets_client.update_tool_status(
                        tool, ToolStatus.FAILED,
                        message=f"Installation failed: {error_msg}"
                    )
                    self.logger.error(f"Claude failed to install {tool.id}: {error_msg}")
                
                # Save Claude's complete result
                result_path = self.artifact_manager.save_json(
                    "claude_result.json", result,
                    subdirs=["tools", tool.spec.name]
                )
                
                # Save a summary of tool calls
                if result.get("tool_calls_made", 0) > 0:
                    self.logger.info(f"Claude made {result['tool_calls_made']} tool calls for {tool.id}")
                
                return result
                
            except Exception as e:
                self.logger.error(f"Error with Claude agent for {tool.id}: {e}", exc_info=True)
                
                # Update status
                tool.update_status(ToolStatus.FAILED, str(e))
                self.sheets_client.update_tool_status(
                    tool, ToolStatus.FAILED, f"Claude agent error: {str(e)}"
                )
                
                return {
                    "success": False,
                    "tool_name": tool.spec.name,
                    "tool_version": tool.spec.version,
                    "errors": [str(e)]
                }
    
    def _load_file(self, path: str) -> str:
        """Load a file's contents."""
        file_path = Path(path)
        if not file_path.exists():
            self.logger.warning(f"File not found: {path}, using empty content")
            return ""
        return file_path.read_text()
