"""
Artifact management for storing generated scripts and metadata.
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional, List
import shutil
import hashlib


class ArtifactManager:
    """Manages storage of generated artifacts."""
    
    def __init__(self, base_path: Path, keep_failed_attempts: bool = True, run_id: Optional[str] = None):
        """
        Initialize artifact manager.
        
        Args:
            base_path: Base directory for storing artifacts
            keep_failed_attempts: Whether to keep artifacts from failed attempts
            run_id: Optional run ID for organizing artifacts by run
        """
        self.logger = logging.getLogger(__name__)
        self.base_path = Path(base_path)
        self.keep_failed_attempts = keep_failed_attempts
        self.run_id = run_id
        
        # If run_id is provided, use runs directory structure
        if self.run_id:
            self.run_base_path = self.base_path / "runs" / self.run_id
        else:
            self.run_base_path = self.base_path
        
        # Create base directory
        self.run_base_path.mkdir(parents=True, exist_ok=True)
        
        # Create standard subdirectories
        self.scripts_dir = self.run_base_path / "scripts"
        self.logs_dir = self.run_base_path / "logs"
        self.metadata_dir = self.run_base_path / "metadata"
        
        for dir_path in [self.scripts_dir, self.logs_dir, self.metadata_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)
    
    def get_tool_directory(self, tool_name: str, tool_version: str) -> Path:
        """Get directory path for a specific tool."""
        # Tools go in the tools subdirectory under the run directory
        tool_dir = self.run_base_path / "tools" / tool_name
        tool_dir.mkdir(parents=True, exist_ok=True)
        return tool_dir
    
    def save_script(self, tool_name: str, tool_version: str, 
                   script_content: str, filename: str = "tool_setup.sh") -> Path:
        """
        Save generated installation script.
        
        Args:
            tool_name: Name of the tool
            tool_version: Version of the tool
            script_content: Script content
            filename: Script filename
            
        Returns:
            Path to saved script
        """
        tool_dir = self.get_tool_directory(tool_name, tool_version)
        script_path = tool_dir / filename
        
        # Save script
        script_path.write_text(script_content)
        script_path.chmod(0o755)  # Make executable
        
        # Calculate checksum
        checksum = hashlib.sha256(script_content.encode()).hexdigest()
        
        # Save checksum
        checksum_path = tool_dir / f"{filename}.sha256"
        checksum_path.write_text(f"{checksum}  {filename}\n")
        
        self.logger.info(f"Saved script to {script_path}")
        return script_path
    
    def save_json(self, filename: str, data: Dict[str, Any], 
                  subdirs: Optional[List[str]] = None, 
                  use_metadata_dir: bool = False) -> Path:
        """
        Save JSON data to file.
        
        Args:
            filename: JSON filename
            data: Data to save
            subdirs: Optional subdirectories under run base path
            use_metadata_dir: If True and subdirs is None, save to metadata_dir instead of run_base_path
            
        Returns:
            Path to saved file
        """
        if subdirs:
            target_dir = self.run_base_path
            for subdir in subdirs:
                target_dir = target_dir / subdir
            target_dir.mkdir(parents=True, exist_ok=True)
        elif use_metadata_dir:
            target_dir = self.metadata_dir
        else:
            # Default: save directly to run base path
            target_dir = self.run_base_path
        
        json_path = target_dir / filename
        
        # Add timestamp if not present
        if 'timestamp' not in data:
            data['timestamp'] = datetime.utcnow().isoformat()
        
        # Save JSON with pretty formatting
        with open(json_path, 'w') as f:
            json.dump(data, f, indent=2, default=str)
        
        self.logger.info(f"Saved JSON to {json_path}")
        return json_path
    
    def save_log(self, tool_name: str, tool_version: str, 
                 log_content: str, log_type: str = "installation") -> Path:
        """
        Save log file.
        
        Args:
            tool_name: Name of the tool
            tool_version: Version of the tool
            log_content: Log content
            log_type: Type of log (installation, validation, etc.)
            
        Returns:
            Path to saved log
        """
        tool_dir = self.get_tool_directory(tool_name, tool_version)
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        log_filename = f"{log_type}_{timestamp}.log"
        log_path = tool_dir / log_filename
        
        log_path.write_text(log_content)
        
        self.logger.info(f"Saved log to {log_path}")
        return log_path
    
    def save_provenance(self, tool_name: str, tool_version: str,
                       provenance_data: Dict[str, Any]) -> Path:
        """
        Save provenance information.
        
        Args:
            tool_name: Name of the tool
            tool_version: Version of the tool
            provenance_data: Provenance information
            
        Returns:
            Path to saved provenance file
        """
        # Ensure required fields
        provenance_data.setdefault('generated_at', datetime.utcnow().isoformat())
        provenance_data.setdefault('artifact_manager_version', '1.0.0')
        
        return self.save_json(
            "provenance.json",
            provenance_data,
            subdirs=[tool_name, tool_version]
        )
    
    def create_status_file(self, tool_name: str, tool_version: str, 
                          status: str, message: Optional[str] = None) -> Path:
        """
        Create a status file for quick status checks.
        
        Args:
            tool_name: Name of the tool
            tool_version: Version of the tool
            status: Status string
            message: Optional status message
            
        Returns:
            Path to status file
        """
        tool_dir = self.get_tool_directory(tool_name, tool_version)
        status_path = tool_dir / "status.txt"
        
        content = f"Status: {status}\n"
        content += f"Updated: {datetime.utcnow().isoformat()}\n"
        if message:
            content += f"Message: {message}\n"
        
        status_path.write_text(content)
        
        return status_path
    
    def list_artifacts(self, tool_name: Optional[str] = None,
                      tool_version: Optional[str] = None) -> Dict[str, List[Path]]:
        """
        List all artifacts, optionally filtered by tool.
        
        Args:
            tool_name: Optional tool name filter
            tool_version: Optional version filter
            
        Returns:
            Dictionary of artifact types to file paths
        """
        artifacts = {
            'scripts': [],
            'logs': [],
            'metadata': [],
            'provenance': []
        }
        
        if tool_name and tool_version:
            # List for specific tool
            tool_dir = self.get_tool_directory(tool_name, tool_version)
            if tool_dir.exists():
                for file_path in tool_dir.rglob('*'):
                    if file_path.is_file():
                        if file_path.suffix == '.sh':
                            artifacts['scripts'].append(file_path)
                        elif file_path.suffix == '.log':
                            artifacts['logs'].append(file_path)
                        elif file_path.name == 'provenance.json':
                            artifacts['provenance'].append(file_path)
                        elif file_path.suffix == '.json':
                            artifacts['metadata'].append(file_path)
        else:
            # List all artifacts for this run
            for file_path in self.run_base_path.rglob('*'):
                if file_path.is_file():
                    if file_path.suffix == '.sh':
                        artifacts['scripts'].append(file_path)
                    elif file_path.suffix == '.log':
                        artifacts['logs'].append(file_path)
                    elif file_path.name == 'provenance.json':
                        artifacts['provenance'].append(file_path)
                    elif file_path.suffix == '.json':
                        artifacts['metadata'].append(file_path)
        
        return artifacts
    
    def cleanup_old_artifacts(self, days: int = 30):
        """
        Clean up artifacts older than specified days.
        
        Args:
            days: Number of days to keep artifacts
        """
        import time
        cutoff_time = time.time() - (days * 24 * 60 * 60)
        
        cleaned = 0
        for file_path in self.base_path.rglob('*'):
            if file_path.is_file():
                if file_path.stat().st_mtime < cutoff_time:
                    file_path.unlink()
                    cleaned += 1
        
        # Remove empty directories
        for dir_path in sorted(self.base_path.rglob('*'), reverse=True):
            if dir_path.is_dir() and not any(dir_path.iterdir()):
                dir_path.rmdir()
        
        self.logger.info(f"Cleaned up {cleaned} old artifacts")
    
    def create_archive(self, output_path: Path, 
                      tool_name: Optional[str] = None) -> Path:
        """
        Create an archive of artifacts.
        
        Args:
            output_path: Path for the archive
            tool_name: Optional tool name to archive specific tool
            
        Returns:
            Path to created archive
        """
        if tool_name:
            source_dir = self.base_path / tool_name
            archive_name = f"{tool_name}_artifacts"
        else:
            source_dir = self.base_path
            archive_name = "all_artifacts"
        
        # Create archive
        archive_path = output_path / f"{archive_name}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
        shutil.make_archive(str(archive_path), 'zip', source_dir)
        
        final_path = Path(f"{archive_path}.zip")
        self.logger.info(f"Created archive: {final_path}")
        
        return final_path
