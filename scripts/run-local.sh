#!/usr/bin/env bash
# run-local.sh
# Local testing script that mirrors the Azure DevOps pipeline logic exactly
# Also supports simple interactive/prompt mode for quick testing
#
# Pipeline-mirroring mode (full work item processing):
#   ./run-local.sh --mode analyze --work-item-id 1373926
#   ./run-local.sh --mode command --work-item-id 1373926 --command "list all comments"
#   ./run-local.sh --mode analyze --work-item-id 1373926 --dry-run
#   ./run-local.sh --mode analyze --context-file ./test-context.json --dry-run
#
# Simple prompt mode (quick testing):
#   ./run-local.sh "analyze this codebase"
#   ./run-local.sh -s spectre "what does this system do?"
#   ./run-local.sh --interactive
#
# Required environment variables (pipeline mode):
#   AZURE_DEVOPS_ORG, AZURE_DEVOPS_PROJECT, AZURE_DEVOPS_PAT
#   OPENCODE_AUTH_JSON (for actual runs, not dry-run)
#
# Required for actual runs (both modes):
#   ~/.local/share/opencode/auth.json OR OPENCODE_AUTH_JSON
#
# Optional:
#   DOCKER_IMAGE - Override the OpenCode Docker image
#   AZURE_DEVOPS_ORG_URL - Override ADO URL (default: https://dev.azure.com/$AZURE_DEVOPS_ORG)

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
DOCKER_IMAGE="${DOCKER_IMAGE:-ghcr.io/opencode-ai/opencode:latest}"
TARGET_REPO=""
SYSTEM=""
INTERACTIVE=false
PROMPT_ARGS=()

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
        -s|--system)
            SYSTEM="$2"
            shift 2
            ;;
        --interactive|-i)
            INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] [prompt]"
            echo ""
            echo "Pipeline-mirroring mode (processes work items like the ADO pipeline):"
            echo "  $0 --mode <analyze|implement|command> --work-item-id <id>"
            echo ""
            echo "Simple prompt mode (quick testing):"
            echo "  $0 \"your prompt here\""
            echo "  $0 --interactive"
            echo ""
            echo "Options:"
            echo "  --mode <mode>         Mode: analyze, implement, or command (pipeline mode)"
            echo "  --work-item-id <id>   Work item ID to process (fetches context from ADO)"
            echo "  --context-file <file> Use local context file instead of fetching"
            echo "  --command <text>      Command text (required for command mode)"
            echo "  -s, --system <name>   System configuration to use"
            echo "  --dry-run             Show what would be sent without running OpenCode"
            echo "  --verbose, -v         Show detailed debug output"
            echo "  --docker-image <img>  Override Docker image"
            echo "  --target-repo <repo>  Target repository (for implement mode)"
            echo "  -i, --interactive     Start interactive OpenCode session"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Environment variables:"
            echo "  AZURE_DEVOPS_ORG      Azure DevOps organization"
            echo "  AZURE_DEVOPS_PROJECT  Azure DevOps project"
            echo "  AZURE_DEVOPS_PAT      Personal Access Token or System.AccessToken"
            echo "  OPENCODE_AUTH_JSON    OpenCode auth configuration"
            echo "  DOCKER_IMAGE          Override Docker image"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            PROMPT_ARGS+=("$1")
            shift
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

# Detect script location and mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Detect submodule vs standalone mode (same as pipeline)
cd "$REPO_ROOT"
if [ -d "template/scripts" ]; then
    SCRIPTS="template/scripts"
    SUBMODULE_MODE="true"
else
    SCRIPTS="scripts"
    SUBMODULE_MODE="false"
fi

