"""
GitHub Repository Analyzer for determining installation methods.
"""

import re
import json
import logging
from typing import Dict, Any, Optional, List, Tuple
from dataclasses import dataclass, field
from enum import Enum
import urllib.request
import urllib.error
from pathlib import Path
import os


class InstallMethod(Enum):
    """Supported installation methods."""
    PIP = "pip"
    NPM = "npm"
    GO_INSTALL = "go_install"
    CARGO = "cargo"
    GEM = "gem"
    BINARY_RELEASE = "binary_release"
    DOCKER = "docker"
    DOCKER_COMPOSE = "docker_compose"
    HELM = "helm"
    MAKE = "make"
    SCRIPT = "script"
    UNKNOWN = "unknown"


@dataclass
class RepoAnalysis:
    """Result of repository analysis."""
    repo_name: str
    repo_owner: str
    description: str = ""
    primary_language: str = ""
    topics: List[str] = field(default_factory=list)
    has_releases: bool = False
    latest_version: Optional[str] = None
    install_methods: List[InstallMethod] = field(default_factory=list)
    docker_image: Optional[str] = None
    package_name: Optional[str] = None
    binary_pattern: Optional[str] = None
    validation_command: Optional[str] = None
    dependencies: List[str] = field(default_factory=list)
    installation_docs: Optional[str] = None


