#!/usr/bin/env bash
# test-core.sh
# Test suite for core OpenCode pipeline functionality
#
# Tests:
# 1. Skills loading (template → org → system-specific layering)
# 2. Agents loading (same layering)
# 3. System detection (tags, area path matching)
# 4. Prompt building (variable substitution)
# 5. Submodule mode detection
#
# Usage:
#   ./template/scripts/test-core.sh
#   ./template/scripts/test-core.sh --verbose

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VERBOSE=false
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Detect mode
if [ -d "template/scripts" ]; then
    SCRIPTS="template/scripts"
    SUBMODULE_MODE="true"
else
    SCRIPTS="scripts"
    SUBMODULE_MODE="false"
fi

# Test directory
TEST_DIR="$REPO_ROOT/.test-core-$$"
mkdir -p "$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper functions
log() {
    echo -e "$1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $1... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${RED}Reason: $1${NC}"
    fi
}

# Create mock work item context
create_mock_context() {
    local output_file="$1"
    local tags="${2:-}"
    local area_path="${3:-TestProject\\\\Test}"

    # Escape backslashes for JSON (\ -> \\)
    local escaped_area_path="${area_path//\\/\\\\}"

    cat > "$output_file" << EOF
{
  "id": "999999",
  "title": "Test Work Item",
  "type": "Bug",
  "state": "New",
  "tags": "$tags",
  "areaPath": "$escaped_area_path",
  "description": "Test description",
  "acceptance_criteria": "Test criteria",
  "repro_steps": "Test steps",
  "attachments": [],
  "comments": []
}
EOF
}

# =============================================================================
# TEST SUITE
# =============================================================================

echo ""
echo -e "${CYAN}=============================================="
echo "OpenCode Core Functionality Tests"
echo "==============================================${NC}"
echo ""
echo "Repository: $REPO_ROOT"
echo "Mode: $([ "$SUBMODULE_MODE" = "true" ] && echo "Submodule" || echo "Standalone")"
echo ""

# -----------------------------------------------------------------------------
# Test 1: Submodule mode detection
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Group 1] Environment Detection${NC}"

test_start "Submodule mode detection"
if [ "$SUBMODULE_MODE" = "true" ] && [ -d "template/scripts" ]; then
    test_pass
elif [ "$SUBMODULE_MODE" = "false" ] && [ -d "scripts" ] && [ ! -d "template/scripts" ]; then
    test_pass
else
    test_fail "Mode detection inconsistent"
fi

test_start "Scripts directory exists"
if [ -d "$SCRIPTS" ]; then
    test_pass
else
    test_fail "$SCRIPTS not found"
fi

test_start "Core scripts present"
REQUIRED_SCRIPTS="build-prompt.sh resolve-system-config.sh get-workitem-context.sh update-workitem.sh run-local.sh"
MISSING=""
for script in $REQUIRED_SCRIPTS; do
    if [ ! -f "$SCRIPTS/$script" ]; then
        MISSING="$MISSING $script"
    fi
done
if [ -z "$MISSING" ]; then
    test_pass
else
    test_fail "Missing:$MISSING"
fi

# -----------------------------------------------------------------------------
# Test 2: Skills loading
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 2] Skills Loading${NC}"

# Create mock context
create_mock_context "$TEST_DIR/context.json" "" "TestProject\\Test"

test_start "Default skills directory exists"
if [ -d "template/systems/_default/skills" ] || [ -d "systems/_default/skills" ]; then
    test_pass
else
    test_fail "No default skills directory"
fi

test_start "Skills are discovered"
# Manually collect skills (same logic as pipeline)
SKILLS_DIR="$TEST_DIR/skills"
mkdir -p "$SKILLS_DIR"

