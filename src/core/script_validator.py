"""
Script validation module for checking generated installation scripts.
"""

import subprocess
import logging
from pathlib import Path
from typing import List, Optional, Tuple
import tempfile
import shutil

from ..models.installation import ValidationResult, ValidationStatus


class ScriptValidator:
    """Validates shell scripts using various linters and checks."""
    
    def __init__(self):
        """Initialize the script validator."""
        self.logger = logging.getLogger(__name__)
        self._check_dependencies()
    
    def _check_dependencies(self):
        """Check if required tools are available."""
        required_tools = {
            'shellcheck': 'Install with: apt-get install shellcheck',
            'bash': 'Bash shell required'
        }
        
        for tool, install_msg in required_tools.items():
            if not shutil.which(tool):
                self.logger.warning(f"{tool} not found. {install_msg}")
    
    def validate_script(self, script_path: Path) -> List[ValidationResult]:
        """
        Run all validation checks on a script.
        
        Args:
            script_path: Path to the script file
            
        Returns:
            List of validation results
        """
        results = []
        
        # Check file exists and is readable
        if not script_path.exists():
            results.append(ValidationResult(
                step="file_check",
                status=ValidationStatus.FAILED,
                error=f"Script file not found: {script_path}"
            ))
            return results
        
        # Run validation steps
        results.append(self._validate_shebang(script_path))
        results.append(self._validate_safety_flags(script_path))
        results.append(self._validate_bash_syntax(script_path))
        results.append(self._validate_shellcheck(script_path))
        results.append(self._validate_idempotency_pattern(script_path))
        results.append(self._validate_no_secrets(script_path))
        
        return results
    
    def _validate_shebang(self, script_path: Path) -> ValidationResult:
        """Validate script has proper shebang."""
        try:
            with open(script_path, 'r') as f:
                first_line = f.readline().strip()
            
            if first_line == "#!/usr/bin/env bash":
                return ValidationResult(
                    step="shebang_check",
                    status=ValidationStatus.PASSED,
                    output="Correct shebang found"
                )
            else:
                return ValidationResult(
                    step="shebang_check",
                    status=ValidationStatus.FAILED,
                    error=f"Invalid shebang: {first_line}"
                )
        except Exception as e:
            return ValidationResult(
                step="shebang_check",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _validate_safety_flags(self, script_path: Path) -> ValidationResult:
        """Validate script has safety flags set."""
        try:
            with open(script_path, 'r') as f:
                content = f.read()
            
            if "set -euo pipefail" in content:
                return ValidationResult(
                    step="safety_flags",
                    status=ValidationStatus.PASSED,
                    output="Safety flags present"
                )
            else:
                return ValidationResult(
                    step="safety_flags",
                    status=ValidationStatus.FAILED,
                    error="Missing 'set -euo pipefail'"
                )
        except Exception as e:
            return ValidationResult(
                step="safety_flags",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _validate_bash_syntax(self, script_path: Path) -> ValidationResult:
        """Validate bash syntax using bash -n."""
        try:
            result = subprocess.run(
                ['bash', '-n', str(script_path)],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                return ValidationResult(
                    step="bash_syntax",
                    status=ValidationStatus.PASSED,
                    output="Syntax check passed"
                )
            else:
                return ValidationResult(
                    step="bash_syntax",
                    status=ValidationStatus.FAILED,
                    error=result.stderr or "Syntax error"
                )
        except subprocess.TimeoutExpired:
            return ValidationResult(
                step="bash_syntax",
                status=ValidationStatus.FAILED,
                error="Syntax check timed out"
            )
        except Exception as e:
            return ValidationResult(
                step="bash_syntax",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _validate_shellcheck(self, script_path: Path) -> ValidationResult:
        """Validate script using shellcheck."""
        if not shutil.which('shellcheck'):
            return ValidationResult(
                step="shellcheck",
                status=ValidationStatus.SKIPPED,
                output="shellcheck not available"
            )
        
        try:
            result = subprocess.run(
                ['shellcheck', '-x', '-f', 'gcc', str(script_path)],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return ValidationResult(
                    step="shellcheck",
                    status=ValidationStatus.PASSED,
                    output="No issues found"
                )
            else:
                # Parse shellcheck output
                issues = []
                for line in result.stdout.splitlines():
                    if line.strip():
                        issues.append(line)
                
                # Check if all issues are warnings/info (not errors)
                error_count = sum(1 for line in issues if ":error:" in line)
                
                if error_count == 0:
                    return ValidationResult(
                        step="shellcheck",
                        status=ValidationStatus.PASSED,
                        output=f"Warnings only: {len(issues)} issues"
                    )
                else:
                    return ValidationResult(
                        step="shellcheck",
                        status=ValidationStatus.FAILED,
                        error=f"{error_count} errors found",
                        output="\n".join(issues[:10])  # First 10 issues
                    )
        except subprocess.TimeoutExpired:
            return ValidationResult(
                step="shellcheck",
                status=ValidationStatus.FAILED,
                error="shellcheck timed out"
            )
        except Exception as e:
            return ValidationResult(
                step="shellcheck",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _validate_idempotency_pattern(self, script_path: Path) -> ValidationResult:
        """Check for idempotency patterns in the script."""
        try:
            with open(script_path, 'r') as f:
                content = f.read()
            
            # Look for common idempotency patterns
            patterns = [
                "if.*command -v",  # Checking if command exists
                "if.*test -f",     # Checking if file exists
                "if.*\\[.*-f",     # Alternative file check
                "dpkg -l.*grep",   # Checking if package installed
                "which",           # Command existence check
                "command -v",      # Command existence check
            ]
            
            import re
            found_patterns = []
            for pattern in patterns:
                if re.search(pattern, content, re.IGNORECASE):
                    found_patterns.append(pattern)
            
            if found_patterns:
                return ValidationResult(
                    step="idempotency_check",
                    status=ValidationStatus.PASSED,
                    output=f"Found idempotency patterns: {', '.join(found_patterns)}"
                )
            else:
                return ValidationResult(
                    step="idempotency_check",
                    status=ValidationStatus.FAILED,
                    error="No idempotency patterns found",
                    output="Script should check if tool is already installed"
                )
        except Exception as e:
            return ValidationResult(
                step="idempotency_check",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
    
    def _validate_no_secrets(self, script_path: Path) -> ValidationResult:
        """Check for potential secrets in the script."""
        try:
            with open(script_path, 'r') as f:
                content = f.read()
            
            # Patterns that might indicate secrets
            secret_patterns = [
                r'(api[_-]?key|apikey|secret[_-]?key|password|passwd|pwd)\s*=\s*["\']?[^"\'\s]+',
                r'(token|auth[_-]?token|access[_-]?token)\s*=\s*["\']?[^"\'\s]+',
                r'-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----',
                r'[a-zA-Z0-9+/]{40,}={0,2}',  # Base64 encoded strings
            ]
            
            import re
            found_secrets = []
            for pattern in secret_patterns:
                matches = re.findall(pattern, content, re.IGNORECASE)
                if matches:
                    found_secrets.extend(matches)
            
            if found_secrets:
                return ValidationResult(
                    step="secrets_check",
                    status=ValidationStatus.FAILED,
                    error="Potential secrets found",
                    output=f"Found {len(found_secrets)} potential secrets"
                )
            else:
                return ValidationResult(
                    step="secrets_check",
                    status=ValidationStatus.PASSED,
                    output="No secrets detected"
                )
        except Exception as e:
            return ValidationResult(
                step="secrets_check",
                status=ValidationStatus.FAILED,
                error=str(e)
            )
