"""
Tool-related data models.
"""

from enum import Enum
from typing import Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field, HttpUrl


class ToolStatus(str, Enum):
    """Status of a tool installation job."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    GENERATING = "generating"
    VALIDATING = "validating"
    INSTALLING = "installing"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class ToolSpec(BaseModel):
    """Specification for a tool to be installed."""
    name: str = Field(..., description="Tool name")
    version: str = Field(..., description="Tool version to install")
    validate_cmd: str = Field(..., description="Command to validate installation")
    description: Optional[str] = Field(None, description="Tool description")
    package_manager: Optional[str] = Field(None, description="Package manager to use")
    repository_url: Optional[HttpUrl] = Field(None, description="Repository URL if applicable")
    gpg_key_url: Optional[HttpUrl] = Field(None, description="GPG key URL for verification")
    dependencies: Optional[list[str]] = Field(default_factory=list, description="Tool dependencies")
    post_install_steps: Optional[list[str]] = Field(default_factory=list, description="Post-installation steps")
    
    class Config:
        json_schema_extra = {
            "example": {
                "name": "terraform",
                "version": "1.6.0",
                "validate_cmd": "terraform version",
                "description": "Infrastructure as Code tool",
                "package_manager": "direct",
                "repository_url": "https://releases.hashicorp.com/terraform/"
            }
        }


class Tool(BaseModel):
    """Complete tool model with metadata."""
    id: str = Field(..., description="Unique tool identifier")
    spec: ToolSpec = Field(..., description="Tool specification")
    status: ToolStatus = Field(default=ToolStatus.PENDING, description="Current status")
    row_number: Optional[int] = Field(None, description="Google Sheet row number")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    error_message: Optional[str] = Field(None, description="Error message if failed")
    artifact_path: Optional[str] = Field(None, description="Path to generated artifacts")
    
    def update_status(self, status: ToolStatus, error: Optional[str] = None) -> None:
        """Update tool status and timestamp."""
        self.status = status
        self.updated_at = datetime.utcnow()
        if error:
            self.error_message = error
