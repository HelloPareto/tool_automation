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
import subprocess
import tempfile
import shutil


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
    
    def __init__(self, github_token: Optional[str] = None, enable_cloning: bool = True):
        self.logger = logging.getLogger(__name__)
        self.github_token = github_token or os.environ.get('GITHUB_TOKEN')
        self.enable_cloning = enable_cloning
        
        if self.github_token:
            self.logger.info("Using GitHub authentication (rate limit: 5000/hour)")
        else:
            self.logger.warning("No GitHub token found. Using unauthenticated requests (rate limit: 60/hour)")
            self.logger.info("Set GITHUB_TOKEN environment variable to increase rate limit")
        
    def analyze_repository(self, github_url: str) -> RepoAnalysis:
        """
        Analyze a GitHub repository to determine installation methods.
        Uses GitHub API first, then falls back to cloning if needed.
        
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
        api_fetch_failed = False
        
        # Fetch repository metadata
        try:
            repo_data = self._fetch_repo_data(owner, repo)
            analysis.description = repo_data.get("description", "")
            analysis.primary_language = repo_data.get("language", "")
            analysis.topics = repo_data.get("topics", [])
        except Exception as e:
            self.logger.warning(f"Failed to fetch repo metadata via API: {e}")
            api_fetch_failed = True
        
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
        
        # Detect installation methods from repository structure (API-based)
        try:
            self._detect_installation_methods(owner, repo, analysis)
        except Exception as e:
            self.logger.warning(f"Failed to detect installation methods via API: {e}")
            api_fetch_failed = True
        
        # If API analysis failed or found nothing, try cloning
        needs_cloning = (
            api_fetch_failed or
            not analysis.install_methods or
            not analysis.installation_docs
        )
        
        if needs_cloning and self.enable_cloning:
            self.logger.info(f"API analysis insufficient for {owner}/{repo}, cloning repository for deeper analysis")
            try:
                self._analyze_cloned_repository(github_url, analysis)
            except Exception as e:
                self.logger.error(f"Failed to clone and analyze repository: {e}")
        
        # Detect package names and validation commands
        self._detect_package_info(owner, repo, analysis)
        
        # If still no install methods found, mark as unknown
        if not analysis.install_methods:
            analysis.install_methods.append(InstallMethod.UNKNOWN)
            self.logger.warning(f"Could not determine installation method for {owner}/{repo}")
        
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
    
    # ==================== Repository Cloning Methods ====================
    
    def _analyze_cloned_repository(self, github_url: str, analysis: RepoAnalysis):
        """
        Clone repository and analyze it locally for deeper insights.
        This is a fallback when API-based analysis is insufficient.
        """
        temp_dir = None
        try:
            # Create temporary directory
            temp_dir = tempfile.mkdtemp(prefix="gh_analyze_")
            self.logger.info(f"Cloning {github_url} to {temp_dir}")
            
            # Clone repository (shallow clone for speed)
            self._clone_repository(github_url, temp_dir)
            
            # Analyze local repository
            repo_path = Path(temp_dir) / analysis.repo_name
            
            if not repo_path.exists():
                # Repository might be cloned directly to temp_dir
                repo_path = Path(temp_dir)
            
            self.logger.info(f"Analyzing cloned repository at {repo_path}")
            
            # Detect installation files
            self._detect_installation_files_local(repo_path, analysis)
            
            # Extract documentation
            self._extract_documentation_local(repo_path, analysis)
            
            # Analyze project structure
            self._analyze_project_structure(repo_path, analysis)
            
            self.logger.info(f"Completed local analysis of {github_url}")
            
        finally:
            # Clean up temporary directory
            if temp_dir and os.path.exists(temp_dir):
                try:
                    shutil.rmtree(temp_dir)
                    self.logger.debug(f"Cleaned up temporary directory: {temp_dir}")
                except Exception as e:
                    self.logger.warning(f"Failed to clean up temporary directory {temp_dir}: {e}")
    
    def _clone_repository(self, github_url: str, target_dir: str):
        """Clone a GitHub repository."""
        try:
            # Use shallow clone for speed
            cmd = [
                "git", "clone",
                "--depth", "1",
                "--single-branch",
                github_url,
                target_dir
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            
            if result.returncode != 0:
                raise RuntimeError(f"Git clone failed: {result.stderr}")
                
            self.logger.debug(f"Successfully cloned {github_url}")
            
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"Git clone timed out after 5 minutes")
        except FileNotFoundError:
            raise RuntimeError("git command not found. Please install git.")
    
    def _detect_installation_files_local(self, repo_path: Path, analysis: RepoAnalysis):
        """Detect installation methods from local repository files."""
        
        # Define file checks with their associated install methods
        file_checks = {
            "setup.py": InstallMethod.PIP,
            "pyproject.toml": InstallMethod.PIP,
            "requirements.txt": InstallMethod.PIP,
            "package.json": InstallMethod.NPM,
            "yarn.lock": InstallMethod.NPM,
            "go.mod": InstallMethod.GO_INSTALL,
            "go.sum": InstallMethod.GO_INSTALL,
            "Cargo.toml": InstallMethod.CARGO,
            "Cargo.lock": InstallMethod.CARGO,
            "Gemfile": InstallMethod.GEM,
            "Dockerfile": InstallMethod.DOCKER,
            "docker-compose.yml": InstallMethod.DOCKER_COMPOSE,
            "docker-compose.yaml": InstallMethod.DOCKER_COMPOSE,
            "Chart.yaml": InstallMethod.HELM,
            "Makefile": InstallMethod.MAKE,
            "install.sh": InstallMethod.SCRIPT,
            "setup.sh": InstallMethod.SCRIPT,
        }
        
        found_files = []
        
        for filename, method in file_checks.items():
            file_path = repo_path / filename
            if file_path.exists():
                found_files.append(filename)
                if method not in analysis.install_methods:
                    analysis.install_methods.append(method)
                    self.logger.info(f"Found {filename} - detected {method.value}")
                
                # Extract additional information
                try:
                    if method == InstallMethod.PIP and filename == "setup.py":
                        content = file_path.read_text(encoding='utf-8', errors='ignore')
                        pkg_name = self._extract_python_package_name(content)
                        if pkg_name:
                            analysis.package_name = pkg_name
                            
                    elif method == InstallMethod.NPM and filename == "package.json":
                        content = file_path.read_text(encoding='utf-8', errors='ignore')
                        pkg_name = self._extract_npm_package_name(content)
                        if pkg_name:
                            analysis.package_name = pkg_name
                            
                    elif method == InstallMethod.DOCKER:
                        analysis.docker_image = f"{analysis.repo_owner}/{analysis.repo_name}"
                        
                except Exception as e:
                    self.logger.warning(f"Error parsing {filename}: {e}")
        
        # Check for Go executables in cmd/ directory
        cmd_dir = repo_path / "cmd"
        if cmd_dir.exists() and cmd_dir.is_dir():
            if InstallMethod.GO_INSTALL not in analysis.install_methods:
                analysis.install_methods.append(InstallMethod.GO_INSTALL)
                self.logger.info(f"Found cmd/ directory - detected Go project")
        
        # Check for main.go
        if (repo_path / "main.go").exists():
            if InstallMethod.GO_INSTALL not in analysis.install_methods:
                analysis.install_methods.append(InstallMethod.GO_INSTALL)
                self.logger.info(f"Found main.go - detected Go executable")
        
        self.logger.info(f"Detected installation files: {', '.join(found_files) if found_files else 'none'}")
    
    def _extract_documentation_local(self, repo_path: Path, analysis: RepoAnalysis):
        """Extract installation documentation from local repository."""
        
        # Look for documentation files
        doc_files = [
            "README.md",
            "README.rst",
            "INSTALL.md",
            "INSTALLATION.md",
            "docs/README.md",
            "docs/installation.md",
            "docs/install.md",
            "docs/getting-started.md",
            "GETTING_STARTED.md",
        ]
        
        for doc_file in doc_files:
            doc_path = repo_path / doc_file
            if doc_path.exists():
                try:
                    content = doc_path.read_text(encoding='utf-8', errors='ignore')
                    install_section = self._extract_installation_section(content)
                    if install_section:
                        analysis.installation_docs = install_section
                        self.logger.info(f"Extracted installation docs from {doc_file}")
                        break
                except Exception as e:
                    self.logger.warning(f"Error reading {doc_file}: {e}")
        
        # If no installation section found, try to extract any relevant info
        if not analysis.installation_docs:
            readme_path = repo_path / "README.md"
            if readme_path.exists():
                try:
                    content = readme_path.read_text(encoding='utf-8', errors='ignore')
                    # Take first 2000 chars of README as fallback
                    analysis.installation_docs = content[:2000]
                    self.logger.info("Using README.md excerpt as installation docs")
                except Exception as e:
                    self.logger.warning(f"Error reading README.md: {e}")
    
    def _analyze_project_structure(self, repo_path: Path, analysis: RepoAnalysis):
        """Analyze project structure to infer additional information."""
        
        # Detect programming language from structure if not already set
        if not analysis.primary_language:
            # Python indicators
            if (repo_path / "setup.py").exists() or (repo_path / "__init__.py").exists():
                analysis.primary_language = "Python"
            # JavaScript/Node indicators
            elif (repo_path / "package.json").exists():
                analysis.primary_language = "JavaScript"
            # Go indicators
            elif (repo_path / "go.mod").exists() or (repo_path / "main.go").exists():
                analysis.primary_language = "Go"
            # Rust indicators
            elif (repo_path / "Cargo.toml").exists():
                analysis.primary_language = "Rust"
            # Ruby indicators
            elif (repo_path / "Gemfile").exists():
                analysis.primary_language = "Ruby"
        
        # Look for additional clues about dependencies
        self._detect_dependencies_local(repo_path, analysis)
    
    def _detect_dependencies_local(self, repo_path: Path, analysis: RepoAnalysis):
        """Detect dependencies from local repository files."""
        
        dependencies = []
        
        # Python requirements
        req_file = repo_path / "requirements.txt"
        if req_file.exists():
            try:
                content = req_file.read_text(encoding='utf-8', errors='ignore')
                # Extract package names (simplified)
                for line in content.split('\n'):
                    line = line.strip()
                    if line and not line.startswith('#'):
                        pkg = line.split('==')[0].split('>=')[0].split('<=')[0].strip()
                        if pkg:
                            dependencies.append(pkg)
            except Exception as e:
                self.logger.warning(f"Error parsing requirements.txt: {e}")
        
        # NPM dependencies
        package_json = repo_path / "package.json"
        if package_json.exists():
            try:
                content = package_json.read_text(encoding='utf-8', errors='ignore')
                data = json.loads(content)
                deps = data.get('dependencies', {})
                dependencies.extend(deps.keys())
            except Exception as e:
                self.logger.warning(f"Error parsing package.json: {e}")
        
        # Limit dependencies to first 20
        if dependencies:
            analysis.dependencies = dependencies[:20]
            self.logger.debug(f"Detected {len(dependencies)} dependencies")