class GitHubAnalyzer:
    """Analyzes GitHub repositories to determine installation methods."""
    
    def __init__(self, github_token: Optional[str] = None):
        self.logger = logging.getLogger(__name__)
        self.github_token = github_token or os.environ.get('GITHUB_TOKEN')
        
        if self.github_token:
            self.logger.info("Using GitHub authentication (rate limit: 5000/hour)")
        else:
            self.logger.warning("No GitHub token found. Using unauthenticated requests (rate limit: 60/hour)")
            self.logger.info("Set GITHUB_TOKEN environment variable to increase rate limit")
        
    def analyze_repository(self, github_url: str) -> RepoAnalysis:
        """
        Analyze a GitHub repository to determine installation methods.
        
        Args:
            github_url: GitHub repository URL
            
        Returns:
            RepoAnalysis object with detected information
        """
        # Parse GitHub URL
        owner, repo = self._parse_github_url(github_url)
        if not owner or not repo:
            raise ValueError(f"Invalid GitHub URL: {github_url}")
            
        analysis = RepoAnalysis(repo_name=repo, repo_owner=owner)
        
        # Fetch repository metadata
        try:
            repo_data = self._fetch_repo_data(owner, repo)
            analysis.description = repo_data.get("description", "")
            analysis.primary_language = repo_data.get("language", "")
            analysis.topics = repo_data.get("topics", [])
        except Exception as e:
            self.logger.warning(f"Failed to fetch repo metadata: {e}")
        
        # Check for releases
        try:
            releases = self._fetch_releases(owner, repo)
            if releases:
                analysis.has_releases = True
                analysis.latest_version = releases[0].get("tag_name", "")
                # Check for binary assets
                if self._has_binary_releases(releases[0]):
                    analysis.install_methods.append(InstallMethod.BINARY_RELEASE)
                    analysis.binary_pattern = self._detect_binary_pattern(releases[0])
        except Exception as e:
            self.logger.warning(f"Failed to fetch releases: {e}")
        
        # Detect installation methods from repository structure
        self._detect_installation_methods(owner, repo, analysis)
        
        # Detect package names and validation commands
        self._detect_package_info(owner, repo, analysis)
        
        return analysis
    
    def _parse_github_url(self, url: str) -> Tuple[Optional[str], Optional[str]]:
        """Parse GitHub URL to extract owner and repo name."""
        # Handle various GitHub URL formats
        patterns = [
            r"github\.com[/:]([^/]+)/([^/\.]+)",
            r"^([^/]+)/([^/]+)$"
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1), match.group(2).rstrip('.git')
        
        return None, None
    
    def _fetch_repo_data(self, owner: str, repo: str) -> Dict[str, Any]:
        """Fetch repository metadata from GitHub API."""
        url = f"https://api.github.com/repos/{owner}/{repo}"
        return self._fetch_json(url)
    
    def _fetch_releases(self, owner: str, repo: str) -> List[Dict[str, Any]]:
        """Fetch releases from GitHub API."""
        url = f"https://api.github.com/repos/{owner}/{repo}/releases"
        return self._fetch_json(url)
    
    def _fetch_file_content(self, owner: str, repo: str, path: str) -> Optional[str]:
        """Fetch raw file content from GitHub."""
        url = f"https://raw.githubusercontent.com/{owner}/{repo}/main/{path}"
        try:
            with urllib.request.urlopen(url) as response:
                return response.read().decode('utf-8')
        except:
            # Try master branch
            url = f"https://raw.githubusercontent.com/{owner}/{repo}/master/{path}"
            try:
                with urllib.request.urlopen(url) as response:
                    return response.read().decode('utf-8')
            except:
                return None
    
    def _fetch_json(self, url: str) -> Any:
        """Fetch JSON data from URL."""
        headers = {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'ToolInstallationBot/1.0'
        }
        
        # Add authentication header if token is available
        if self.github_token:
            headers['Authorization'] = f'token {self.github_token}'
        
        req = urllib.request.Request(url, headers=headers)
        
        try:
            with urllib.request.urlopen(req) as response:
                # Log rate limit info if available
                if 'X-RateLimit-Remaining' in response.headers:
                    remaining = response.headers['X-RateLimit-Remaining']
                    limit = response.headers.get('X-RateLimit-Limit', 'unknown')
                    self.logger.debug(f"GitHub API rate limit: {remaining}/{limit} remaining")
                
                return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            if e.code == 403 and 'rate limit' in str(e.reason).lower():
                self.logger.error("GitHub API rate limit exceeded! Consider setting GITHUB_TOKEN environment variable.")
            raise
    
    def _has_binary_releases(self, release: Dict[str, Any]) -> bool:
        """Check if release has binary assets."""
        assets = release.get("assets", [])
        binary_extensions = ['.tar.gz', '.zip', '.exe', '.dmg', '.deb', '.rpm', '.AppImage']
        
        for asset in assets:
            name = asset.get("name", "").lower()
            if any(name.endswith(ext) for ext in binary_extensions):
                return True
        return False
    
    def _detect_binary_pattern(self, release: Dict[str, Any]) -> Optional[str]:
        """Detect pattern for binary download URLs."""
        assets = release.get("assets", [])
        for asset in assets:
            name = asset.get("name", "").lower()
            if 'linux' in name and ('amd64' in name or 'x86_64' in name):
                return asset.get("name")
        return None
    
    def _detect_installation_methods(self, owner: str, repo: str, analysis: RepoAnalysis):
        """Detect installation methods from repository structure."""
        # Check for package files
        file_checks = {
            "setup.py": InstallMethod.PIP,
            "pyproject.toml": InstallMethod.PIP,
            "package.json": InstallMethod.NPM,
            "go.mod": InstallMethod.GO_INSTALL,
            "Cargo.toml": InstallMethod.CARGO,
            "Gemfile": InstallMethod.GEM,
            "Dockerfile": InstallMethod.DOCKER,
            "docker-compose.yml": InstallMethod.DOCKER_COMPOSE,
            "docker-compose.yaml": InstallMethod.DOCKER_COMPOSE,
            "Chart.yaml": InstallMethod.HELM,
            "Makefile": InstallMethod.MAKE,
            "install.sh": InstallMethod.SCRIPT,
        }
        
        for file_path, method in file_checks.items():
            content = self._fetch_file_content(owner, repo, file_path)
            if content:
                if method not in analysis.install_methods:
                    analysis.install_methods.append(method)
                    
                # Extract additional info from files
                if method == InstallMethod.PIP and file_path == "setup.py":
                    analysis.package_name = self._extract_python_package_name(content)
                elif method == InstallMethod.NPM and file_path == "package.json":
                    analysis.package_name = self._extract_npm_package_name(content)
                elif method == InstallMethod.DOCKER:
                    analysis.docker_image = f"{owner}/{repo}"
        
        # Check if Go module can be installed
        if analysis.primary_language == "Go" and InstallMethod.GO_INSTALL not in analysis.install_methods:
            # Check if it has main.go or cmd directory
            if self._fetch_file_content(owner, repo, "main.go") or self._fetch_file_content(owner, repo, "cmd"):
                analysis.install_methods.append(InstallMethod.GO_INSTALL)
    
    def _extract_python_package_name(self, setup_content: str) -> Optional[str]:
        """Extract package name from setup.py."""
        match = re.search(r'name\s*=\s*["\']([^"\']+)["\']', setup_content)
        return match.group(1) if match else None
    
    def _extract_npm_package_name(self, package_json: str) -> Optional[str]:
        """Extract package name from package.json."""
        try:
            data = json.loads(package_json)
            return data.get("name")
        except:
            return None
    
    def _detect_package_info(self, owner: str, repo: str, analysis: RepoAnalysis):
        """Detect package-specific information."""
        # Set default package names if not detected
        if not analysis.package_name:
            if InstallMethod.PIP in analysis.install_methods:
                # Common Python packages
                analysis.package_name = repo.lower().replace('_', '-')
            elif InstallMethod.NPM in analysis.install_methods:
                analysis.package_name = repo.lower()
            elif InstallMethod.GO_INSTALL in analysis.install_methods:
                analysis.package_name = f"github.com/{owner}/{repo}"
        
        # Detect validation commands based on package type
        if InstallMethod.PIP in analysis.install_methods:
            pkg = analysis.package_name or repo
            analysis.validation_command = f"python -c 'import {pkg.replace('-', '_')}; print({pkg.replace('-', '_')}.__version__)'"
        elif InstallMethod.NPM in analysis.install_methods:
            pkg = analysis.package_name or repo
            analysis.validation_command = f"npm list -g {pkg}"
        elif InstallMethod.GO_INSTALL in analysis.install_methods:
            analysis.validation_command = f"{repo} --version || {repo} version"
        elif InstallMethod.BINARY_RELEASE in analysis.install_methods:
            analysis.validation_command = f"{repo} --version || {repo} version"
        elif InstallMethod.DOCKER in analysis.install_methods:
            analysis.validation_command = f"docker images {analysis.docker_image}"
        
        # Try to find installation docs
        for doc_file in ["README.md", "INSTALL.md", "docs/installation.md"]:
            content = self._fetch_file_content(owner, repo, doc_file)
            if content:
                analysis.installation_docs = self._extract_installation_section(content)
                break
    
    def _extract_installation_section(self, markdown: str) -> Optional[str]:
        """Extract installation section from markdown."""
        # Look for installation headers
        patterns = [
            r'#+\s*Installation(.*?)(?=\n#|\Z)',
            r'#+\s*Install(.*?)(?=\n#|\Z)',
            r'#+\s*Getting Started(.*?)(?=\n#|\Z)'
        ]
        
        for pattern in patterns:
            match = re.search(pattern, markdown, re.IGNORECASE | re.DOTALL)
            if match:
                return match.group(0)[:1000]  # First 1000 chars
        
        return None
