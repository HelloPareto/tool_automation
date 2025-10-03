"""
Claude-related models for script generation.
"""

from typing import Optional, Dict, Any, List
from datetime import datetime
from pydantic import BaseModel, Field, validator
import json


class SelfReviewItem(BaseModel):
    """Individual self-review checklist item."""
    criterion: str = Field(..., description="Review criterion")
    passed: bool = Field(..., description="Whether criterion passed")
    explanation: str = Field(..., description="Explanation of result")


class SelfReview(BaseModel):
    """Claude's self-review of generated script."""
    checklist: List[SelfReviewItem] = Field(default_factory=list)
    blockers: Optional[List[str]] = Field(None, description="Blocking issues found")
    warnings: Optional[List[str]] = Field(None, description="Non-blocking warnings")
    overall_confidence: float = Field(..., ge=0.0, le=1.0, description="Confidence score 0-1")


class ScriptMetadata(BaseModel):
    """Metadata about the generated script."""
    tool_name: str
    tool_version: str
    generated_at: datetime = Field(default_factory=datetime.utcnow)
    model_used: str = Field(default="claude-3-5-sonnet-20241022")
    prompt_hash: str
    base_image_digest: Optional[str] = None
    standards_version: str = Field(default="1.0.0")


class ClaudeResponse(BaseModel):
    """Structured response from Claude for script generation."""
    plan: List[str] = Field(..., description="Step-by-step installation plan")
    script_bash: str = Field(..., description="Generated bash script content")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")
    self_review: SelfReview = Field(..., description="Self-review results")
    
    @validator('script_bash')
    def validate_script_format(cls, v):
        """Ensure script has proper shebang and safety flags."""
        if not v.strip().startswith("#!/usr/bin/env bash"):
            raise ValueError("Script must start with #!/usr/bin/env bash")
        if "set -euo pipefail" not in v:
            raise ValueError("Script must include 'set -euo pipefail'")
        return v
    
    @validator('plan')
    def validate_plan_not_empty(cls, v):
        """Ensure plan has at least one step."""
        if not v:
            raise ValueError("Plan must contain at least one step")
        return v
    
    def to_json_envelope(self) -> str:
        """Convert to JSON envelope format."""
        return json.dumps(self.model_dump(), indent=2, default=str)
    
    class Config:
        json_schema_extra = {
            "example": {
                "plan": [
                    "Add HashiCorp GPG key to keyring",
                    "Add HashiCorp APT repository", 
                    "Update package list",
                    "Install terraform at version 1.6.0",
                    "Verify installation"
                ],
                "script_bash": "#!/usr/bin/env bash\nset -euo pipefail\n\n# Script content...",
                "metadata": {
                    "package_source": "hashicorp_official",
                    "install_method": "apt"
                },
                "self_review": {
                    "checklist": [
                        {
                            "criterion": "Idempotent",
                            "passed": True,
                            "explanation": "Script checks if terraform is already installed"
                        }
                    ],
                    "blockers": None,
                    "warnings": None,
                    "overall_confidence": 0.95
                }
            }
        }
