#!/bin/bash
# run-local.sh
# Local testing script that mirrors the Azure DevOps pipeline logic exactly
#
# Usage:
#   ./run-local.sh --mode analyze --work-item-id 1373926
#   ./run-local.sh --mode command --work-item-id 1373926 --command "list all comments"
#   ./run-local.sh --mode analyze --work-item-id 1373926 --dry-run
#   ./run-local.sh --mode analyze --context-file ./test-context.json --dry-run
#
# Required environment variables:
#   AZURE_DEVOPS_ORG, AZURE_DEVOPS_PROJECT, AZURE_DEVOPS_PAT
#   OPENCODE_AUTH_JSON (for actual runs, not dry-run)
#
# Optional:
#   DOCKER_IMAGE - Override the OpenCode Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
MODE=""
WORK_ITEM_ID=""
COMMAND_TEXT=""
DRY_RUN=false
VERBOSE=false
CONTEXT_FILE=""
DOCKER_IMAGE="${DOCKER_IMAGE:-jspannareif/opencode-mcp:latest}"
TARGET_REPO=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --work-item-id)
            WORK_ITEM_ID="$2"
            shift 2
            ;;
        --command)
            COMMAND_TEXT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --context-file)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --docker-image)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        --target-repo)
            TARGET_REPO="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --mode <analyze|implement|command> [options]"
            echo ""
            echo "Options:"
            echo "  --mode <mode>         Required: analyze, implement, or command"
            echo "  --work-item-id <id>   Work item ID to process (fetches context from ADO)"
            echo "  --context-file <file> Use local context file instead of fetching"
            echo "  --command <text>      Command text (required for command mode)"
            echo "  --dry-run             Show what would be sent without running OpenCode"
            echo "  --verbose, -v         Show detailed debug output"
            echo "  --docker-image <img>  Override Docker image"
            echo "  --target-repo <repo>  Target repository (for implement mode)"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Environment variables:"
            echo "  AZURE_DEVOPS_ORG      Azure DevOps organization"
            echo "  AZURE_DEVOPS_PROJECT  Azure DevOps project"
            echo "  AZURE_DEVOPS_PAT      Personal Access Token or System.AccessToken"
            echo "  OPENCODE_AUTH_JSON    OpenCode auth configuration (for actual runs)"
            echo "  DOCKER_IMAGE          Override Docker image (default: jspannareif/opencode-mcp:latest)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
log() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}=============================================="
    echo -e "$1"
    echo -e "==============================================${NC}"
}

# Validate required arguments
if [ -z "$MODE" ]; then
    log_error "--mode is required (analyze|implement|command)"
    exit 1
fi

case $MODE in
    analyze|implement|command)
        ;;
    *)
        log_error "Invalid mode '$MODE'. Must be analyze, implement, or command"
        exit 1
        ;;
esac

if [ "$MODE" = "command" ] && [ -z "$COMMAND_TEXT" ]; then
    log_error "--command is required for command mode"
    exit 1
fi

if [ -z "$WORK_ITEM_ID" ] && [ -z "$CONTEXT_FILE" ]; then
    log_error "Either --work-item-id or --context-file is required"
    exit 1
fi

# Detect script location and mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Detect submodule vs standalone mode (same as pipeline)
cd "$REPO_ROOT"
if [ -d "template/scripts" ]; then
    SCRIPTS="template/scripts"
    SUBMODULE_MODE="true"
    log "Running in submodule mode"
else
    SCRIPTS="scripts"
    SUBMODULE_MODE="false"
    log "Running in standalone mode"
fi

