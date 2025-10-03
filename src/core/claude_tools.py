"""
Tool definitions for Claude Agent to perform autonomous installations.
"""

from claude_agent_sdk import tool, create_sdk_mcp_server
from pathlib import Path
import subprocess
import asyncio
import json
import hashlib
import tempfile
import shutil
from typing import Dict, Any, Optional
import os


@tool("generate_script", "Generate installation script for a tool", {
    "tool_name": str,
    "tool_version": str,
    "validate_cmd": str,
    "package_manager": str,
    "repository_url": str,
    "install_standards": str,
    "base_dockerfile": str
})
async def generate_script(args):
    """Generate an installation script based on specifications."""
    tool_name = args["tool_name"]
    tool_version = args["tool_version"]
    
    # This will be handled by Claude's reasoning
    # Claude will generate the script content based on the standards
    return {
        "content": [{
            "type": "text",
            "text": "Script generation will be handled by Claude's reasoning"
        }]
    }


@tool("write_script", "Write installation script to file", {
    "filename": str,
    "content": str
})
async def write_script(args):
    """Write the generated script to a file."""
    try:
        path = Path(args["filename"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(args["content"])
        path.chmod(0o755)
        
        # Calculate checksum
        checksum = hashlib.sha256(args["content"].encode()).hexdigest()
        
        return {
            "content": [{
                "type": "text",
                "text": f"Script written to {path}\nChecksum: {checksum}"
            }]
        }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error writing script: {str(e)}"
            }],
            "is_error": True
        }


@tool("run_shellcheck", "Run shellcheck on a script", {"script_path": str})
async def run_shellcheck(args):
    """Run shellcheck validation on a script."""
    script_path = args["script_path"]
    
    # Check if shellcheck is available
    if not shutil.which('shellcheck'):
        return {
            "content": [{
                "type": "text",
                "text": "shellcheck not available, skipping validation"
            }]
        }
    
    try:
        result = await asyncio.create_subprocess_exec(
            'shellcheck', '-x', script_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await result.communicate()
        
        if result.returncode == 0:
            return {
                "content": [{
                    "type": "text",
                    "text": "✓ Shellcheck passed - no issues found"
                }]
            }
        else:
            return {
                "content": [{
                    "type": "text",
                    "text": f"Shellcheck issues found:\n{stdout.decode()}\n{stderr.decode()}"
                }]
            }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error running shellcheck: {str(e)}"
            }],
            "is_error": True
        }


@tool("run_bash_syntax_check", "Check bash syntax", {"script_path": str})
async def run_bash_syntax_check(args):
    """Check bash syntax with bash -n."""
    script_path = args["script_path"]
    
    try:
        result = await asyncio.create_subprocess_exec(
            'bash', '-n', script_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await result.communicate()
        
        if result.returncode == 0:
            return {
                "content": [{
                    "type": "text",
                    "text": "✓ Bash syntax check passed"
                }]
            }
        else:
            return {
                "content": [{
                    "type": "text",
                    "text": f"Bash syntax errors:\n{stderr.decode()}"
                }],
                "is_error": True
            }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error checking syntax: {str(e)}"
            }],
            "is_error": True
        }


@tool("build_docker_image", "Build Docker image for testing", {
    "dockerfile_content": str,
    "image_tag": str,
    "build_context": str
})
async def build_docker_image(args):
    """Build a Docker image for testing the installation."""
    try:
        # Create temporary directory for Docker context
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            
            # Write Dockerfile
            dockerfile_path = temp_path / "Dockerfile"
            dockerfile_path.write_text(args["dockerfile_content"])
            
            # Copy any files from build context
            if args.get("build_context"):
                context_path = Path(args["build_context"])
                if context_path.exists():
                    for file in context_path.glob("*"):
                        shutil.copy2(file, temp_path / file.name)
            
            # Build image
            cmd = ['docker', 'build', '--no-cache', '-t', args["image_tag"], str(temp_path)]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT
            )
            
            stdout, _ = await result.communicate()
            output = stdout.decode()
            
            if result.returncode == 0:
                return {
                    "content": [{
                        "type": "text",
                        "text": f"✓ Docker image built successfully: {args['image_tag']}\n{output[-500:]}"
                    }]
                }
            else:
                return {
                    "content": [{
                        "type": "text",
                        "text": f"Docker build failed:\n{output}"
                    }],
                    "is_error": True
                }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error building Docker image: {str(e)}"
            }],
            "is_error": True
        }


@tool("run_docker_container", "Run Docker container for validation", {
    "image_tag": str,
    "command": str,
    "timeout": int
})
async def run_docker_container(args):
    """Run a Docker container to validate the installation."""
    try:
        cmd = [
            'docker', 'run', '--rm',
            args["image_tag"],
            'bash', '-c', args["command"]
        ]
        
        # Create subprocess with timeout
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=args.get("timeout", 60)
            )
            
            output = f"STDOUT:\n{stdout.decode()}\nSTDERR:\n{stderr.decode()}"
            
            if process.returncode == 0:
                return {
                    "content": [{
                        "type": "text",
                        "text": f"✓ Container ran successfully\n{output}"
                    }]
                }
            else:
                return {
                    "content": [{
                        "type": "text",
                        "text": f"Container failed with exit code {process.returncode}\n{output}"
                    }],
                    "is_error": True
                }
                
        except asyncio.TimeoutError:
            process.terminate()
            await process.wait()
            return {
                "content": [{
                    "type": "text",
                    "text": f"Container execution timed out after {args.get('timeout', 60)} seconds"
                }],
                "is_error": True
            }
            
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error running container: {str(e)}"
            }],
            "is_error": True
        }


