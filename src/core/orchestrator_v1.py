"""
Main orchestrator for tool installation automation.
"""

import asyncio
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime
from pathlib import Path
import json

from ..models.tool import Tool, ToolStatus
from ..models.installation import InstallationResult
from ..integrations.google_sheets import GoogleSheetsClient
from ..integrations.claude_client import ClaudeClient
from .script_validator import ScriptValidator
from .docker_runner import DockerRunner
from .artifact_manager import ArtifactManager
from ..utils.logging import setup_logger


class ToolInstallationOrchestrator:
    """Orchestrates the tool installation process."""
    
    def __init__(self, 
                 sheets_client: GoogleSheetsClient,
                 claude_client: ClaudeClient,
                 artifact_manager: ArtifactManager,
                 docker_config: Dict[str, Any],
                 max_concurrent_jobs: int = 5,
                 dry_run: bool = False):
        """
        Initialize the orchestrator.
        
        Args:
            sheets_client: Google Sheets client
            claude_client: Claude API client
            artifact_manager: Artifact storage manager
            docker_config: Docker configuration
            max_concurrent_jobs: Maximum concurrent installations
            dry_run: If True, skip actual Docker execution
        """
        self.logger = setup_logger(__name__)
        self.sheets_client = sheets_client
        self.claude_client = claude_client
        self.artifact_manager = artifact_manager
        self.validator = ScriptValidator()
        self.docker_runner = DockerRunner(docker_config)
        self.max_concurrent_jobs = max_concurrent_jobs
        self.dry_run = dry_run
        
        # Load standards and configs
        self.install_standards = self._load_file("config/install_standards.md")
        self.base_dockerfile = self._load_file("config/base.Dockerfile") 
        self.acceptance_checklist = self._load_file("config/acceptance_checklist.yaml")
        
        # Semaphore for rate limiting
        self.semaphore = asyncio.Semaphore(max_concurrent_jobs)
    
    async def run(self) -> Dict[str, Any]:
        """
        Main orchestration method.
        
        Returns:
            Summary of results
        """
        self.logger.info("Starting Tool Installation Orchestrator")
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
        
        # Process tools concurrently
        tasks = [self._process_tool(tool) for tool in pending_tools]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Aggregate results
        successful = sum(1 for r in results if isinstance(r, InstallationResult) and r.success)
        failed = sum(1 for r in results if isinstance(r, Exception) or 
                    (isinstance(r, InstallationResult) and not r.success))
        
        duration = (datetime.utcnow() - start_time).total_seconds()
        
        summary = {
            "total_tools": len(tools),
            "processed": len(pending_tools),
            "successful": successful,
            "failed": failed,
            "duration_seconds": duration
        }
        
        self.logger.info(f"Orchestration complete: {summary}")
        
        # Save summary
        summary_path = self.artifact_manager.save_json(
            "summary.json", summary, subdirs=["runs", datetime.utcnow().strftime("%Y%m%d_%H%M%S")]
        )
        self.logger.info(f"Summary saved to {summary_path}")
        
        return summary
    
    async def _process_tool(self, tool: Tool) -> InstallationResult:
        """Process a single tool asynchronously."""
        async with self.semaphore:
            try:
                self.logger.info(f"Processing {tool.id}")
                
                # Update status to in_progress
                tool.update_status(ToolStatus.IN_PROGRESS)
                self.sheets_client.update_tool_status(tool, ToolStatus.IN_PROGRESS)
                
                # Create installation result
                result = InstallationResult(
                    tool_id=tool.id,
                    tool_name=tool.spec.name,
                    tool_version=tool.spec.version,
                    script_path="",
                    success=False  # Will be updated later
                )
                
                # Generate script with Claude
                self.logger.info(f"Generating script for {tool.id}")
                tool.update_status(ToolStatus.GENERATING)
                self.sheets_client.update_tool_status(tool, ToolStatus.GENERATING)
                
                claude_response = await self.claude_client.generate_installation_script(
                    tool_spec=tool.spec,
                    install_standards=self.install_standards,
                    base_dockerfile=self.base_dockerfile,
                    acceptance_checklist=self.acceptance_checklist
                )
                
                # Check Claude's self-review
                if claude_response.self_review.blockers:
                    error_msg = f"Claude reported blockers: {claude_response.self_review.blockers}"
                    self.logger.error(error_msg)
                    result.complete(success=False)
                    tool.update_status(ToolStatus.FAILED, error_msg)
                    self.sheets_client.update_tool_status(
                        tool, ToolStatus.FAILED, error_msg
                    )
                    return result
                
                # Save the generated script
                script_path = self.artifact_manager.save_script(
                    tool.spec.name, 
                    tool.spec.version,
                    claude_response.script_bash
                )
                result.script_path = str(script_path)
                
                # Save metadata
                metadata = {
                    "tool": tool.model_dump(),
                    "claude_response": {
                        "plan": claude_response.plan,
                        "metadata": claude_response.metadata,
                        "self_review": {
                            "checklist": [item.model_dump() for item in claude_response.self_review.checklist],
                            "blockers": claude_response.self_review.blockers,
                            "warnings": claude_response.self_review.warnings,
                            "confidence": claude_response.self_review.overall_confidence
                        }
                    },
                    "generated_at": datetime.utcnow().isoformat()
                }
                
                metadata_path = self.artifact_manager.save_json(
                    "metadata.json", metadata,
                    subdirs=[tool.spec.name, tool.spec.version]
                )
                
                # Validate script
                self.logger.info(f"Validating script for {tool.id}")
                tool.update_status(ToolStatus.VALIDATING)
                self.sheets_client.update_tool_status(tool, ToolStatus.VALIDATING)
                
                validation_results = self.validator.validate_script(script_path)
                result.static_validation = validation_results
                
                # Check if static validation passed
                if any(v.status == "failed" for v in validation_results):
                    error_msg = "Static validation failed"
                    self.logger.error(f"{error_msg} for {tool.id}")
                    result.complete(success=False)
                    tool.update_status(ToolStatus.FAILED, error_msg)
                    self.sheets_client.update_tool_status(
                        tool, ToolStatus.FAILED, error_msg
                    )
                    
                    # Save result even if failed
                    self._save_result(tool, result)
                    return result
                
                # Run in Docker container (unless dry run)
                if not self.dry_run:
                    self.logger.info(f"Installing {tool.id} in Docker")
                    tool.update_status(ToolStatus.INSTALLING)
                    self.sheets_client.update_tool_status(tool, ToolStatus.INSTALLING)
                    
                    docker_result = await self.docker_runner.run_installation(
                        script_path=script_path,
                        tool_spec=tool.spec,
                        base_image=self.docker_runner.config.get('base_image', 'ubuntu:22.04')
                    )
                    
                    result.container_validation = docker_result
                    result.docker_image_used = self.docker_runner.config.get('base_image')
                    result.execution_logs = docker_result.output
                    
                    if docker_result.status == "failed":
                        error_msg = f"Docker installation failed: {docker_result.error}"
                        self.logger.error(f"{error_msg} for {tool.id}")
                        result.complete(success=False)
                        tool.update_status(ToolStatus.FAILED, error_msg)
                        self.sheets_client.update_tool_status(
                            tool, ToolStatus.FAILED, error_msg
                        )
                        self._save_result(tool, result)
                        return result
                
                # Success!
                result.complete(success=True)
                tool.update_status(ToolStatus.COMPLETED)
                
                # Save provenance
                provenance = self._create_provenance(tool, claude_response, result)
                provenance_path = self.artifact_manager.save_json(
                    "provenance.json", provenance,
                    subdirs=[tool.spec.name, tool.spec.version]
                )
                result.provenance = provenance
                
                # Update sheet with success
                artifact_path = f"artifacts/{tool.spec.name}/{tool.spec.version}/"
                self.sheets_client.update_tool_status(
                    tool, ToolStatus.COMPLETED,
                    message="Installation successful",
                    artifact_path=artifact_path
                )
                
                # Save final result
                self._save_result(tool, result)
                
                self.logger.info(f"Successfully processed {tool.id}")
                return result
                
            except Exception as e:
                self.logger.error(f"Error processing {tool.id}: {e}", exc_info=True)
                
                # Update status
                tool.update_status(ToolStatus.FAILED, str(e))
                self.sheets_client.update_tool_status(
                    tool, ToolStatus.FAILED, f"Error: {str(e)}"
                )
                
                # Return failed result
                if 'result' in locals():
                    result.complete(success=False)
                    return result
                else:
                    raise
    
    def _load_file(self, path: str) -> str:
        """Load a file's contents."""
        file_path = Path(path)
        if not file_path.exists():
            self.logger.warning(f"File not found: {path}, using empty content")
            return ""
        return file_path.read_text()
    
    def _create_provenance(self, tool: Tool, claude_response: Any, 
                          result: InstallationResult) -> Dict[str, Any]:
        """Create provenance information."""
        return {
            "tool": {
                "name": tool.spec.name,
                "version": tool.spec.version,
                "id": tool.id
            },
            "generation": {
                "model": "claude-sonnet-4-5-20250929",
                "timestamp": datetime.utcnow().isoformat(),
                "confidence": claude_response.self_review.overall_confidence
            },
            "validation": {
                "static": [v.model_dump() for v in result.static_validation],
                "container": result.container_validation.model_dump() if result.container_validation else None
            },
            "environment": {
                "base_image": result.docker_image_used,
                "standards_version": "1.0.0"
            },
            "artifacts": result.artifacts
        }
    
    def _save_result(self, tool: Tool, result: InstallationResult) -> None:
        """Save installation result."""
        try:
            result_path = self.artifact_manager.save_json(
                "result.json", result.model_dump(),
                subdirs=[tool.spec.name, tool.spec.version]
            )
            self.logger.info(f"Saved result to {result_path}")
        except Exception as e:
            self.logger.error(f"Failed to save result: {e}")