# Make scripts executable
chmod +x $SCRIPTS/*.sh 2>/dev/null || true

section "1. ENVIRONMENT DETECTION"

log "Repository root: $REPO_ROOT"
log "Scripts directory: $SCRIPTS"
log "Submodule mode: $SUBMODULE_MODE"
log "Mode: $MODE"
log "Docker image: $DOCKER_IMAGE"

# Validate environment variables
if [ -z "$CONTEXT_FILE" ]; then
    if [ -z "$AZURE_DEVOPS_ORG" ] || [ -z "$AZURE_DEVOPS_PROJECT" ] || [ -z "$AZURE_DEVOPS_PAT" ]; then
        log_error "AZURE_DEVOPS_ORG, AZURE_DEVOPS_PROJECT, and AZURE_DEVOPS_PAT must be set"
        exit 1
    fi
    log_success "Azure DevOps credentials configured"
fi

if [ "$DRY_RUN" = false ] && [ -z "$OPENCODE_AUTH_JSON" ]; then
    log_warn "OPENCODE_AUTH_JSON not set - will fail on actual run"
fi

section "2. FETCH WORK ITEM CONTEXT"

WORK_DIR="$REPO_ROOT/.run-local-$$"
mkdir -p "$WORK_DIR/attachments"

# Cleanup on exit
cleanup() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

if [ -n "$CONTEXT_FILE" ]; then
    log "Using provided context file: $CONTEXT_FILE"
    cp "$CONTEXT_FILE" "$WORK_DIR/workitem-context.json"
else
    log "Fetching work item $WORK_ITEM_ID from Azure DevOps..."
    ./$SCRIPTS/get-workitem-context.sh \
        --work-item-id "$WORK_ITEM_ID" \
        --output "$WORK_DIR/workitem-context.json" \
        --attachments-dir "$WORK_DIR/attachments"
    log_success "Work item context fetched"
fi

# Show attachments
if [ "$(ls -A "$WORK_DIR/attachments" 2>/dev/null)" ]; then
    log "Attachments downloaded:"
    ls -la "$WORK_DIR/attachments/"
else
    log "No attachments"
fi

section "3. RESOLVE SYSTEM CONFIGURATION"

# Resolve system (same logic as pipeline)
if [ "$SUBMODULE_MODE" = "true" ]; then
    SYSTEM=$(./$SCRIPTS/resolve-system-config.sh \
        --context-file "$WORK_DIR/workitem-context.json" \
        --systems-dir systems \
        --systems-dir template/systems \
        ${VERBOSE:+--verbose})
else
    SYSTEM=$(./$SCRIPTS/resolve-system-config.sh \
        --context-file "$WORK_DIR/workitem-context.json" \
        ${VERBOSE:+--verbose})
fi

log "Detected system: $SYSTEM"

# Copy OpenCode config (same priority as pipeline)
if [ -f "systems/_default/opencode.json" ]; then
    cp systems/_default/opencode.json "$WORK_DIR/opencode.json"
    log "Using local opencode.json"
elif [ -f "template/systems/_default/opencode.json" ]; then
    cp template/systems/_default/opencode.json "$WORK_DIR/opencode.json"
    log "Using template opencode.json"
else
    log_warn "No opencode.json found"
    echo '{}' > "$WORK_DIR/opencode.json"
fi

section "4. LOAD SKILLS"

mkdir -p "$WORK_DIR/.opencode/skills"

if [ "$SUBMODULE_MODE" = "true" ]; then
    # 1. Template default skills
    if [ -d "template/systems/_default/skills" ]; then
        log_verbose "Loading template default skills..."
        cp -r template/systems/_default/skills/* "$WORK_DIR/.opencode/skills/" 2>/dev/null || true
    fi

    # 2. Local default skills (can override template)
    if [ -d "systems/_default/skills" ]; then
        log_verbose "Loading organization-specific skills..."
        cp -r systems/_default/skills/* "$WORK_DIR/.opencode/skills/" 2>/dev/null || true
    fi

    # 3. System-specific skills from both locations
    for systems_dir in template/systems systems; do
        if [ -d "$systems_dir/$SYSTEM/skills" ] && [ "$(ls -A $systems_dir/$SYSTEM/skills 2>/dev/null)" ]; then
            log_verbose "Loading skills from $systems_dir/$SYSTEM..."
            cp -r $systems_dir/$SYSTEM/skills/* "$WORK_DIR/.opencode/skills/" 2>/dev/null || true
        fi
    done
else
    # Standalone mode
    if [ -d "systems/_default/skills" ]; then
        cp -r systems/_default/skills/* "$WORK_DIR/.opencode/skills/" 2>/dev/null || true
    fi
    if [ -d "systems/$SYSTEM/skills" ] && [ "$(ls -A systems/$SYSTEM/skills 2>/dev/null)" ]; then
        cp -r systems/$SYSTEM/skills/* "$WORK_DIR/.opencode/skills/" 2>/dev/null || true
    fi
fi

SKILLS_LIST=$(ls -1 "$WORK_DIR/.opencode/skills/" 2>/dev/null | sed 's/\.md$//' | tr '\n' ', ' | sed 's/,$//')
log "Loaded skills: ${SKILLS_LIST:-none}"

section "5. LOAD AGENTS"

mkdir -p "$WORK_DIR/.opencode/agents"

if [ "$SUBMODULE_MODE" = "true" ]; then
    # 1. Template default agents
    if [ -d "template/systems/_default/agents" ]; then
        log_verbose "Loading template default agents..."
        cp -r template/systems/_default/agents/* "$WORK_DIR/.opencode/agents/" 2>/dev/null || true
    fi

    # 2. Local default agents (can override template)
    if [ -d "systems/_default/agents" ]; then
        log_verbose "Loading organization-specific agents..."
        cp -r systems/_default/agents/* "$WORK_DIR/.opencode/agents/" 2>/dev/null || true
    fi

    # 3. System-specific agents from both locations
    for systems_dir in template/systems systems; do
        if [ -d "$systems_dir/$SYSTEM/agents" ] && [ "$(ls -A $systems_dir/$SYSTEM/agents 2>/dev/null)" ]; then
            log_verbose "Loading agents from $systems_dir/$SYSTEM..."
            cp -r $systems_dir/$SYSTEM/agents/* "$WORK_DIR/.opencode/agents/" 2>/dev/null || true
        fi
    done
else
    # Standalone mode
    if [ -d "systems/_default/agents" ]; then
        cp -r systems/_default/agents/* "$WORK_DIR/.opencode/agents/" 2>/dev/null || true
    fi
    if [ -d "systems/$SYSTEM/agents" ] && [ "$(ls -A systems/$SYSTEM/agents 2>/dev/null)" ]; then
        cp -r systems/$SYSTEM/agents/* "$WORK_DIR/.opencode/agents/" 2>/dev/null || true
    fi
fi

AGENTS_LIST=$(ls -1 "$WORK_DIR/.opencode/agents/" 2>/dev/null | sed 's/\.md$//' | tr '\n' ', ' | sed 's/,$//')
log "Loaded agents: ${AGENTS_LIST:-none}"

section "6. BUILD PROMPT"

# Build prompt (same as pipeline)
if [ "$SUBMODULE_MODE" = "true" ]; then
    PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode "$MODE" \
        --system "$SYSTEM" \
        --context "$WORK_DIR/workitem-context.json" \
        ${COMMAND_TEXT:+--command "$COMMAND_TEXT"} \
        --systems-dir systems \
        --systems-dir template/systems)
else
    PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode "$MODE" \
        --system "$SYSTEM" \
        --context "$WORK_DIR/workitem-context.json" \
        ${COMMAND_TEXT:+--command "$COMMAND_TEXT"})
fi

log_success "Prompt built successfully"

section "7. CONFIGURATION SUMMARY"

echo ""
echo "Mode:           $MODE"
echo "System:         $SYSTEM"
echo "Submodule:      $SUBMODULE_MODE"
echo "Work Item ID:   ${WORK_ITEM_ID:-N/A}"
echo "Docker Image:   $DOCKER_IMAGE"
echo "Skills:         $SKILLS_LIST"
echo "Agents:         $AGENTS_LIST"
echo ""

if [ "$VERBOSE" = true ]; then
    echo "--- OPENCODE CONFIG ---"
    cat "$WORK_DIR/opencode.json"
    echo ""
fi

section "8. PROMPT PREVIEW"

# Show prompt (truncated unless verbose)
if [ "$VERBOSE" = true ]; then
    echo "$PROMPT"
else
    echo "$PROMPT" | head -100
    LINES=$(echo "$PROMPT" | wc -l)
    if [ "$LINES" -gt 100 ]; then
        echo ""
        echo "... (truncated, $LINES total lines, use --verbose to see all)"
    fi
fi

if [ "$DRY_RUN" = true ]; then
    section "DRY RUN COMPLETE"
    log "Would run OpenCode with agent: $MODE"
    log "Prompt length: $(echo "$PROMPT" | wc -c) characters"
    exit 0
fi

section "9. RUN OPENCODE"

if [ -z "$OPENCODE_AUTH_JSON" ]; then
    log_error "OPENCODE_AUTH_JSON is required for actual runs"
    exit 1
fi

# Create auth directory
mkdir -p "$HOME/.local/share/opencode"
echo "$OPENCODE_AUTH_JSON" > "$HOME/.local/share/opencode/auth.json"

# Copy workspace files
cp "$WORK_DIR/opencode.json" "$REPO_ROOT/opencode.json"
rm -rf "$REPO_ROOT/.opencode/skills" "$REPO_ROOT/.opencode/agents" 2>/dev/null || true
mkdir -p "$REPO_ROOT/.opencode"
cp -r "$WORK_DIR/.opencode/skills" "$REPO_ROOT/.opencode/" 2>/dev/null || true
cp -r "$WORK_DIR/.opencode/agents" "$REPO_ROOT/.opencode/" 2>/dev/null || true
cp -r "$WORK_DIR/attachments" "$REPO_ROOT/" 2>/dev/null || true
cp "$WORK_DIR/workitem-context.json" "$REPO_ROOT/" 2>/dev/null || true

log "Running OpenCode in Docker..."

# Run OpenCode (same as pipeline)
docker run --rm \
    -e ADO_MCP_AUTH_TOKEN="$AZURE_DEVOPS_PAT" \
    -e AZURE_DEVOPS_ORG_URL="https://dev.azure.com/$AZURE_DEVOPS_ORG" \
    -e AZURE_DEVOPS_ORG="$AZURE_DEVOPS_ORG" \
    -e AZURE_DEVOPS_PROJECT="$AZURE_DEVOPS_PROJECT" \
    -e AZURE_DEVOPS_PAT="$AZURE_DEVOPS_PAT" \
    -e WORK_ITEM_ID="$WORK_ITEM_ID" \
    -v "$HOME/.local/share/opencode:/root/.local/share/opencode" \
    -v "$REPO_ROOT:/workspace" \
    -w /workspace \
    "$DOCKER_IMAGE" run --agent "$MODE" "$PROMPT" > "$REPO_ROOT/result.md"

section "10. RESULT"

if [ -f "$REPO_ROOT/result.md" ]; then
    cat "$REPO_ROOT/result.md"
    log_success "Result saved to result.md"
else
    log_error "No result file generated"
    exit 1
fi
