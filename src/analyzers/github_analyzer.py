"""
GitHub Repository Analyzer - Simplified version.
Fetches only basic metadata; Claude handles all installation analysis.
"""

import re
import json
import logging
from typing import Optional, Tuple
from dataclasses import dataclass
import urllib.request
import urllib.error
import os


@dataclass
class RepoBasicInfo:
    """Basic repository information."""
    repo_name: str
    repo_owner: str
    description: str = ""
    github_url: str = ""
    latest_version: Optional[str] = None
    has_releases: bool = False


class GitHubAnalyzer:
    """
    Simplified GitHub analyzer that fetches only basic metadata.
    Claude Agent handles all installation method detection and analysis.
    """
    
    def __init__(self, github_token: Optional[str] = None):
        self.logger = logging.getLogger(__name__)
        self.github_token = github_token or os.environ.get('GITHUB_TOKEN')
        
        if self.github_token:
            self.logger.info("Using GitHub authentication (rate limit: 5000/hour)")
        else:
            self.logger.warning("No GitHub token found. Using unauthenticated requests (rate limit: 60/hour)")
            self.logger.info("Set GITHUB_TOKEN environment variable to increase rate limit")
        
    def get_basic_info(self, github_url: str) -> RepoBasicInfo:
        """
        Fetch basic repository information.
        
        Args:
            github_url: GitHub repository URL
            
        Returns:
            RepoBasicInfo with name, description, and latest release
        """
        # Parse GitHub URL
        owner, repo = self._parse_github_url(github_url)
        if not owner or not repo:
            raise ValueError(f"Invalid GitHub URL: {github_url}")
            
        info = RepoBasicInfo(
            repo_name=repo,
            repo_owner=owner,
            github_url=github_url
        )
        
        # Fetch repository metadata
        try:
            repo_data = self._fetch_repo_data(owner, repo)
            info.description = repo_data.get("description", "")
        except Exception as e:
            self.logger.warning(f"Failed to fetch repo metadata: {e}")
            info.description = f"Repository {owner}/{repo}"
        
        # Check for releases
        try:
            releases = self._fetch_releases(owner, repo)
            if releases:
                info.has_releases = True
                latest = releases[0]
                info.latest_version = latest.get("tag_name", "latest")
                self.logger.info(f"Latest release: {info.latest_version}")
            else:
                info.latest_version = "latest"
        except Exception as e:
            self.logger.warning(f"Failed to fetch releases: {e}")
            info.latest_version = "latest"
        
        return info
    
    def _parse_github_url(self, url: str) -> Tuple[Optional[str], Optional[str]]:
        """Parse owner and repo from GitHub URL."""
        patterns = [
            r'github\.com[/:]([^/]+)/([^/\.]+)',
            r'github\.com/([^/]+)/([^/]+)\.git'
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1), match.group(2)
        
        return None, None
    
    def _fetch_repo_data(self, owner: str, repo: str) -> dict:
        """Fetch repository data from GitHub API."""
        url = f"https://api.github.com/repos/{owner}/{repo}"
        
        request = urllib.request.Request(url)
        if self.github_token:
            request.add_header("Authorization", f"token {self.github_token}")
        request.add_header("Accept", "application/vnd.github.v3+json")
        
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise ValueError(f"Repository not found: {owner}/{repo}")
            elif e.code == 403:
                raise ValueError(f"GitHub API rate limit exceeded. Set GITHUB_TOKEN to increase limit.")
            else:
                raise ValueError(f"GitHub API error: {e.code}")
    
    def _fetch_releases(self, owner: str, repo: str) -> list:
        """Fetch releases from GitHub API."""
        url = f"https://api.github.com/repos/{owner}/{repo}/releases"
        
        request = urllib.request.Request(url)
        if self.github_token:
            request.add_header("Authorization", f"token {self.github_token}")
        request.add_header("Accept", "application/vnd.github.v3+json")
        
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                releases = json.loads(response.read().decode())
                return releases if isinstance(releases, list) else []
        except Exception as e:
            self.logger.debug(f"Failed to fetch releases: {e}")
            return []