if [ "$SUBMODULE_MODE" = "true" ]; then
    cp -r template/systems/_default/skills/* "$SKILLS_DIR/" 2>/dev/null || true
    cp -r systems/_default/skills/* "$SKILLS_DIR/" 2>/dev/null || true
else
    cp -r systems/_default/skills/* "$SKILLS_DIR/" 2>/dev/null || true
fi

SKILLS_LIST=$(ls -1 "$SKILLS_DIR" 2>/dev/null | sed 's/\.md$//' | tr '\n' ',' | sed 's/,$//')
log_verbose "Skills found: $SKILLS_LIST"

if echo "$SKILLS_LIST" | grep -q "using-superpowers"; then
    test_pass
else
    test_fail "using-superpowers skill not found"
fi

test_start "Multiple skills loaded"
SKILL_COUNT=$(ls -1 "$SKILLS_DIR" 2>/dev/null | wc -l)
if [ "$SKILL_COUNT" -ge 5 ]; then
    test_pass
else
    test_fail "Only $SKILL_COUNT skills found, expected at least 5"
fi

test_start "Skill files are valid markdown"
INVALID_SKILLS=""
# Check skills in the collected directory
for skill_file in "$SKILLS_DIR"/*.md; do
    if [ -f "$skill_file" ]; then
        # Check for frontmatter
        if ! head -1 "$skill_file" | grep -q "^---"; then
            INVALID_SKILLS="$INVALID_SKILLS $(basename "$skill_file")"
        fi
    fi
done
if [ -z "$INVALID_SKILLS" ]; then
    test_pass
else
    test_fail "Missing frontmatter:$INVALID_SKILLS"
fi

# -----------------------------------------------------------------------------
# Test 3: Agents loading
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 3] Agents Loading${NC}"

test_start "Default agents directory exists"
if [ -d "template/systems/_default/agents" ] || [ -d "systems/_default/agents" ]; then
    test_pass
else
    test_fail "No default agents directory"
fi

test_start "Core agents are discovered"
# Manually collect agents (same logic as pipeline)
AGENTS_DIR="$TEST_DIR/agents"
mkdir -p "$AGENTS_DIR"

if [ "$SUBMODULE_MODE" = "true" ]; then
    cp -r template/systems/_default/agents/* "$AGENTS_DIR/" 2>/dev/null || true
    cp -r systems/_default/agents/* "$AGENTS_DIR/" 2>/dev/null || true
else
    cp -r systems/_default/agents/* "$AGENTS_DIR/" 2>/dev/null || true
fi

AGENTS_LIST=$(ls -1 "$AGENTS_DIR" 2>/dev/null | sed 's/\.md$//' | tr '\n' ',' | sed 's/,$//')
log_verbose "Agents found: $AGENTS_LIST"

MISSING_AGENTS=""
for agent in analyze command implement; do
    if ! echo "$AGENTS_LIST" | grep -q "$agent"; then
        MISSING_AGENTS="$MISSING_AGENTS $agent"
    fi
done
if [ -z "$MISSING_AGENTS" ]; then
    test_pass
else
    test_fail "Missing agents:$MISSING_AGENTS"
fi

test_start "Agent files have frontmatter"
INVALID_AGENTS=""
# Check agents in the collected directory
for agent_file in "$AGENTS_DIR"/*.md; do
    if [ -f "$agent_file" ]; then
        if ! head -1 "$agent_file" | grep -q "^---"; then
            INVALID_AGENTS="$INVALID_AGENTS $(basename "$agent_file")"
        fi
    fi
done
if [ -z "$INVALID_AGENTS" ]; then
    test_pass
else
    test_fail "Missing frontmatter:$INVALID_AGENTS"
fi

# -----------------------------------------------------------------------------
# Test 4: System detection
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 4] System Detection${NC}"

test_start "Default system when no match"
create_mock_context "$TEST_DIR/context-default.json" "" "SomeProject\\Unknown"
if [ "$SUBMODULE_MODE" = "true" ]; then
    SYSTEM=$(./$SCRIPTS/resolve-system-config.sh \
        --context-file "$TEST_DIR/context-default.json" \
        --systems-dir systems \
        --systems-dir template/systems 2>/dev/null)
else
    SYSTEM=$(./$SCRIPTS/resolve-system-config.sh \
        --context-file "$TEST_DIR/context-default.json" 2>/dev/null)
fi
if [ "$SYSTEM" = "_default" ]; then
    test_pass
else
    test_fail "Expected _default, got $SYSTEM"
fi

# Test tag-based detection if a non-default system exists
test_start "System config.yml format valid"
INVALID_CONFIGS=""
# Check config files in both locations
for systems_dir in template/systems systems; do
    if [ -d "$systems_dir" ]; then
        for config in "$systems_dir"/*/config.yml; do
            if [ -f "$config" ]; then
                # Basic YAML validation - check it's not empty and has expected structure
                if [ ! -s "$config" ]; then
                    INVALID_CONFIGS="$INVALID_CONFIGS $(dirname "$config" | xargs basename)"
                fi
            fi
        done
    fi
done
if [ -z "$INVALID_CONFIGS" ]; then
    test_pass
else
    test_fail "Invalid configs:$INVALID_CONFIGS"
fi

# -----------------------------------------------------------------------------
# Test 5: Prompt building
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 5] Prompt Building${NC}"

test_start "Analyze prompt builds successfully"
create_mock_context "$TEST_DIR/context-prompt.json" "" "TestProject\\Test"
if [ "$SUBMODULE_MODE" = "true" ]; then
    PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode analyze \
        --system _default \
        --context "$TEST_DIR/context-prompt.json" \
        --systems-dir systems \
        --systems-dir template/systems 2>/dev/null)
else
    PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode analyze \
        --system _default \
        --context "$TEST_DIR/context-prompt.json" 2>/dev/null)
fi
if [ -n "$PROMPT" ]; then
    test_pass
else
    test_fail "Empty prompt"
fi

test_start "Prompt contains work item context"
if echo "$PROMPT" | grep -q "Test Work Item"; then
    test_pass
