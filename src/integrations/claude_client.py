"""
Claude integration for generating installation scripts.
"""

import asyncio
import hashlib
import json
import logging
from typing import Optional, Dict, Any
from datetime import datetime
from pathlib import Path

from claude_agent_sdk import query, ClaudeAgentOptions
from ..models.claude import ClaudeResponse, SelfReview, SelfReviewItem, ScriptMetadata
from ..models.tool import ToolSpec


class ClaudeClient:
    """Client for interacting with Claude to generate installation scripts."""
    
    def __init__(self, api_key: Optional[str] = None, 
                 model: str = "claude-sonnet-4-5-20250929",
                 max_tokens: int = 4096,
                 temperature: float = 0.2):
        """
        Initialize Claude client.
        
        Args:
            api_key: Anthropic API key (uses env var if not provided)
            model: Claude model to use
            max_tokens: Maximum tokens for response
            temperature: Temperature for generation (lower = more deterministic)
        """
        self.logger = logging.getLogger(__name__)
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.api_key = api_key
        
        # Configure Claude options
        self.options = ClaudeAgentOptions(
            system_prompt=self._get_system_prompt(),
            # We'll use temperature through the API if possible
        )
    
    async def generate_installation_script(self, 
                                         tool_spec: ToolSpec,
                                         install_standards: str,
                                         base_dockerfile: str,
                                         acceptance_checklist: str) -> ClaudeResponse:
        """
        Generate installation script for a tool.
        
        Args:
            tool_spec: Tool specification
            install_standards: Installation standards document
            base_dockerfile: Base Dockerfile content
            acceptance_checklist: Acceptance criteria
            
        Returns:
            Claude response with generated script
        """
        # Build the prompt
        prompt = self._build_prompt(
            tool_spec=tool_spec,
            install_standards=install_standards,
            base_dockerfile=base_dockerfile,
            acceptance_checklist=acceptance_checklist
        )
        
        # Calculate prompt hash for provenance
        prompt_hash = hashlib.sha256(prompt.encode()).hexdigest()[:16]
        
        try:
            # Query Claude
            self.logger.info(f"Generating script for {tool_spec.name} v{tool_spec.version}")
            
            response_text = ""
            async for message in query(prompt=prompt, options=self.options):
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            response_text += block.text
            
            # Parse JSON response
            try:
                # Extract JSON from response (Claude might add markdown formatting)
                json_start = response_text.find('{')
                json_end = response_text.rfind('}') + 1
                if json_start >= 0 and json_end > json_start:
                    json_text = response_text[json_start:json_end]
                else:
                    json_text = response_text
                
                response_data = json.loads(json_text)
                
                # Convert to ClaudeResponse model
                claude_response = self._parse_response(response_data, prompt_hash)
                
                self.logger.info(f"Successfully generated script for {tool_spec.name}")
                return claude_response
                
            except json.JSONDecodeError as e:
                self.logger.error(f"Failed to parse Claude response as JSON: {e}")
                # Create a fallback response
                return self._create_fallback_response(
                    tool_spec, prompt_hash, 
                    error=f"Invalid JSON response: {str(e)}"
                )
                
        except Exception as e:
            self.logger.error(f"Error generating script: {e}")
            raise
    
    def _get_system_prompt(self) -> str:
        """Get the system prompt for Claude."""
        return """You are a senior DevOps engineer. Generate idempotent Linux installers that strictly follow the attached Solutions Team Install Standards and target the attached base Dockerfile. Never deviate from the standards. Output must be a single JSON object with keys: plan, script_bash, metadata, and self_review. script_bash must be a complete Bash script starting with #!/usr/bin/env bash and set -euo pipefail. The installer must be repeatable, version-pinned, non-interactive, and include a validate() that runs ${validate_cmd} and exits 0. If a requirement is impossible, explain under self_review.blockers and still return your best safe attempt."""
    
    def _build_prompt(self, tool_spec: ToolSpec, install_standards: str,
                     base_dockerfile: str, acceptance_checklist: str) -> str:
        """Build the user prompt for Claude."""
        # Convert tool spec to YAML-like format
        tool_yaml = f"""name: {tool_spec.name}
version: {tool_spec.version}
validate_cmd: {tool_spec.validate_cmd}
description: {tool_spec.description or 'N/A'}
package_manager: {tool_spec.package_manager or 'auto'}"""
        
        if tool_spec.repository_url:
            tool_yaml += f"\nrepository_url: {tool_spec.repository_url}"
        if tool_spec.gpg_key_url:
            tool_yaml += f"\ngpg_key_url: {tool_spec.gpg_key_url}"
        if tool_spec.dependencies:
            tool_yaml += f"\ndependencies: {', '.join(tool_spec.dependencies)}"
        if tool_spec.post_install_steps:
            tool_yaml += f"\npost_install_steps:\n"
            for step in tool_spec.post_install_steps:
                tool_yaml += f"  - {step}\n"
        
        prompt = f"""Inputs

Install Standards (verbatim excerpt):
<<<INSTALL_STANDARDS>>>
{install_standards}
<<<INSTALL_STANDARDS>>>

Base Dockerfile (read-only):
<<<BASE_DOCKERFILE>>>
{base_dockerfile}
<<<BASE_DOCKERFILE>>>

Acceptance Checklist:
<<<ACCEPTANCE_CHECKLIST>>>
{acceptance_checklist}
<<<ACCEPTANCE_CHECKLIST>>>

Tool Spec (YAML):
<<<TOOL_SPEC_YAML>>>
{tool_yaml}
<<<TOOL_SPEC_YAML>>>

Task

Propose a concise step-by-step plan.

Produce tool_setup.sh as script_bash. Requirements:
- #!/usr/bin/env bash + set -euo pipefail.
- Idempotent: skip if installed at requested version.
- Pin versions; verify downloads with checksums/signatures if applicable.
- Use OS-native package repos per standards (e.g., apt with GPG keyring under /usr/share/keyrings).
- Clean caches; minimize layers; no interactivity (DEBIAN_FRONTEND=noninteractive).
- Implement validate() that runs ${{validate_cmd}} and fails loudly on mismatch.

Complete self_review: checklist pass/fail with explanations and any blockers.

Return only the JSON object, no prose."""
        
        return prompt
    
    def _parse_response(self, response_data: Dict[str, Any], 
                       prompt_hash: str) -> ClaudeResponse:
        """Parse Claude's JSON response into our model."""
        # Parse self_review
        self_review_data = response_data.get('self_review', {})
        
        # Parse checklist items
        checklist_items = []
        if 'checklist' in self_review_data:
            for item in self_review_data['checklist']:
                if isinstance(item, dict):
                    checklist_items.append(SelfReviewItem(
                        criterion=item.get('criterion', 'Unknown'),
                        passed=item.get('passed', False),
                        explanation=item.get('explanation', '')
                    ))
        
        # Calculate confidence based on checklist
        passed_count = sum(1 for item in checklist_items if item.passed)
        total_count = len(checklist_items) if checklist_items else 1
        confidence = passed_count / total_count
        
        self_review = SelfReview(
            checklist=checklist_items,
            blockers=self_review_data.get('blockers'),
            warnings=self_review_data.get('warnings'),
            overall_confidence=self_review_data.get('overall_confidence', confidence)
        )
        
        # Create response
        return ClaudeResponse(
            plan=response_data.get('plan', []),
            script_bash=response_data.get('script_bash', ''),
            metadata=response_data.get('metadata', {}),
            self_review=self_review
        )
    
    def _create_fallback_response(self, tool_spec: ToolSpec, 
                                 prompt_hash: str, error: str) -> ClaudeResponse:
        """Create a fallback response when parsing fails."""
        return ClaudeResponse(
            plan=["Failed to generate valid installation script"],
            script_bash="#!/usr/bin/env bash\necho 'Script generation failed'\nexit 1",
            metadata={"error": error, "tool": tool_spec.name},
            self_review=SelfReview(
                checklist=[
                    SelfReviewItem(
                        criterion="Script Generation",
                        passed=False,
                        explanation=error
                    )
                ],
                blockers=[error],
                overall_confidence=0.0
            )
        )
