# Local Testing Guide

This guide explains how to test the AI agent locally without triggering the full Azure DevOps pipeline.

## Prerequisites

- Docker installed and running
- OpenCode authentication configured (`~/.local/share/opencode/auth.json`)
- Azure DevOps PAT (for fetching work items)

## The run-local.sh Script

The `scripts/run-local.sh` script mirrors the Azure DevOps pipeline logic exactly, allowing you to test locally.

### Two Execution Modes

#### 1. Pipeline Mode (Full Work Item Processing)

Fetches a work item from Azure DevOps and processes it exactly like the pipeline would:

```bash
# Analyze a work item
./scripts/run-local.sh --mode analyze --work-item-id 1373926

# Run a command
./scripts/run-local.sh --mode command --work-item-id 1373926 --command "explain this bug"

# Implement a work item
./scripts/run-local.sh --mode implement --work-item-id 1373926

# Dry-run (show what would be sent without running OpenCode)
./scripts/run-local.sh --mode analyze --work-item-id 1373926 --dry-run

# Use a local context file instead of fetching from ADO
./scripts/run-local.sh --mode analyze --context-file ./test-context.json --dry-run
```

**Required environment variables:**
```bash
export AZURE_DEVOPS_ORG="your-org"
export AZURE_DEVOPS_PROJECT="your-project"
export AZURE_DEVOPS_PAT="your-pat-or-token"
```

#### 2. Simple Mode (Quick Testing)

For quick testing with a simple prompt or interactive session:

```bash
# Run with a prompt
./scripts/run-local.sh "analyze this codebase"

# With a specific system configuration
./scripts/run-local.sh -s spectre "what does this system do?"

# Start interactive session
./scripts/run-local.sh --interactive
```

### All Options

| Option | Description |
|--------|-------------|
| `--mode <mode>` | Pipeline mode: `analyze`, `implement`, or `command` |
| `--work-item-id <id>` | Work item to process (fetches from ADO) |
| `--context-file <file>` | Use local JSON file instead of fetching |
| `--command <text>` | Command text (required for command mode) |
| `-s, --system <name>` | System configuration to use |
| `--dry-run` | Show configuration without running OpenCode |
| `-v, --verbose` | Show detailed debug output |
| `--docker-image <img>` | Override Docker image |
| `-i, --interactive` | Start interactive OpenCode session |

### What Pipeline Mode Does

The script follows the exact same steps as the Azure DevOps pipeline:

1. **Environment Detection** - Detects submodule vs standalone mode
2. **Fetch Work Item** - Gets work item details, comments, and attachments
3. **Resolve System** - Determines which system configuration to use
4. **Load Skills** - Copies skills from template → org → system layers
5. **Load Agents** - Copies agents from template → org → system layers
6. **Build Prompt** - Constructs the prompt with work item context
7. **Run OpenCode** - Executes in Docker container
8. **Output Result** - Saves to `result.md`

### Dry-Run Output

The `--dry-run` flag shows everything that would be sent to OpenCode without actually running it:

```
==============================================
1. ENVIRONMENT DETECTION
==============================================
[INFO] Repository root: /home/user/repo
[INFO] Scripts directory: template/scripts
[INFO] Submodule mode: true
[INFO] Mode: analyze
[INFO] Docker image: jspannareif/opencode-mcp:latest

==============================================
7. CONFIGURATION SUMMARY
==============================================

Mode:           analyze
System:         _default
Submodule:      true
Work Item ID:   1373926
Docker Image:   jspannareif/opencode-mcp:latest
Skills:         brainstorming,debugging,tdd,...
Agents:         analyze,command,implement

==============================================
8. PROMPT PREVIEW
==============================================
# Analyze Prompt
...
```

## CA Certificates for Internal Endpoints

If your organization uses internal endpoints (Confluence, Jira, internal APIs) with custom CA certificates, see [CA Certificates](../certs/README.md).

The `run-local.sh` script automatically:
1. Detects `.crt` files in the `certs/` directory
2. Mounts them into the container
3. Runs `update-ca-certificates` to install them
4. Sets `NODE_EXTRA_CA_CERTS` for Node.js applications

## Testing Core Functionality

Run the test suite to verify skills, agents, and configuration loading:

```bash
./scripts/test-core.sh
```

This runs 21 tests covering:
- Environment detection (submodule vs standalone)
- Skills loading and layering
- Agents loading
- System detection
- Prompt building
- OpenCode configuration

## Troubleshooting

### "Auth file not found"

```bash
# Option 1: Run opencode auth
opencode auth login

# Option 2: Set environment variable
export OPENCODE_AUTH_JSON='{"token": "..."}'
```

### "AZURE_DEVOPS_* must be set"

```bash
export AZURE_DEVOPS_ORG="your-org"
export AZURE_DEVOPS_PROJECT="your-project"
export AZURE_DEVOPS_PAT="your-pat"
```

### Container hangs or times out

Check if CA certificates are needed for internal endpoints:

```bash
# Test without certs
docker run --rm jspannareif/opencode-mcp:latest --version

# Test with certs
./scripts/run-local.sh --dry-run  # Shows if certs are detected
```

### Skills/Agents not loading

Use verbose mode to see loading details:

```bash
./scripts/run-local.sh --mode analyze --work-item-id 123 --dry-run --verbose
```
