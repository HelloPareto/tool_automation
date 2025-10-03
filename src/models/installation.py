"""
Installation and validation result models.
"""

from enum import Enum
from typing import Optional, Dict, Any, List
from datetime import datetime
from pydantic import BaseModel, Field


class ValidationStatus(str, Enum):
    """Status of validation steps."""
    PASSED = "passed"
    FAILED = "failed"
    SKIPPED = "skipped"


class ValidationResult(BaseModel):
    """Result of a validation step."""
    step: str = Field(..., description="Validation step name")
    status: ValidationStatus = Field(..., description="Validation status")
    output: Optional[str] = Field(None, description="Validation output")
    error: Optional[str] = Field(None, description="Error message if failed")
    duration_seconds: Optional[float] = Field(None, description="Validation duration")
    
    class Config:
        json_schema_extra = {
            "example": {
                "step": "shellcheck",
                "status": "passed",
                "output": "No issues found",
                "duration_seconds": 0.5
            }
        }


class InstallationResult(BaseModel):
    """Complete installation result for a tool."""
    tool_id: str = Field(..., description="Tool identifier")
    tool_name: str = Field(..., description="Tool name")
    tool_version: str = Field(..., description="Tool version")
    success: bool = Field(..., description="Overall success status")
    script_path: str = Field(..., description="Path to generated script")
    
    # Validation results
    static_validation: List[ValidationResult] = Field(default_factory=list)
    container_validation: Optional[ValidationResult] = None
    
    # Execution details
    docker_image_used: Optional[str] = Field(None, description="Base Docker image used")
    execution_logs: Optional[str] = Field(None, description="Installation execution logs")
    
    # Timing
    started_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = None
    duration_seconds: Optional[float] = None
    
    # Artifacts
    artifacts: Dict[str, str] = Field(
        default_factory=dict,
        description="Paths to generated artifacts"
    )
    
    # Provenance
    provenance: Dict[str, Any] = Field(
        default_factory=dict,
        description="Provenance information"
    )
    
    def complete(self, success: bool) -> None:
        """Mark installation as complete."""
        self.success = success
        self.completed_at = datetime.utcnow()
        if self.started_at:
            self.duration_seconds = (self.completed_at - self.started_at).total_seconds()
    
    class Config:
        json_schema_extra = {
            "example": {
                "tool_id": "terraform-1.6.0",
                "tool_name": "terraform",
                "tool_version": "1.6.0",
                "success": True,
                "script_path": "artifacts/terraform/1.6.0/tool_setup.sh",
                "static_validation": [
                    {"step": "shellcheck", "status": "passed"},
                    {"step": "bash_syntax", "status": "passed"}
                ],
                "docker_image_used": "ubuntu:22.04",
                "duration_seconds": 45.2
            }
        }