@tool("cleanup_docker", "Clean up Docker resources", {
    "image_tag": str,
    "remove_image": bool
})
async def cleanup_docker(args):
    """Clean up Docker resources after testing."""
    try:
        cleanup_log = []
        
        # Remove containers using this image
        list_cmd = ['docker', 'ps', '-a', '-q', '--filter', f'ancestor={args["image_tag"]}']
        result = await asyncio.create_subprocess_exec(
            *list_cmd,
            stdout=asyncio.subprocess.PIPE
        )
        stdout, _ = await result.communicate()
        
        if stdout:
            container_ids = stdout.decode().strip().split('\n')
            for container_id in container_ids:
                if container_id:
                    rm_result = await asyncio.create_subprocess_exec(
                        'docker', 'rm', '-f', container_id
                    )
                    await rm_result.wait()
                    cleanup_log.append(f"Removed container: {container_id}")
        
        # Remove image if requested
        if args.get("remove_image", True):
            rmi_result = await asyncio.create_subprocess_exec(
                'docker', 'rmi', args["image_tag"],
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await rmi_result.wait()
            
            if rmi_result.returncode == 0:
                cleanup_log.append(f"Removed image: {args['image_tag']}")
            else:
                cleanup_log.append(f"Failed to remove image: {args['image_tag']}")
        
        return {
            "content": [{
                "type": "text",
                "text": "Docker cleanup completed:\n" + "\n".join(cleanup_log)
            }]
        }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error during cleanup: {str(e)}"
            }]
        }


@tool("save_artifacts", "Save only the necessary artifacts", {
    "tool_name": str,
    "tool_version": str,
    "script_path": str,
    "validation_results": str,
    "artifacts_dir": str
})
async def save_artifacts(args):
    """Save only the tool_setup.sh and essential metadata."""
    try:
        # Create artifact directory
        artifact_path = Path(args["artifacts_dir"]) / args["tool_name"] / args["tool_version"]
        artifact_path.mkdir(parents=True, exist_ok=True)
        
        # Copy the script
        script_source = Path(args["script_path"])
        script_dest = artifact_path / "tool_setup.sh"
        shutil.copy2(script_source, script_dest)
        script_dest.chmod(0o755)
        
        # Save validation results as JSON
        results_path = artifact_path / "validation_results.json"
        results_path.write_text(args["validation_results"])
        
        # Clean up temporary files
        if script_source.parent != artifact_path:
            script_source.unlink()
        
        return {
            "content": [{
                "type": "text",
                "text": f"✓ Artifacts saved to {artifact_path}\n- tool_setup.sh\n- validation_results.json"
            }]
        }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error saving artifacts: {str(e)}"
            }],
            "is_error": True
        }


@tool("cleanup_temp_files", "Clean up temporary files", {"paths": list})
async def cleanup_temp_files(args):
    """Clean up temporary files created during the process."""
    cleaned = []
    errors = []
    
    for path_str in args.get("paths", []):
        try:
            path = Path(path_str)
            if path.exists():
                if path.is_file():
                    path.unlink()
                    cleaned.append(f"Removed file: {path}")
                elif path.is_dir():
                    shutil.rmtree(path)
                    cleaned.append(f"Removed directory: {path}")
        except Exception as e:
            errors.append(f"Error removing {path_str}: {str(e)}")
    
    message = "Cleanup completed:\n" + "\n".join(cleaned)
    if errors:
        message += "\n\nErrors:\n" + "\n".join(errors)
    
    return {
        "content": [{
            "type": "text",
            "text": message
        }]
    }


@tool("bash", "Execute bash commands", {"command": str, "cwd": str})
async def bash(args):
    """Execute bash commands."""
    try:
        command = args["command"]
        cwd = args.get("cwd", os.getcwd())
        
        result = await asyncio.create_subprocess_shell(
            command,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            shell=True
        )
        
        stdout, stderr = await result.communicate()
        output = stdout.decode() + (stderr.decode() if stderr else "")
        
        return {
            "content": [{
                "type": "text",
                "text": f"Command output:\n{output}"
            }],
            "is_error": result.returncode != 0
        }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error executing command: {str(e)}"
            }],
            "is_error": True
        }


@tool("write", "Write content to a file", {"path": str, "content": str})
async def write(args):
    """Write content to a file."""
    try:
        path = Path(args["path"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(args["content"])
        
        if path.suffix == ".sh":
            path.chmod(0o755)
        
        return {
            "content": [{
                "type": "text",
                "text": f"Successfully wrote to {path}"
            }]
        }
    except Exception as e:
        return {
            "content": [{
                "type": "text",
                "text": f"Error writing file: {str(e)}"
            }],
            "is_error": True
        }


def get_claude_tools():
    """Get the tool server for Claude agent."""
    return create_sdk_mcp_server(
        name="installation_tools",
        version="1.0.0",
        tools=[
            generate_script,
            write_script,
            write,  # Added general write tool
            bash,   # Added bash tool
            run_shellcheck,
            run_bash_syntax_check,
            build_docker_image,
            run_docker_container,
            cleanup_docker,
            save_artifacts,
            cleanup_temp_files
        ]
    )