# Make scripts executable
chmod +x $SCRIPTS/*.sh 2>/dev/null || true

# Auth file location
AUTH_FILE="$HOME/.local/share/opencode/auth.json"

# Determine execution mode
if [ -n "$MODE" ] || [ -n "$WORK_ITEM_ID" ] || [ -n "$CONTEXT_FILE" ]; then
    # Pipeline mode - process work item
    EXECUTION_MODE="pipeline"
elif [ "$INTERACTIVE" = true ] || [ ${#PROMPT_ARGS[@]} -gt 0 ]; then
    # Simple prompt/interactive mode
    EXECUTION_MODE="simple"
else
    log_error "No mode specified. Use --help for usage."
    exit 1
fi

# ============================================================================
# SIMPLE MODE - Quick prompt/interactive execution
# ============================================================================
if [ "$EXECUTION_MODE" = "simple" ]; then
    # Check for auth
    if [ ! -f "$AUTH_FILE" ]; then
        if [ -n "$OPENCODE_AUTH_JSON" ]; then
            mkdir -p "$(dirname "$AUTH_FILE")"
            echo "$OPENCODE_AUTH_JSON" > "$AUTH_FILE"
        else
            log_error "Auth file not found at $AUTH_FILE"
            echo ""
            echo "To authenticate with GitHub Copilot, run:"
            echo "  opencode auth login"
            echo ""
            echo "Or set OPENCODE_AUTH_JSON environment variable"
            exit 1
        fi
    fi

    # Check for ADO PAT (optional but recommended)
    if [ -z "$AZURE_DEVOPS_PAT" ]; then
        log_warn "AZURE_DEVOPS_PAT not set. Azure DevOps MCP will not work."
    fi

    # Configuration
    AZURE_DEVOPS_ORG_URL="${AZURE_DEVOPS_ORG_URL:-https://dev.azure.com/${AZURE_DEVOPS_ORG:-your-org}}"
    WORKSPACE="${WORKSPACE:-$(pwd)}"

    # Copy opencode.json to workspace if not present
    if [ ! -f "$WORKSPACE/opencode.json" ]; then
        if [ -f "$REPO_ROOT/systems/_default/opencode.json" ]; then
            log "Copying opencode.json to workspace..."
            cp "$REPO_ROOT/systems/_default/opencode.json" "$WORKSPACE/opencode.json"
        elif [ -f "$REPO_ROOT/template/systems/_default/opencode.json" ]; then
            log "Copying opencode.json to workspace..."
            cp "$REPO_ROOT/template/systems/_default/opencode.json" "$WORKSPACE/opencode.json"
        fi
    fi

    # Clear and load skills fresh (layered like pipeline)
    rm -rf "$WORKSPACE/.opencode/skills"
    mkdir -p "$WORKSPACE/.opencode/skills"

    if [ "$SUBMODULE_MODE" = "true" ]; then
        # 1. Template default skills (generic base)
        TEMPLATE_SKILLS_DIR="$REPO_ROOT/template/systems/_default/skills"
        if [ -d "$TEMPLATE_SKILLS_DIR" ] && [ "$(ls -A "$TEMPLATE_SKILLS_DIR" 2>/dev/null)" ]; then
            log "Loading template default skills..."
            cp -r "$TEMPLATE_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        fi

        # 2. Local default skills (organization-specific, can override template)
        LOCAL_SKILLS_DIR="$REPO_ROOT/systems/_default/skills"
        if [ -d "$LOCAL_SKILLS_DIR" ] && [ "$(ls -A "$LOCAL_SKILLS_DIR" 2>/dev/null)" ]; then
            log "Loading organization-specific skills..."
            cp -r "$LOCAL_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        fi

        # 3. System-specific skills from both locations
        if [ -n "$SYSTEM" ]; then
            for systems_dir in "$REPO_ROOT/template/systems" "$REPO_ROOT/systems"; do
                SKILLS_DIR="$systems_dir/$SYSTEM/skills"
                if [ -d "$SKILLS_DIR" ] && [ "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
                    log "Loading skills from $(basename "$systems_dir")/$SYSTEM..."
                    cp -r "$SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
                fi
            done
        fi
    else
        # Standalone mode: simple loading
        DEFAULT_SKILLS_DIR="$REPO_ROOT/systems/_default/skills"
        if [ -d "$DEFAULT_SKILLS_DIR" ] && [ "$(ls -A "$DEFAULT_SKILLS_DIR" 2>/dev/null)" ]; then
            log "Loading default skills..."
            cp -r "$DEFAULT_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        fi

        if [ -n "$SYSTEM" ]; then
            SKILLS_DIR="$REPO_ROOT/systems/$SYSTEM/skills"
            if [ -d "$SKILLS_DIR" ] && [ "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
                log "Loading skills from system: $SYSTEM"
                cp -r "$SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
            else
                log_warn "No skills found for system '$SYSTEM'"
            fi
        fi
    fi

    # Clear and load agents fresh (layered like skills)
    rm -rf "$WORKSPACE/.opencode/agents"
    mkdir -p "$WORKSPACE/.opencode/agents"

    if [ "$SUBMODULE_MODE" = "true" ]; then
        # 1. Template default agents
        TEMPLATE_AGENTS_DIR="$REPO_ROOT/template/systems/_default/agents"
        if [ -d "$TEMPLATE_AGENTS_DIR" ] && [ "$(ls -A "$TEMPLATE_AGENTS_DIR" 2>/dev/null)" ]; then
            log "Loading template default agents..."
            cp -r "$TEMPLATE_AGENTS_DIR"/* "$WORKSPACE/.opencode/agents/" 2>/dev/null || true
        fi

        # 2. Local default agents (organization-specific, can override template)
        LOCAL_AGENTS_DIR="$REPO_ROOT/systems/_default/agents"
        if [ -d "$LOCAL_AGENTS_DIR" ] && [ "$(ls -A "$LOCAL_AGENTS_DIR" 2>/dev/null)" ]; then
            log "Loading organization-specific agents..."
            cp -r "$LOCAL_AGENTS_DIR"/* "$WORKSPACE/.opencode/agents/" 2>/dev/null || true
        fi

        # 3. System-specific agents from both locations
        if [ -n "$SYSTEM" ]; then
            for systems_dir in "$REPO_ROOT/template/systems" "$REPO_ROOT/systems"; do
                AGENTS_DIR="$systems_dir/$SYSTEM/agents"
                if [ -d "$AGENTS_DIR" ] && [ "$(ls -A "$AGENTS_DIR" 2>/dev/null)" ]; then
                    log "Loading agents from $(basename "$systems_dir")/$SYSTEM..."
                    cp -r "$AGENTS_DIR"/* "$WORKSPACE/.opencode/agents/" 2>/dev/null || true
                fi
            done
        fi
    else
        # Standalone mode: simple loading
        DEFAULT_AGENTS_DIR="$REPO_ROOT/systems/_default/agents"
        if [ -d "$DEFAULT_AGENTS_DIR" ] && [ "$(ls -A "$DEFAULT_AGENTS_DIR" 2>/dev/null)" ]; then
            log "Loading default agents..."
            cp -r "$DEFAULT_AGENTS_DIR"/* "$WORKSPACE/.opencode/agents/" 2>/dev/null || true
        fi

        if [ -n "$SYSTEM" ]; then
            AGENTS_DIR="$REPO_ROOT/systems/$SYSTEM/agents"
            if [ -d "$AGENTS_DIR" ] && [ "$(ls -A "$AGENTS_DIR" 2>/dev/null)" ]; then
                log "Loading agents from system: $SYSTEM"
                cp -r "$AGENTS_DIR"/* "$WORKSPACE/.opencode/agents/" 2>/dev/null || true
            fi
        fi
    fi

    # Show model being used
    if [ -f "$WORKSPACE/opencode.json" ]; then
        MODEL=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKSPACE/opencode.json" 2>/dev/null | cut -d'"' -f4)
        log "Model: ${MODEL:-not specified}"
    fi

    log "Starting OpenCode container..."
    echo "  Workspace: $WORKSPACE"
    echo "  Auth: $AUTH_FILE"
    echo "  ADO URL: $AZURE_DEVOPS_ORG_URL"
    echo ""

    # Build docker command as array
    DOCKER_ARGS=(run --rm)

    if [ -t 0 ] && [ -t 1 ]; then
        # Interactive TTY available
        DOCKER_ARGS+=(-it)
    fi

    # Mount auth directory
    DOCKER_ARGS+=(-v "$HOME/.local/share/opencode:/root/.local/share/opencode")

    # Mount workspace
    DOCKER_ARGS+=(-v "$WORKSPACE:/workspace")
    DOCKER_ARGS+=(-w /workspace)

    # Mount temp/output directory for generated files
    TEMP_DIR="$REPO_ROOT/.temp"
    mkdir -p "$TEMP_DIR"
    DOCKER_ARGS+=(-v "$TEMP_DIR:/output")
    log "Output directory: $TEMP_DIR (mounted at /output in container)"

    # Mount CA certificates if available (for internal HTTPS endpoints)
    # Supports multiple .crt files in certs/ directory
    # Note: update-ca-certificates requires certs directly in /usr/local/share/ca-certificates/
    # So we mount to /tmp/org-certs and copy in the entrypoint script
    CERTS_DIR="$REPO_ROOT/certs"
    CA_CERTS_FOUND=false
    if [ -d "$CERTS_DIR" ] && ls "$CERTS_DIR"/*.crt 1>/dev/null 2>&1; then
        log "Mounting organization CA certificates:"
        ls "$CERTS_DIR"/*.crt | while read cert; do echo "  - $(basename "$cert")"; done
        DOCKER_ARGS+=(-v "$CERTS_DIR:/tmp/org-certs:ro")
        CA_CERTS_FOUND=true
    fi

    # Environment variables
    if [ -n "$AZURE_DEVOPS_PAT" ]; then
        DOCKER_ARGS+=(-e "ADO_MCP_AUTH_TOKEN=$AZURE_DEVOPS_PAT")
    fi
    DOCKER_ARGS+=(-e "AZURE_DEVOPS_ORG_URL=$AZURE_DEVOPS_ORG_URL")

    # If prompt provided, run non-interactively
    if [ ${#PROMPT_ARGS[@]} -gt 0 ]; then
        PROMPT="${PROMPT_ARGS[*]}"
        log "Running with prompt: $PROMPT"
        echo ""
        if [ "$CA_CERTS_FOUND" = true ]; then
            # Copy org certs to proper location and run update-ca-certificates
            # Must use --entrypoint to override container's default entrypoint
            # Set NODE_EXTRA_CA_CERTS so Node.js also trusts the certs
            # Use $1 for the prompt argument (underscore is placeholder for $0)
            docker "${DOCKER_ARGS[@]}" --entrypoint sh "$DOCKER_IMAGE" -c '
                cp /tmp/org-certs/*.crt /usr/local/share/ca-certificates/ 2>/dev/null
                update-ca-certificates 2>/dev/null
                export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
                opencode run "$1"
            ' _ "$PROMPT"
        else
            docker "${DOCKER_ARGS[@]}" "$DOCKER_IMAGE" run "$PROMPT"
        fi
    else
        # Interactive mode
        log "Starting interactive session..."
        echo ""
        if [ "$CA_CERTS_FOUND" = true ]; then
            # Copy org certs to proper location and run update-ca-certificates
            # Must use --entrypoint to override container's default entrypoint
            # Set NODE_EXTRA_CA_CERTS so Node.js also trusts the certs
            docker "${DOCKER_ARGS[@]}" --entrypoint sh "$DOCKER_IMAGE" -c '
                cp /tmp/org-certs/*.crt /usr/local/share/ca-certificates/ 2>/dev/null
                update-ca-certificates 2>/dev/null
                export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
                exec opencode
            '
        else
            docker "${DOCKER_ARGS[@]}" "$DOCKER_IMAGE"
        fi
    fi

    exit 0
fi

# ============================================================================
# PIPELINE MODE - Full work item processing (mirrors ADO pipeline exactly)
# ============================================================================

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

if [ "$DRY_RUN" = false ] && [ -z "$OPENCODE_AUTH_JSON" ] && [ ! -f "$AUTH_FILE" ]; then
    log_warn "OPENCODE_AUTH_JSON not set and no auth file - will fail on actual run"
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
if [ -n "$SYSTEM" ]; then
    log "Using specified system: $SYSTEM"
elif [ "$SUBMODULE_MODE" = "true" ]; then
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

# Post "working" indicator for analyze mode (will be updated with result)
if [ "$MODE" = "analyze" ] && [ -n "$WORK_ITEM_ID" ]; then
    log "Posting 'working' indicator to work item..."
    WORKING_MSG="## AI Analysis in Progress

Analyzing work item and attachments...

*This comment will be updated with the analysis result.*"

    ./$SCRIPTS/update-workitem.sh \
        --work-item-id "$WORK_ITEM_ID" \
        --upsert-comment "AI-ANALYSIS" \
        --add-comment "$WORKING_MSG" 2>/dev/null || log_warn "Could not post working indicator"
fi

section "9. RUN OPENCODE"

# Handle auth
if [ -n "$OPENCODE_AUTH_JSON" ]; then
    mkdir -p "$HOME/.local/share/opencode"
    echo "$OPENCODE_AUTH_JSON" > "$HOME/.local/share/opencode/auth.json"
elif [ ! -f "$AUTH_FILE" ]; then
    log_error "OPENCODE_AUTH_JSON is required for actual runs (or ~/.local/share/opencode/auth.json)"
    exit 1
fi

# Copy workspace files
cp "$WORK_DIR/opencode.json" "$REPO_ROOT/opencode.json"
rm -rf "$REPO_ROOT/.opencode/skills" "$REPO_ROOT/.opencode/agents" 2>/dev/null || true
mkdir -p "$REPO_ROOT/.opencode"
cp -r "$WORK_DIR/.opencode/skills" "$REPO_ROOT/.opencode/" 2>/dev/null || true
cp -r "$WORK_DIR/.opencode/agents" "$REPO_ROOT/.opencode/" 2>/dev/null || true
cp -r "$WORK_DIR/attachments" "$REPO_ROOT/" 2>/dev/null || true
cp "$WORK_DIR/workitem-context.json" "$REPO_ROOT/" 2>/dev/null || true

log "Running OpenCode in Docker..."

# Build docker arguments
DOCKER_ARGS="--rm"
DOCKER_ARGS="$DOCKER_ARGS -e ADO_MCP_AUTH_TOKEN=$AZURE_DEVOPS_PAT"
DOCKER_ARGS="$DOCKER_ARGS -e AZURE_DEVOPS_ORG_URL=https://dev.azure.com/$AZURE_DEVOPS_ORG"
DOCKER_ARGS="$DOCKER_ARGS -e AZURE_DEVOPS_ORG=$AZURE_DEVOPS_ORG"
DOCKER_ARGS="$DOCKER_ARGS -e AZURE_DEVOPS_PROJECT=$AZURE_DEVOPS_PROJECT"
DOCKER_ARGS="$DOCKER_ARGS -e AZURE_DEVOPS_PAT=$AZURE_DEVOPS_PAT"
DOCKER_ARGS="$DOCKER_ARGS -e WORK_ITEM_ID=$WORK_ITEM_ID"
DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.local/share/opencode:/root/.local/share/opencode"
DOCKER_ARGS="$DOCKER_ARGS -v $REPO_ROOT:/workspace"
DOCKER_ARGS="$DOCKER_ARGS -w /workspace"

# Add CA certificates if available (for internal HTTPS endpoints)
# Organizations can provide certs/*.crt files for internal SSL/TLS
# Note: mount to /tmp/org-certs and copy to proper location in entrypoint
CA_MOUNT=""
CERTS_DIR="$REPO_ROOT/certs"
if [ -d "$CERTS_DIR" ] && ls "$CERTS_DIR"/*.crt 1>/dev/null 2>&1; then
    log "Mounting organization CA certificates:"
    ls "$CERTS_DIR"/*.crt | while read cert; do echo "  - $(basename "$cert")"; done
    CA_MOUNT="-v $CERTS_DIR:/tmp/org-certs:ro"
fi

# Run OpenCode (same as pipeline)
# If CA certs mounted, copy to proper location and run update-ca-certificates
# Must use --entrypoint to override container's default entrypoint
# Set NODE_EXTRA_CA_CERTS so Node.js also trusts the certs
# Use $1 and $2 for agent mode and prompt (underscore is placeholder for $0)
if [ -n "$CA_MOUNT" ]; then
    docker run $DOCKER_ARGS $CA_MOUNT --entrypoint sh \
        "$DOCKER_IMAGE" -c '
            cp /tmp/org-certs/*.crt /usr/local/share/ca-certificates/ 2>/dev/null
            update-ca-certificates 2>/dev/null
            export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
            opencode run --agent "$1" "$2"
        ' _ "$MODE" "$PROMPT" > "$REPO_ROOT/result.md"
else
    docker run $DOCKER_ARGS \
        "$DOCKER_IMAGE" run --agent "$MODE" "$PROMPT" > "$REPO_ROOT/result.md"
fi

section "10. RESULT"

if [ -f "$REPO_ROOT/result.md" ]; then
    cat "$REPO_ROOT/result.md"
    log_success "Result saved to result.md"

    # Update work item comment with result (for analyze mode)
    if [ "$MODE" = "analyze" ] && [ -n "$WORK_ITEM_ID" ]; then
        log "Updating work item comment with analysis result..."
        ANALYSIS=$(cat "$REPO_ROOT/result.md")
        ANALYSIS_WITH_FOOTER="${ANALYSIS}

---
*Agent: analyze*"

        ./$SCRIPTS/update-workitem.sh \
            --work-item-id "$WORK_ITEM_ID" \
            --upsert-comment "AI-ANALYSIS" \
            --add-comment "$ANALYSIS_WITH_FOOTER" 2>/dev/null && log_success "Work item comment updated" || log_warn "Could not update work item comment"
    fi
else
    log_error "No result file generated"
    exit 1
fi
