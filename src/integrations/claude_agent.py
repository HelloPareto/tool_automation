"""
Claude Agent that uses built-in tools for autonomous tool installation.
"""

import asyncio
import logging
import json
from typing import Dict, Any, Optional
from pathlib import Path
from datetime import datetime

from claude_agent_sdk import query, ClaudeAgentOptions
from ..models.tool import ToolSpec


class ClaudeInstallationAgent:
    """Claude agent that uses built-in tools for complete tool installation."""
    
    def __init__(self, artifacts_base_path: Path = Path("artifacts")):
        """Initialize the Claude installation agent."""
        self.logger = logging.getLogger(__name__)
        # Always use absolute path to avoid issues with Claude's working directory
        self.artifacts_base_path = artifacts_base_path.absolute()
        
    async def install_tool(self, 
                          tool_spec: ToolSpec,
                          install_standards: str,
                          base_dockerfile: str,
                          acceptance_checklist: str,
                          dry_run: bool = False) -> Dict[str, Any]:
        """
        Autonomously install a tool using Claude's built-in tools.
        
        Args:
            tool_spec: Tool specification
            install_standards: Installation standards document
            base_dockerfile: Base Dockerfile content
            acceptance_checklist: Acceptance criteria
            dry_run: If True, skip Docker execution
            
        Returns:
            Complete installation result
        """
        self.logger.info(f"Claude agent starting installation for {tool_spec.name} v{tool_spec.version}")
        
        # Configure Claude to use built-in tools
        options = ClaudeAgentOptions(
            system_prompt=self._get_system_prompt(dry_run),
            permission_mode="bypassPermissions",  # Allow all operations
            # Don't specify allowed_tools - let Claude use all built-in tools
        )
        
        # Build the task prompt
        prompt = self._build_prompt(
            tool_spec=tool_spec,
            install_standards=install_standards,
            base_dockerfile=base_dockerfile,
            acceptance_checklist=acceptance_checklist,
            dry_run=dry_run
        )
        
        # Collect all responses from Claude
        responses = []
        tool_calls = []
        files_created = []
        validation_passed = False
        docker_tested = False
        
        # Execute the autonomous agent
        async for message in query(prompt=prompt, options=options):
            if hasattr(message, 'content'):
                for block in message.content:
                    if hasattr(block, 'text'):
                        responses.append(block.text)
                        # Parse for status updates
                        text_lower = block.text.lower()
                        if "validation passed" in text_lower or "shellcheck passed" in text_lower:
                            validation_passed = True
                        if "docker" in text_lower and ("success" in text_lower or "passed" in text_lower):
                            docker_tested = True
                        # Look for file paths
                        if "wrote to" in text_lower or "created" in text_lower or "saved to" in text_lower:
                            # Try to extract file paths
                            import re
                            paths = re.findall(r'`([^`]+\.sh)`|"([^"]+\.sh)"|\'([^\']+\.sh)\'', block.text)
                            for path_tuple in paths:
                                path = next(p for p in path_tuple if p)
                                if path:
                                    files_created.append(path)
                    elif hasattr(block, 'tool_use'):
                        tool_calls.append({
                            "tool": getattr(block, 'name', 'unknown'),
                            "input": getattr(block, 'input', {})
                        })
        
        # Parse final results
        final_response = "\n".join(responses)
        
        # Determine script path
        script_path = None
        if files_created:
            # Look for the main tool_setup.sh
            for path in files_created:
                if "tool_setup.sh" in path:
                    script_path = path
                    break
            if not script_path:
                script_path = files_created[0]  # Use first script created
        else:
            # Default path
            script_path = str(self.artifacts_base_path / "tools" / tool_spec.name / "tool_setup.sh")
        
        # Build result
        result = {
            "success": validation_passed or "success" in final_response.lower(),
            "tool_name": tool_spec.name,
            "tool_version": tool_spec.version,
            "script_generated": bool(files_created) or "script" in final_response.lower(),
            "validation_passed": validation_passed,
            "docker_tested": docker_tested and not dry_run,
            "artifacts_saved": bool(files_created),
            "errors": [],
            "script_path": script_path,
            "validation_results": {
                "shellcheck": "passed" if validation_passed else "unknown",
                "syntax": "passed" if validation_passed else "unknown"
            },
            "docker_results": {
                "build": "skipped" if dry_run else ("success" if docker_tested else "failed"),
                "install": "skipped" if dry_run else ("success" if docker_tested else "failed"),
                "validate": "skipped" if dry_run else ("success" if docker_tested else "failed")
            },
            "tool_calls_made": len(tool_calls),
            "files_created": files_created,
            "claude_response": final_response
        }
        
        # Check for errors - be more specific about what constitutes an error
        error_indicators = ["error:", "failed:", "error!", "installation failed", "validation failed"]
        success_indicators = ["✓", "passed", "success", "completed successfully", "no errors"]
        
        # Count error vs success indicators
        error_count = sum(1 for indicator in error_indicators if indicator in final_response.lower())
        success_count = sum(1 for indicator in success_indicators if indicator in final_response.lower())
        
        # Only mark as error if there are more error indicators than success indicators
        if error_count > success_count:
            # Extract actual error messages (lines that start with ERROR: or contain "failed")
            error_lines = []
            for line in final_response.split('\n'):
                line_lower = line.lower()
                if any(err in line_lower for err in ["error:", "failed:", "error!"]):
                    # Skip lines that are about "no errors"
                    if "no error" not in line_lower and "passed" not in line_lower:
                        error_lines.append(line.strip())
            
            if error_lines:
                result["errors"] = error_lines[:5]  # First 5 actual error lines
                result["success"] = False
        
        self.logger.info(f"Claude made {len(tool_calls)} tool calls")
        self.logger.info(f"Installation {'succeeded' if result['success'] else 'failed'} for {tool_spec.name}")
        
        return result
    
    def _get_system_prompt(self, dry_run: bool) -> str:
        """Get the system prompt for Claude."""
        return f"""You are an expert DevOps engineer responsible for autonomously installing tools.

Many tools come from GitHub repositories. When a GitHub URL is provided, I've already analyzed the repository
to detect possible installation methods (pip, npm, binary releases, Docker, etc.). Use this information to
choose the most appropriate installation method.

Your task is to use your built-in tools to:
1. Generate an idempotent installation script following the provided standards
2. Choose the best installation method based on the tool type and available options
3. Save the script using the Write tool to artifacts/tools/<tool_name>/tool_setup.sh
4. Validate the script with shellcheck using the Bash tool
5. Check bash syntax using Bash tool with bash -n
6. {"Skip Docker testing (dry run mode)" if dry_run else "Test the installation in a Docker container using Bash tool"}
7. Report results clearly

You have access to these built-in tools:
- Write: Create files (use for saving scripts)
- Read: Read files (use to verify scripts were saved)
- Bash: Execute commands (use for shellcheck, docker commands, etc.)
- Glob: Find files by pattern
- Edit: Modify existing files

Important:
- Create the artifacts directory structure if it doesn't exist
- Save the main script as artifacts/tools/<tool_name>/tool_setup.sh
- Use Bash tool for ALL command execution (shellcheck, docker build, docker run, etc.)
- Be explicit about what you're doing at each step
- Report success/failure clearly"""
    
    def _build_prompt(self, tool_spec: ToolSpec, install_standards: str,
                     base_dockerfile: str, acceptance_checklist: str,
                     dry_run: bool) -> str:
        """Build the task prompt for Claude."""
        # Build GitHub-specific information if available
        github_info = ""
        if tool_spec.github_url:
            github_info = f"""
GitHub Repository Analysis:
- GitHub URL: {tool_spec.github_url}
- Detected Installation Methods: {', '.join(tool_spec.detected_install_methods) if tool_spec.detected_install_methods else 'None detected'}
- Package Name: {tool_spec.package_name or 'Not detected'}
- Docker Image: {tool_spec.docker_image or 'Not available'}
- Binary Pattern: {tool_spec.binary_pattern or 'No binary releases'}

Installation Documentation Found:
{tool_spec.installation_docs or 'No specific installation docs found'}
"""
        
        return f"""Install {tool_spec.name} version {tool_spec.version} following these specifications:

Tool Details:
- Name: {tool_spec.name}
- Version: {tool_spec.version}
- Validate Command: {tool_spec.validate_cmd}
- Package Manager: {tool_spec.package_manager or 'auto-detect'}
{f"- Repository URL: {tool_spec.repository_url}" if tool_spec.repository_url else ""}
{f"- GPG Key URL: {tool_spec.gpg_key_url}" if tool_spec.gpg_key_url else ""}
{github_info}

Installation Standards:
{install_standards}

Base Dockerfile:
{base_dockerfile}

Acceptance Checklist:
{acceptance_checklist}

STEP-BY-STEP INSTRUCTIONS:

1. First, ensure the directory exists:
   - Use Bash: mkdir -p {self.artifacts_base_path}/tools/{tool_spec.name}

2. Analyze the tool and choose the best installation method:
   {self._get_installation_guidance(tool_spec)}

3. Generate a complete installation script that:
   - Is idempotent (can be run multiple times safely)
   - Pins the exact version {tool_spec.version}
   - Includes a validate() function using: {tool_spec.validate_cmd}
   - Follows all the installation standards
   - Uses set -euo pipefail for safety
   - Uses the most appropriate installation method based on the tool type

4. Save the script:
   - Use Write tool to save to: {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Verify it was saved correctly with Read tool

5. Validate the script:
   - Use Bash: shellcheck -x {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Use Bash: bash -n {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Report any issues found

6. {"Skip Docker testing due to dry run mode" if dry_run else f'''Test in Docker:
   - Create a test directory with Bash: mkdir -p /tmp/docker_test_{tool_spec.name}_{tool_spec.version}
   - Use Write to create Dockerfile at: /tmp/docker_test_{tool_spec.name}_{tool_spec.version}/Dockerfile
     Content should be based on the base Dockerfile and copy/run your script
   - Copy the script with Bash: cp {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh /tmp/docker_test_{tool_spec.name}_{tool_spec.version}/
   - Use Bash: cd /tmp/docker_test_{tool_spec.name}_{tool_spec.version} && docker build -t test_{tool_spec.name}_{tool_spec.version} .
   - Use Bash: docker run --rm test_{tool_spec.name}_{tool_spec.version} {tool_spec.validate_cmd}
   - Clean up with Bash: docker rmi test_{tool_spec.name}_{tool_spec.version} && rm -rf /tmp/docker_test_{tool_spec.name}_{tool_spec.version}'''}

7. Summary:
   - Report if all steps completed successfully
   - List any errors encountered
   - Confirm the script is saved at the correct location
   - Report which installation method was used

Remember:
- Use Bash tool for ALL command execution
- Use Write tool to create files
- Use Read tool to verify files
- Be explicit about each step and its result
- The script MUST be saved to: {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh"""
    
    def _get_installation_guidance(self, tool_spec: ToolSpec) -> str:
        """Get specific installation guidance based on detected methods."""
        if not tool_spec.detected_install_methods:
            return """
   - No specific installation method detected
   - Check if there are binary releases available
   - Look for installation documentation in README
   - Consider building from source if necessary"""
        
        guidance = []
        
        # Python packages
        if "pip" in tool_spec.detected_install_methods:
            pkg = tool_spec.package_name or tool_spec.name
            guidance.append(f"""
   - Python package detected: Use pip install {pkg}
   - Check PyPI for available versions
   - Consider using virtual environment""")
        
        # Node.js packages
        if "npm" in tool_spec.detected_install_methods:
            pkg = tool_spec.package_name or tool_spec.name
            guidance.append(f"""
   - Node.js package detected: Use npm install -g {pkg}
   - Check npm registry for versions""")
        
        # Go packages
        if "go_install" in tool_spec.detected_install_methods:
            pkg = tool_spec.package_name or f"github.com/{tool_spec.github_url.split('/')[-2]}/{tool_spec.github_url.split('/')[-1]}"
            guidance.append(f"""
   - Go module detected: Use go install {pkg}@{tool_spec.version}
   - Ensure Go is available in the environment""")
        
        # Binary releases
        if "binary_release" in tool_spec.detected_install_methods:
            guidance.append(f"""
   - Binary releases available on GitHub
   - Download appropriate binary for Linux amd64
   - Pattern: {tool_spec.binary_pattern or 'Check releases page'}""")
        
        # Docker
        if "docker" in tool_spec.detected_install_methods:
            img = tool_spec.docker_image or f"{tool_spec.name}:latest"
            guidance.append(f"""
   - Docker image available: {img}
   - Consider if Docker installation is appropriate
   - May need wrapper script for CLI usage""")
        
        # Docker Compose
        if "docker_compose" in tool_spec.detected_install_methods:
            guidance.append("""
   - Docker Compose setup available
   - This is typically for full applications, not CLI tools
   - Consider extracting just the necessary components""")
        
        return "\n".join(guidance) if guidance else """
   - Use the detected methods as guidance
   - Choose the most appropriate for a system-wide installation
   - Prefer binary releases or package managers over building from source"""
