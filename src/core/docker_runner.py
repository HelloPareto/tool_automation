"""
Docker runner for executing installation scripts in containers.
"""

import asyncio
import logging
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional
import subprocess
import shutil
import time

from ..models.installation import ValidationResult, ValidationStatus
from ..models.tool import ToolSpec


class DockerRunner:
    """Runs installation scripts in Docker containers for validation."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize Docker runner.
        
        Args:
            config: Docker configuration dictionary
        """
        self.logger = logging.getLogger(__name__)
        self.config = config
        self.base_image = config.get('base_image', 'ubuntu:22.04')
        self.build_timeout = config.get('build_timeout', 300)
        self.run_timeout = config.get('run_timeout', 600)
        self.cleanup_containers = config.get('cleanup_containers', True)
        
        self._check_docker()
    
    def _check_docker(self):
        """Check if Docker is available."""
        if not shutil.which('docker'):
            raise RuntimeError("Docker not found. Please install Docker.")
        
        # Check if Docker daemon is running
        try:
            subprocess.run(
                ['docker', 'info'],
                capture_output=True,
                check=True,
                timeout=5
            )
        except Exception as e:
            raise RuntimeError(f"Docker daemon not accessible: {e}")
    
    async def run_installation(self, 
                             script_path: Path,
                             tool_spec: ToolSpec,
                             base_image: Optional[str] = None) -> ValidationResult:
        """
        Run installation script in a Docker container.
        
        Args:
            script_path: Path to the installation script
            tool_spec: Tool specification
            base_image: Override base image if needed
            
        Returns:
            Validation result
        """
        image = base_image or self.base_image
        container_name = f"tool-install-{tool_spec.name}-{int(time.time())}"
        
        try:
            # Create temporary directory for Docker context
            with tempfile.TemporaryDirectory() as temp_dir:
                temp_path = Path(temp_dir)
                
                # Copy script to temp directory
                script_copy = temp_path / "tool_setup.sh"
                shutil.copy2(script_path, script_copy)
                script_copy.chmod(0o755)
                
                # Create Dockerfile
                dockerfile_content = self._create_dockerfile(image, tool_spec)
                dockerfile_path = temp_path / "Dockerfile"
                dockerfile_path.write_text(dockerfile_content)
                
                # Build Docker image
                self.logger.info(f"Building Docker image for {tool_spec.name}")
                build_result = await self._build_image(
                    context_path=temp_path,
                    image_tag=f"{container_name}:latest"
                )
                
                if not build_result[0]:
                    return ValidationResult(
                        step="docker_build",
                        status=ValidationStatus.FAILED,
                        error="Failed to build Docker image",
                        output=build_result[1]
                    )
                
                # Run the installation
                self.logger.info(f"Running installation for {tool_spec.name}")
                run_result = await self._run_container(
                    image_tag=f"{container_name}:latest",
                    container_name=container_name,
                    tool_spec=tool_spec
                )
                
                return run_result
                
        except Exception as e:
            self.logger.error(f"Docker execution error: {e}")
            return ValidationResult(
                step="docker_execution",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
        finally:
            # Cleanup
            if self.cleanup_containers:
                await self._cleanup(container_name)
    
    def _create_dockerfile(self, base_image: str, tool_spec: ToolSpec) -> str:
        """Create Dockerfile for testing installation."""
        return f"""FROM {base_image}

# Copy installation script
COPY tool_setup.sh /tmp/tool_setup.sh
RUN chmod +x /tmp/tool_setup.sh

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TOOL_NAME={tool_spec.name}
ENV TOOL_VERSION={tool_spec.version}

# Run installation script
RUN /tmp/tool_setup.sh

# Validate installation
RUN {tool_spec.validate_cmd}

# Default command
CMD ["/bin/bash"]
"""
    
    async def _build_image(self, context_path: Path, image_tag: str) -> tuple[bool, str]:
        """Build Docker image."""
        try:
            process = await asyncio.create_subprocess_exec(
                'docker', 'build',
                '--no-cache',
                '-t', image_tag,
                str(context_path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT
            )
            
            # Wait with timeout
            try:
                stdout, _ = await asyncio.wait_for(
                    process.communicate(),
                    timeout=self.build_timeout
                )
                output = stdout.decode() if stdout else ""
                
                if process.returncode == 0:
                    return True, output
                else:
                    return False, output
                    
            except asyncio.TimeoutError:
                process.terminate()
                await process.wait()
                return False, f"Build timed out after {self.build_timeout} seconds"
                
        except Exception as e:
            return False, str(e)
    
    async def _run_container(self, 
                           image_tag: str,
                           container_name: str,
                           tool_spec: ToolSpec) -> ValidationResult:
        """Run container and validate installation."""
        try:
            # Run validation command in container
            cmd = [
                'docker', 'run',
                '--rm',
                '--name', container_name,
                image_tag,
                'bash', '-c', tool_spec.validate_cmd
            ]
            
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            # Wait with timeout
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=self.run_timeout
                )
                
                output = f"STDOUT:\n{stdout.decode()}\n\nSTDERR:\n{stderr.decode()}"
                
                if process.returncode == 0:
                    # Parse version from output if possible
                    version_info = self._extract_version(stdout.decode(), tool_spec)
                    
                    return ValidationResult(
                        step="docker_validation",
                        status=ValidationStatus.PASSED,
                        output=f"Tool installed successfully. {version_info}",
                        duration_seconds=0  # TODO: Track actual duration
                    )
                else:
                    return ValidationResult(
                        step="docker_validation",
                        status=ValidationStatus.FAILED,
                        error=f"Validation command failed with exit code {process.returncode}",
                        output=output
                    )
                    
            except asyncio.TimeoutError:
                process.terminate()
                await process.wait()
                return ValidationResult(
                    step="docker_validation",
                    status=ValidationStatus.FAILED,
                    error=f"Validation timed out after {self.run_timeout} seconds"
                )
                
        except Exception as e:
            return ValidationResult(
                step="docker_validation",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _extract_version(self, output: str, tool_spec: ToolSpec) -> str:
        """Try to extract version information from output."""
        import re
        
        # Common version patterns
        patterns = [
            r'[vV]ersion[:\s]+(\d+\.\d+\.\d+)',
            r'(\d+\.\d+\.\d+)',
            fr'{tool_spec.name}[:\s]+(\d+\.\d+\.\d+)',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, output)
            if match:
                detected = match.group(1)
                if detected == tool_spec.version:
                    return f"Version verified: {detected}"
                else:
                    return f"Version mismatch: expected {tool_spec.version}, got {detected}"
        
        return "Version extracted from output"
    
    async def _cleanup(self, container_name: str):
        """Clean up Docker resources."""
        try:
            # Remove container if it exists
            subprocess.run(
                ['docker', 'rm', '-f', container_name],
                capture_output=True,
                timeout=10
            )
            
            # Remove image
            subprocess.run(
                ['docker', 'rmi', f"{container_name}:latest"],
                capture_output=True,
                timeout=10
            )
        except Exception as e:
            self.logger.warning(f"Cleanup error: {e}")