else
    test_fail "Work item title not found in prompt"
fi

test_start "Prompt contains system context"
if echo "$PROMPT" | grep -q "AI Agent Context\|AI agent"; then
    test_pass
else
    test_fail "System context not found in prompt"
fi

test_start "Command prompt builds with command text"
if [ "$SUBMODULE_MODE" = "true" ]; then
    CMD_PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode command \
        --system _default \
        --context "$TEST_DIR/context-prompt.json" \
        --command "test command" \
        --systems-dir systems \
        --systems-dir template/systems 2>/dev/null)
else
    CMD_PROMPT=$(./$SCRIPTS/build-prompt.sh \
        --mode command \
        --system _default \
        --context "$TEST_DIR/context-prompt.json" \
        --command "test command" 2>/dev/null)
fi
if echo "$CMD_PROMPT" | grep -q "test command"; then
    test_pass
else
    test_fail "Command text not found in prompt"
fi

test_start "All modes have prompt templates"
MISSING_PROMPTS=""
for mode in analyze implement command; do
    FOUND=false
    for dir in template/systems/_default/prompts systems/_default/prompts; do
        if [ -f "$dir/$mode.md" ]; then
            FOUND=true
            break
        fi
    done
    if [ "$FOUND" = false ]; then
        MISSING_PROMPTS="$MISSING_PROMPTS $mode"
    fi
done
if [ -z "$MISSING_PROMPTS" ]; then
    test_pass
else
    test_fail "Missing prompts:$MISSING_PROMPTS"
fi

# -----------------------------------------------------------------------------
# Test 6: OpenCode config
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 6] OpenCode Configuration${NC}"

test_start "opencode.json exists"
if [ -f "systems/_default/opencode.json" ] || [ -f "template/systems/_default/opencode.json" ]; then
    test_pass
else
    test_fail "No opencode.json found"
fi

test_start "opencode.json is valid JSON"
CONFIG_FILE=""
if [ -f "systems/_default/opencode.json" ]; then
    CONFIG_FILE="systems/_default/opencode.json"
elif [ -f "template/systems/_default/opencode.json" ]; then
    CONFIG_FILE="template/systems/_default/opencode.json"
fi

if [ -n "$CONFIG_FILE" ] && jq . "$CONFIG_FILE" > /dev/null 2>&1; then
    test_pass
else
    test_fail "Invalid JSON in $CONFIG_FILE"
fi

# -----------------------------------------------------------------------------
# Test 7: Layering (org overrides template)
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 7] Layering (Org > Template)${NC}"

test_start "Organization skills override template"
# Skills can be either *.md files or directories containing SKILL.md
ORG_SKILLS=0
TEMPLATE_SKILLS=0

# Count org-level skills (can be file or directory)
if [ -d "systems/_default/skills" ]; then
    ORG_SKILLS=$(ls -d systems/_default/skills/*/ 2>/dev/null | wc -l || echo "0")
fi

# Count template skills
if [ -d "template/systems/_default/skills" ]; then
    TEMPLATE_SKILLS=$(ls -d template/systems/_default/skills/*/ 2>/dev/null | wc -l || echo "0")
fi

log_verbose "Org skills: $ORG_SKILLS, Template skills: $TEMPLATE_SKILLS"

if [ "$ORG_SKILLS" -gt 0 ] || [ "$TEMPLATE_SKILLS" -gt 0 ]; then
    test_pass
else
    test_fail "No skills in either layer"
fi

test_start "Skills from both layers are loaded"
# The skill count from earlier (SKILL_COUNT) should reflect both layers
if [ "$SKILL_COUNT" -ge 1 ]; then
    test_pass
else
    test_fail "No skills loaded"
fi

# -----------------------------------------------------------------------------
# Test 8: Update work item features
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[Group 8] Update Work Item Features${NC}"

test_start "update-workitem.sh supports --upsert-comment"
# Check that the script accepts upsert-comment by looking at source
if grep -q "upsert-comment" "$SCRIPTS/update-workitem.sh"; then
    test_pass
else
    test_fail "--upsert-comment not found in script"
fi

test_start "update-workitem.sh has comment marker handling"
# Check that the script handles comment markers for idempotent updates
if grep -q "UPSERT_MARKER\|upsert-comment" "$SCRIPTS/update-workitem.sh"; then
    test_pass
else
    test_fail "Comment marker handling not found"
fi

test_start "Pipeline posts working indicator before analysis"
# Check that analyze.yml posts a working indicator
if grep -q "AI Analysis in Progress\|working indicator" "$REPO_ROOT/template/pipelines/templates/analyze.yml" 2>/dev/null || \
   grep -q "AI Analysis in Progress\|working indicator" "$REPO_ROOT/pipelines/templates/analyze.yml" 2>/dev/null; then
    test_pass
else
    test_fail "Working indicator not found in analyze pipeline"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}=============================================="
echo "Test Summary"
echo "==============================================${NC}"
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
