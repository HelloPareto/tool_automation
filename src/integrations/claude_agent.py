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
        
        # Extract complexity assessment from response
        complexity_assessment = self._extract_complexity_assessment(final_response)
        
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
            "claude_response": final_response,
            "complexity_assessment": complexity_assessment  # New field
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

    async def validate_composed_image(self, compose_dir: str, run_all_path: str, image_tag: str) -> Dict[str, Any]:
        """Ask Claude (built-in tools) to build and validate the composed image end-to-end.

        Args:
            compose_dir: Directory containing Dockerfile, run_all.sh and tools/
            run_all_path: Full path to run_all.sh (for reference)
            image_tag: Docker image tag to use for build/run

        Returns:
            Dict with success flag and basic logs
        """
        self.logger.info(f"Claude compose validation starting for {compose_dir} → {image_tag}")

        system_prompt = "You are an expert DevOps engineer. Use Bash to build, test, and SELF-HEAL the provided compose context."
        options = ClaudeAgentOptions(system_prompt=system_prompt, permission_mode="bypassPermissions")

        prompt = f"""
Validate multi-tool composition with self-healing:

Context:
- Compose dir: {compose_dir}
- Image tag: {image_tag}
- Entrypoint script: /workspace/run_all.sh (copied by Dockerfile)

Procedure:
1) Build image:
   - Bash: cd {compose_dir} && docker build --platform linux/amd64 --progress=plain -t {image_tag} .
2) Run container:
   - Bash: docker run --rm -e DEBIAN_FRONTEND=noninteractive {image_tag} bash -lc "/workspace/run_all.sh"
3) On failure, DIAGNOSE and SELF-HEAL, then REBUILD and RE-RUN (up to 2 retries):
   a) Parse logs to identify the failing tool and error category (missing shared library, unbound variable, quoting, etc.).
   b) If missing shared library (e.g., libxslt.so.1):
      - Edit {compose_dir}/shared_setup.sh to apt-get install the corresponding jammy package and add `ldconfig`.
      - Also edit artifacts/tools/<tool>/tool_manifest.json to include the apt package.
      - If the tool installer needs to run `ldconfig`, add it in artifacts/tools/<tool>/tool_setup.sh after apt installs.
   c) If script error (e.g., "unbound variable"):
      - Edit artifacts/tools/<tool>/tool_setup.sh to safely initialize variables and add tmp_dir + trap cleanup as needed.
      - Run shellcheck and bash -n.
   d) If validation quoting issue:
      - Regenerate compose/run_all.sh validation line for that tool with correct quoting (`bash -lc '...'` or `"..."`).
   e) After edits, re-copy updated files into {compose_dir} if needed, rebuild the image and re-run run_all.sh.
4) Success criteria:
   - Only report success after printing COMPOSE_VALIDATION_SUCCESS.
"""

        responses = []
        success = False
        tool_calls = 0

        async for message in query(prompt=prompt, options=options):
            if hasattr(message, 'content'):
                for block in message.content:
                    if hasattr(block, 'text'):
                        text = block.text
                        responses.append(text)
                        if "COMPOSE_VALIDATION_SUCCESS" in text:
                            success = True
                    elif hasattr(block, 'tool_use'):
                        tool_calls += 1

        full = "\n".join(responses)
        if not success:
            # Heuristic: success if no obvious error words and mentions of completion
            lowered = full.lower()
            if ("error" not in lowered and "failed" not in lowered) and ("completed successfully" in lowered or "validation successful" in lowered or "installation completed successfully" in lowered):
                success = True

        self.logger.info(f"Compose validation {'succeeded' if success else 'failed'} for {image_tag}")
        return {
            "success": success,
            "image_tag": image_tag,
            "compose_dir": compose_dir,
            "tool_calls_made": tool_calls,
            "logs": full[-5000:]  # tail
        }
    
    def _get_system_prompt(self, dry_run: bool) -> str:
        """Get the system prompt for Claude."""
        return f"""You are an expert DevOps engineer responsible for autonomously installing tools.

When a GitHub URL is provided, YOU must analyze the repository to determine the best installation method.
Do NOT rely on pre-analysis - research the specific repository yourself using web search and/or cloning.

Your task is to use your built-in tools to:
1. **Analyze the repository** (if GitHub URL provided):
   - Web search for installation docs specific to that GitHub repository
   - Clone and examine the repository if needed to understand installation approach
   - Determine the best method: pip, npm, binary, Docker, source build, etc.
2. Generate an idempotent installation script with prerequisite handling
3. Save the script using the Write tool to artifacts/tools/<tool_name>/tool_setup.sh
4. Validate the script with shellcheck and bash syntax checks using the Bash tool
5. {"Skip Docker testing (dry run mode)" if dry_run else "Test the installation in a Docker container using Bash tool"}
6. Assess the installation complexity
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
GitHub Repository: {tool_spec.github_url}
"""
        
        return f"""Install {tool_spec.name} version {tool_spec.version} following these specifications:

Tool Details:
- Name: {tool_spec.name}
- Version: {tool_spec.version}
- Validate Command: {tool_spec.validate_cmd}
- Description: {tool_spec.description or 'Not provided'}
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

1. **ANALYZE THE REPOSITORY** (REQUIRED):
   {"Since this is a GitHub-based installation, you MUST research the repository first:" if tool_spec.github_url else "Ensure the directory exists:"}
   
   {"a) Research installation methods for this SPECIFIC repository:" if tool_spec.github_url else ""}
      {"- Use github based web search to find: installation guide for " + tool_spec.github_url if tool_spec.github_url else ""}
      {"- Focus on official documentation from this repository" if tool_spec.github_url else ""}
      {"- Check GitHub releases page for binary downloads" if tool_spec.github_url else ""}
      {"- Look for: README.md installation sections, INSTALL.md, docs/installation.md" if tool_spec.github_url else ""}
   
   {"b) If needed, clone and analyze the repository locally:" if tool_spec.github_url else ""}
      {"- Use Bash: git clone --depth 1 " + tool_spec.github_url + " /tmp/" + tool_spec.name + "_analysis" if tool_spec.github_url else ""}
      {"- Use Read or Bash to check key files:" if tool_spec.github_url else ""}
        {"* README.md (installation instructions)" if tool_spec.github_url else ""}
        {"* setup.py / pyproject.toml (Python)" if tool_spec.github_url else ""}
        {"* package.json (Node.js)" if tool_spec.github_url else ""}
        {"* go.mod (Go)" if tool_spec.github_url else ""}
        {"* Cargo.toml (Rust)" if tool_spec.github_url else ""}
        {"* Makefile / CMakeLists.txt (build system)" if tool_spec.github_url else ""}
        {"* Dockerfile (containerized)" if tool_spec.github_url else ""}
      {"- Use Bash to clean up: rm -rf /tmp/" + tool_spec.name + "_analysis" if tool_spec.github_url else ""}
   
   {"c) Determine the BEST installation method based on your research:" if tool_spec.github_url else ""}
      {"- Python: pip install (check for package on PyPI)" if tool_spec.github_url else ""}
      {"- Node.js: npm install -g (check npm registry)" if tool_spec.github_url else ""}
      {"- Go: go install github.com/..." if tool_spec.github_url else ""}
      {"- Binary: Download from GitHub releases" if tool_spec.github_url else ""}
      {"- Docker: Use official Docker image if available" if tool_spec.github_url else ""}
      {"- Build from source: Last resort for complex tools" if tool_spec.github_url else ""}
   
   {"d) Create the directory:" if tool_spec.github_url else "- Use Bash: mkdir -p " + str(self.artifacts_base_path) + "/tools/" + tool_spec.name}
      {"- Use Bash: mkdir -p " + str(self.artifacts_base_path) + "/tools/" + tool_spec.name if tool_spec.github_url else ""}

2. **DETECT PREREQUISITES** - Based on the installation method you chose:
   - Identify programming languages needed (Python, Node.js, Go, Java, Rust, etc.)
   - Identify build tools if needed (gcc, make, cmake, etc.)
   - Identify system libraries or dependencies
   - List ALL prerequisites before proceeding
   - Target OS/arch for all apt packages: Ubuntu 22.04 (jammy), amd64
   - Distinguish clearly between apt-installable system packages vs Python/Node packages:
     * prerequisites.apt MUST contain valid Debian/Ubuntu package names (e.g., libssl-dev, libpq-dev, libgdal-dev, gdal-bin)
     * Do NOT place Python-only packages (e.g., cartopy, geopandas, h5py) in prerequisites.apt or prerequisites.libs; install them with pip inside install_tool()
     * For C/C++ libs, prefer -dev variants that provide headers (e.g., libxml2-dev, libxslt1-dev, zlib1g-dev)
     * Avoid conceptual names (e.g., GDAL) — map to concrete apt names (e.g., libgdal-dev, gdal-bin)

3. **CHOOSE INSTALLATION APPROACH**:
   - Based on your repository analysis above, select the most appropriate method
   - Prefer simpler methods (package managers) over complex (source builds)
   - Consider: ease of installation, version pinning, reproducibility

4. Generate a complete installation script with PREREQUISITE HANDLING:
   
   The script MUST include these functions IN ORDER:
   
   a) **check_prerequisites()** - Check if prerequisites are already installed
      - Use `command -v <tool>` or version checks
      - Return 0 if all present, 1 if any missing
      - Log what's found and what's missing
   
   b) **install_prerequisites()** - Install missing prerequisites
      - Only install what's not already present (idempotency)
      - Use appropriate package managers (apt-get, yum, etc.)
      - Pin versions where possible
      - Examples:
        * Python: `apt-get install -y python3 python3-pip python3-venv`
        * Node.js: `apt-get install -y nodejs npm` or use NodeSource
        * Go: Download and extract to `/usr/local/go`
        * Java: `apt-get install -y openjdk-11-jre-headless`
        * Build tools: `apt-get install -y build-essential`
   
   c) **verify_prerequisites()** - Verify prerequisites work correctly
      - Run version checks for each prerequisite
      - Exit with error if any verification fails
      - Examples:
        * Python: `python3 --version && pip3 --version`
        * Node: `node --version && npm --version`
        * Go: `go version`
        * Java: `java -version`
   
   d) **check_existing_installation()** - Check if tool is already installed (idempotency)
   
   e) **install_tool()** - Install the actual tool (only after prerequisites verified)
   
   f) **validate()** - Validate the tool installation using: {tool_spec.validate_cmd}
   
   The main() function must call these IN THIS ORDER:
   ```bash
   main() {{
       log "Starting {tool_spec.name} {tool_spec.version} installation..."
       
       # Step 1: Prerequisites
       if ! check_prerequisites; then
           install_prerequisites
           verify_prerequisites
       fi
       
       # Step 2: Check if already installed
       if check_existing_installation; then
           validate
           exit 0
       fi
       
       # Step 3: Install the tool
       install_tool
       
       # Step 4: Validate
       validate
       
       log "Installation completed successfully"
   }}
   ```
   
   Other requirements:
   - Is idempotent (can be run multiple times safely)
   - Pins the exact version {tool_spec.version}
   - Follows all the installation standards
   - Uses set -euo pipefail for safety
   - Clear logging with timestamps
   - Actionable error messages
   - MUST support a flag `--skip-prereqs` (or env `RESPECT_SHARED_DEPS=1`) to bypass installing prerequisites when a shared layer already provided them
   - MUST NOT run `apt-get clean` or remove apt caches; central orchestration manages cleanup to preserve caching across multi-tool installs
   - MUST NOT start background services; if services are needed, declare them in the manifest (below) but do not start them here

   Self-healing requirements (MANDATORY):
   - Initialize variables safely under `set -euo pipefail` to avoid unbound variable errors.
     Example pattern to include at top of script:
     ```bash
     set -euo pipefail
     IFS=$'\n\t'
     tmp_dir="${{tmp_dir:-$(mktemp -d)}}"
     trap 'rm -rf "$tmp_dir"' EXIT
     ```
   - After install_tool(), perform runtime linkage verification for primary binaries:
     * Identify the installed binary path(s) (e.g., `command -v <tool>` or known path).
     * Run `ldd <binary> | grep "not found"` to detect missing shared libraries.
     * For each missing `.so`, map it to an Ubuntu 22.04 apt package and install it, then run `ldconfig`.
       Example mappings: libxslt.so.1→libxslt1.1, libpq.so.*→libpq5/libpq-dev, libgdal.so.*→libgdal30/libgdal-dev, libxml2.so.2→libxml2/libxml2-dev, zlib→zlib1g/zlib1g-dev.
     * Re-run `ldd` to ensure no missing libraries remain.
     * Update `tool_manifest.json` prerequisites.apt/libs to reflect any added packages.

5. Save the script:
   - Use Write tool to save to: {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Verify it was saved correctly with Read tool
  - ALSO write a manifest describing prerequisites and validation to: {self.artifacts_base_path}/tools/{tool_spec.name}/tool_manifest.json with this JSON schema:
     ```json
     {{
       "name": "{tool_spec.name}",
       "version": "{tool_spec.version}",
       "prerequisites": {{
         "apt": ["curl", "ca-certificates"],
         "runtimes": ["python", "node", "go", "java", "rust"],
         "libs": ["libssl-dev"],
         "services": ["docker", "postgres"]
       }},
       "env_exports": {{ "PATH": ["/usr/local/bin"] }},
       "validate_cmd": "{tool_spec.validate_cmd}",
       "requires_compilation": false
     }}
     ```
     Strict rules for `prerequisites`:
     - `apt`: Only Debian/Ubuntu package identifiers valid on Ubuntu 22.04 jammy (amd64). Use concrete names (e.g., libpq-dev) — never conceptual names (e.g., PostgreSQL client).
     - `libs`: Only system library packages (often lib*-dev). Do NOT include Python libraries; install those with pip within install_tool().
     - If a dependency does not have an apt package, omit it from `apt`/`libs` and document/install via the appropriate language package manager inside install_tool().

6. Validate the script:
   - Use Bash: shellcheck -x {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Use Bash: bash -n {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
   - Report any issues found

7. {"Skip Docker testing due to dry run mode" if dry_run else f'''Test in Docker:
           - Create a test directory with Bash: mkdir -p /tmp/docker_test_{tool_spec.name}_{tool_spec.version}
           - Use Write to create Dockerfile at: /tmp/docker_test_{tool_spec.name}_{tool_spec.version}/Dockerfile
             Content should be based on the base Dockerfile and COPY your script into the image, but DO NOT RUN it during build.
             Example Dockerfile snippet:
             # --- begin ---
             # Base content from provided base Dockerfile above
             # add required runtime packages only if absolutely necessary
             COPY tool_setup.sh /workspace/tool_setup.sh
             RUN chmod +x /workspace/tool_setup.sh
             # --- end ---
           - Copy the script with Bash: cp {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh /tmp/docker_test_{tool_spec.name}_{tool_spec.version}/
           - Use Bash: cd /tmp/docker_test_{tool_spec.name}_{tool_spec.version} && docker build --platform linux/amd64 --progress=plain --no-cache -t test_{tool_spec.name}_{tool_spec.version} .
             Note: Build may take 10-30 minutes for complex tools with compilation so build docker container with 30 mins as runtime initially. Be patient.
           - Use Bash: docker run --rm -e DEBIAN_FRONTEND=noninteractive test_{tool_spec.name}_{tool_spec.version} bash -lc "/workspace/tool_setup.sh && {tool_spec.validate_cmd}"
           - Clean up with Bash: docker rmi test_{tool_spec.name}_{tool_spec.version} && rm -rf /tmp/docker_test_{tool_spec.name}_{tool_spec.version}'''}

8. Summary:
   - Report if all steps completed successfully
   - List any errors encountered
   - Confirm the script is saved at the correct location
   - Report which installation method was used

9. **COMPLEXITY ASSESSMENT** (Required):
   Based on the installation you just completed, provide a complexity assessment as JSON.
   
   Analyze these factors:
   • Prerequisites: How many? How common? (Python/Node = common, CUDA = rare)
   • Installation Method: Package manager (simple) vs binary vs source compilation (complex)
   • Build Process: None vs simple make vs complex toolchain
   • Dependencies: Count and nature
   • Special Requirements: Architecture-specific, checksums, services, etc.
   
   Complexity scale (1-10):
   • 1-2: Very Low (single pip/npm, no prerequisites)
   • 3-4: Low (1-2 common prerequisites, straightforward)
   • 5-6: Medium (multiple steps, verification, architecture detection)
   • 7-8: High (compilation, many prerequisites, complex dependencies)
   • 9-10: Very High (exotic dependencies, platform-specific toolchains)
   
   IMPORTANT: At the end of your response, provide this JSON block:
   
   ```json
   {{
     "summary": "3-4 sentences explaining installation complexity. Focus on what makes this tool simple or complex. Mention prerequisites, installation method, and special requirements.",
     "score": <1-10>,
     "key_factors": [
       "Most impactful complexity factor",
       "Second factor",
       "Third factor if applicable"
     ],
     "installation_method": "<pip|npm|binary|docker|source|go_install|script|custom>",
     "prerequisites_count": <number>,
     "requires_compilation": <true|false>
   }}
   ```

Remember:
- Use Bash tool for ALL command execution
- Use Write tool to create files
- Use Read tool to verify files
- Be explicit about each step and its result
- The script MUST be saved to: {self.artifacts_base_path}/tools/{tool_spec.name}/tool_setup.sh
- **End with the complexity assessment JSON**"""
    
    def _extract_complexity_assessment(self, response: str) -> dict:
        """
        Extract complexity assessment JSON from Claude's response.
        
        Args:
            response: Full response text from Claude
            
        Returns:
            Dictionary with complexity assessment, or default if not found
        """
        import json
        import re
        
        # Try to find JSON block in response (looking for the complexity assessment)
        # Pattern 1: Look for JSON in code blocks
        json_pattern = r'```json\s*(\{[^`]*?"summary"[^`]*?\})\s*```'
        matches = re.findall(json_pattern, response, re.DOTALL | re.IGNORECASE)
        
        if matches:
            # Try to parse the last JSON block (should be the complexity assessment)
            for match in reversed(matches):
                try:
                    assessment = json.loads(match)
                    # Validate it's a complexity assessment
                    if "summary" in assessment and "score" in assessment:
                        self.logger.info(f"Successfully extracted complexity assessment: score={assessment.get('score')}")
                        return assessment
                except json.JSONDecodeError:
                    continue
        
        # Pattern 2: Look for raw JSON (without code blocks)
        json_pattern2 = r'\{[^{}]*"summary"[^{}]*"score"[^{}]*\}'
        matches2 = re.findall(json_pattern2, response, re.DOTALL)
        
        if matches2:
            for match in reversed(matches2):
                try:
                    assessment = json.loads(match)
                    if "summary" in assessment and "score" in assessment:
                        self.logger.info(f"Extracted complexity assessment from raw JSON: score={assessment.get('score')}")
                        return assessment
                except json.JSONDecodeError:
                    continue
        
        # Default if not found
        self.logger.warning("Could not extract complexity assessment from Claude's response")
        return {
            "summary": "Complexity assessment not provided by Claude.",
            "score": None,
            "key_factors": [],
            "installation_method": "unknown",
            "prerequisites_count": 0,
            "requires_compilation": False
        }
