"""
Configuration settings for the Tool Installation Automation system.
"""

from typing import Optional, Dict, Any
from pathlib import Path
from pydantic import BaseModel, Field, validator
from pydantic_settings import BaseSettings


class GoogleSheetsConfig(BaseModel):
    """Google Sheets configuration."""
    credentials_path: Path = Field(..., description="Path to Google service account credentials")
    spreadsheet_id: str = Field(..., description="Google Sheets spreadsheet ID")
    sheet_name: str = Field(default="Tools", description="Sheet name containing tool list")
    
    @validator('credentials_path')
    def validate_credentials_exist(cls, v):
        # Skip validation for mock mode
        if str(v).lower() == "mock":
            return v
        if not v.exists():
            raise ValueError(f"Google credentials file not found: {v}")
        return v


class ClaudeConfig(BaseModel):
    """Claude API configuration."""
    api_key: Optional[str] = Field(None, description="Anthropic API key (can use env var)")
    model: str = Field(default="claude-3-5-sonnet-20241022", description="Claude model to use")
    max_tokens: int = Field(default=4096, description="Maximum tokens for response")
    temperature: float = Field(default=0.2, description="Temperature for generation")
    max_concurrent_jobs: int = Field(default=5, description="Maximum concurrent Claude jobs")
    retry_attempts: int = Field(default=3, description="Number of retry attempts")
    retry_delay_seconds: float = Field(default=2.0, description="Initial retry delay")


class DockerConfig(BaseModel):
    """Docker configuration."""
    base_image: str = Field(default="ubuntu:22.04", description="Base Docker image")
    build_timeout: int = Field(default=300, description="Docker build timeout in seconds")
    run_timeout: int = Field(default=600, description="Docker run timeout in seconds")
    cleanup_containers: bool = Field(default=True, description="Clean up containers after run")
    registry: Optional[str] = Field(None, description="Docker registry URL if using private images")


class ArtifactConfig(BaseModel):
    """Artifact storage configuration."""
    base_path: Path = Field(default=Path("artifacts"), description="Base path for artifacts")
    keep_failed_attempts: bool = Field(default=True, description="Keep artifacts from failed attempts")
    
    def get_tool_path(self, tool_name: str, tool_version: str) -> Path:
        """Get artifact path for a specific tool."""
        return self.base_path / tool_name / tool_version


class LoggingConfig(BaseModel):
    """Logging configuration."""
    level: str = Field(default="INFO", description="Logging level")
    format: str = Field(
        default="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        description="Log format"
    )
    file_path: Optional[Path] = Field(default=Path("logs/tool_installer.log"))
    max_file_size_mb: int = Field(default=10, description="Maximum log file size in MB")
    backup_count: int = Field(default=5, description="Number of log backups to keep")


class Settings(BaseSettings):
    """Main application settings."""
    # Component configs
    google_sheets: GoogleSheetsConfig
    claude: ClaudeConfig = Field(default_factory=ClaudeConfig)
    docker: DockerConfig = Field(default_factory=DockerConfig)
    artifacts: ArtifactConfig = Field(default_factory=ArtifactConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)
    
    # Standards and templates
    install_standards_path: Path = Field(
        default=Path("config/install_standards.md"),
        description="Path to installation standards document"
    )
    base_dockerfile_path: Path = Field(
        default=Path("config/base.Dockerfile"),
        description="Path to base Dockerfile"
    )
    acceptance_checklist_path: Path = Field(
        default=Path("config/acceptance_checklist.yaml"),
        description="Path to acceptance checklist"
    )
    
    # Operational settings
    dry_run: bool = Field(default=False, description="Run in dry-run mode")
    parallel_jobs: int = Field(default=5, description="Number of parallel jobs")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        env_nested_delimiter = "__"
        extra = "ignore"  # Ignore extra fields from environment
        
    @validator('install_standards_path', 'base_dockerfile_path', 'acceptance_checklist_path')
    def validate_config_files_exist(cls, v):
        if not v.exists():
            # Create a placeholder if it doesn't exist
            v.parent.mkdir(parents=True, exist_ok=True)
            v.touch()
        return v
