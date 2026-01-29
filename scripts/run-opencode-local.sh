#!/bin/bash
# Run OpenCode container locally for testing
# Usage: ./scripts/run-opencode-local.sh [-s|--system <system>] [prompt]
# Example: ./scripts/run-opencode-local.sh -s spectre "analyze this codebase"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
SYSTEM=""
PROMPT_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--system)
            SYSTEM="$2"
            shift 2
            ;;
        *)
            PROMPT_ARGS+=("$1")
            shift
            ;;
    esac
done

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Auth file location
AUTH_FILE="$HOME/.local/share/opencode/auth.json"

# Check for auth.json
if [ ! -f "$AUTH_FILE" ]; then
    echo -e "${RED}Error: Auth file not found at $AUTH_FILE${NC}"
    echo ""
    echo "To authenticate with GitHub Copilot, run:"
    echo "  opencode auth login"
    echo ""
    echo "Or copy auth.json from another machine:"
    echo "  mkdir -p ~/.local/share/opencode"
    echo "  cat > ~/.local/share/opencode/auth.json << 'EOF'"
    echo "  <paste auth.json content>"
    echo "  EOF"
    exit 1
fi

# Check for ADO PAT (optional but recommended)
if [ -z "$AZURE_DEVOPS_PAT" ]; then
    echo -e "${YELLOW}Warning: AZURE_DEVOPS_PAT not set. Azure DevOps MCP will not work.${NC}"
    echo "Set it with: export AZURE_DEVOPS_PAT=<your-pat>"
    echo ""
fi

# Configuration
AZURE_DEVOPS_ORG_URL="${AZURE_DEVOPS_ORG_URL:-https://dev.azure.com/if-it}"
IMAGE="${OPENCODE_IMAGE:-jspannareif/opencode-mcp:latest}"
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Copy opencode.json to workspace if not present
if [ ! -f "$WORKSPACE/opencode.json" ]; then
    echo -e "${YELLOW}Copying opencode.json to workspace...${NC}"
    cp "$REPO_ROOT/systems/_default/opencode.json" "$WORKSPACE/opencode.json"
fi

# Clear and load skills fresh (layered like pipeline)
rm -rf "$WORKSPACE/.opencode/skills"
mkdir -p "$WORKSPACE/.opencode/skills"

# Detect submodule mode
if [ -d "$REPO_ROOT/template/scripts" ]; then
    SUBMODULE_MODE="true"
else
    SUBMODULE_MODE="false"
fi

if [ "$SUBMODULE_MODE" = "true" ]; then
    # 1. Template default skills (generic base)
    TEMPLATE_SKILLS_DIR="$REPO_ROOT/template/systems/_default/skills"
    if [ -d "$TEMPLATE_SKILLS_DIR" ] && [ "$(ls -A "$TEMPLATE_SKILLS_DIR" 2>/dev/null)" ]; then
        echo -e "${GREEN}Loading template default skills:${NC}"
        cp -r "$TEMPLATE_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        for skill in "$TEMPLATE_SKILLS_DIR"/*/; do
            if [ -d "$skill" ]; then
                echo -e "  - $(basename "$skill")"
            fi
        done
    fi

    # 2. Local default skills (organization-specific, can override template)
    LOCAL_SKILLS_DIR="$REPO_ROOT/systems/_default/skills"
    if [ -d "$LOCAL_SKILLS_DIR" ] && [ "$(ls -A "$LOCAL_SKILLS_DIR" 2>/dev/null)" ]; then
        echo -e "${GREEN}Loading organization-specific skills:${NC}"
        cp -r "$LOCAL_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        for skill in "$LOCAL_SKILLS_DIR"/*/; do
            if [ -d "$skill" ]; then
                echo -e "  - $(basename "$skill")"
            fi
        done
    fi

    # 3. System-specific skills from both locations
    if [ -n "$SYSTEM" ]; then
        for systems_dir in "$REPO_ROOT/template/systems" "$REPO_ROOT/systems"; do
            SKILLS_DIR="$systems_dir/$SYSTEM/skills"
            if [ -d "$SKILLS_DIR" ] && [ "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
                echo -e "${GREEN}Loading skills from $(basename "$systems_dir")/$SYSTEM:${NC}"
                cp -r "$SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
                for skill in "$SKILLS_DIR"/*/; do
                    if [ -d "$skill" ]; then
                        echo -e "  - $(basename "$skill")"
                    fi
                done
            fi
        done
    fi
else
    # Standalone mode: simple loading
    DEFAULT_SKILLS_DIR="$REPO_ROOT/systems/_default/skills"
    if [ -d "$DEFAULT_SKILLS_DIR" ] && [ "$(ls -A "$DEFAULT_SKILLS_DIR" 2>/dev/null)" ]; then
        echo -e "${GREEN}Loading default skills:${NC}"
        cp -r "$DEFAULT_SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
        for skill in "$DEFAULT_SKILLS_DIR"/*/; do
            if [ -d "$skill" ]; then
                echo -e "  - $(basename "$skill")"
            fi
        done
    fi

    if [ -n "$SYSTEM" ]; then
        SKILLS_DIR="$REPO_ROOT/systems/$SYSTEM/skills"
        if [ -d "$SKILLS_DIR" ] && [ "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]; then
            echo -e "${GREEN}Loading skills from system: $SYSTEM${NC}"
            cp -r "$SKILLS_DIR"/* "$WORKSPACE/.opencode/skills/" 2>/dev/null || true
            for skill in "$SKILLS_DIR"/*/; do
                if [ -d "$skill" ]; then
                    echo -e "  - $(basename "$skill")"
                fi
            done
        else
            echo -e "${YELLOW}Warning: No skills found for system '$SYSTEM'${NC}"
        fi
    fi
fi

# Show model being used
MODEL=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKSPACE/opencode.json" | cut -d'"' -f4)
echo -e "${GREEN}Model: ${MODEL:-not specified}${NC}"

echo -e "${GREEN}Starting OpenCode container...${NC}"
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
echo -e "${GREEN}Output directory:${NC} $TEMP_DIR (mounted at /output in container)"

# Mount root CA certificate
CERT_FILE="$REPO_ROOT/certs/if-root-ca-g2.crt"
if [ -f "$CERT_FILE" ]; then
    DOCKER_ARGS+=(-v "$CERT_FILE:/usr/local/share/ca-certificates/if-root-ca-g2.crt")
    DOCKER_ARGS+=(-e "NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/if-root-ca-g2.crt")
fi

# Environment variables
if [ -n "$AZURE_DEVOPS_PAT" ]; then
    DOCKER_ARGS+=(-e "ADO_MCP_AUTH_TOKEN=$AZURE_DEVOPS_PAT")
fi
DOCKER_ARGS+=(-e "AZURE_DEVOPS_ORG_URL=$AZURE_DEVOPS_ORG_URL")

# Add image
DOCKER_ARGS+=("$IMAGE")

# If prompt provided, run non-interactively
if [ ${#PROMPT_ARGS[@]} -gt 0 ]; then
    PROMPT="${PROMPT_ARGS[*]}"
    echo -e "${GREEN}Running with prompt:${NC} $PROMPT"
    echo ""
    docker "${DOCKER_ARGS[@]}" run "$PROMPT"
else
    # Interactive mode
    echo -e "${GREEN}Starting interactive session...${NC}"
    echo ""
    docker "${DOCKER_ARGS[@]}"
fi
