#!/bin/bash
# resolve-system-config.sh
# Matches work item against system configuration detection rules
# Returns the matching system name or "_default"
#
# Supports multiple systems directories for template + organization overlay pattern:
#   --systems-dir ./systems --systems-dir ./template/systems
#
# Search order: First match wins (organization systems checked before template)

set -e

# Default values
CONTEXT_FILE=""
SYSTEMS_DIRS=()
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --context-file)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --systems-dir)
            SYSTEMS_DIRS+=("$2")
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$CONTEXT_FILE" ]; then
    echo "Error: --context-file is required" >&2
    echo "Usage: $0 --context-file <path-to-workitem.json> [--systems-dir <path>]... [--verbose]" >&2
    exit 1
fi

if [ ! -f "$CONTEXT_FILE" ]; then
    echo "Error: Context file not found: $CONTEXT_FILE" >&2
    exit 1
fi

# Default systems directory if none provided
if [ ${#SYSTEMS_DIRS[@]} -eq 0 ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SYSTEMS_DIRS=("$SCRIPT_DIR/../systems")
fi

# Validate at least one systems directory exists
VALID_DIRS=()
for dir in "${SYSTEMS_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        VALID_DIRS+=("$dir")
    fi
done

if [ ${#VALID_DIRS[@]} -eq 0 ]; then
    echo "Error: No valid systems directories found" >&2
    exit 1
fi

# Helper function for verbose logging
log() {
    if [ "$VERBOSE" = true ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Extract work item fields from JSON
WORK_ITEM_TAGS=$(jq -r '.tags // ""' "$CONTEXT_FILE")
WORK_ITEM_AREA_PATH=$(jq -r '.areaPath // ""' "$CONTEXT_FILE")

log "Work item tags: $WORK_ITEM_TAGS"
log "Work item area path: $WORK_ITEM_AREA_PATH"

# Function to extract list values from YAML detection section
# Args: $1 = config file, $2 = field name (tags or area_path)
extract_detection_list() {
    local file="$1"
    local field="$2"
    local in_detection=false
    local in_field=false

    while IFS= read -r line; do
        # Check if we're entering detection block
        if [[ "$line" =~ ^detection: ]]; then
            in_detection=true
            continue
        fi

        # Exit detection block if we hit another top-level key
        if $in_detection && [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi

        if [ "$in_detection" = true ]; then
            # Check if we're entering our target field
            if [[ "$line" =~ ^[[:space:]]+${field}: ]]; then
                in_field=true
                continue
            fi

            # Exit field if we hit another key at same level
            if $in_field && [[ "$line" =~ ^[[:space:]]+[a-z_]+: ]]; then
                in_field=false
                continue
            fi

            # Extract list item (handles both quoted and unquoted values)
            if [ "$in_field" = true ] && [[ "$line" =~ ^[[:space:]]+-[[:space:]]*(.*) ]]; then
                local value="${BASH_REMATCH[1]}"
                # Remove surrounding quotes
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                echo "$value"
            fi
        fi
    done < "$file"
}

# Function to check if a tag matches the work item tags
check_tag_match() {
    local pattern="$1"

    # Convert pattern to lowercase
    local pattern_lower
    pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')

    # Split tags by semicolon and check each
    IFS=';' read -ra tag_array <<< "$WORK_ITEM_TAGS"
    for tag in "${tag_array[@]}"; do
        # Trim whitespace and convert to lowercase
        local trimmed_tag
        trimmed_tag=$(echo "$tag" | xargs | tr '[:upper:]' '[:lower:]')

        if [ "$trimmed_tag" = "$pattern_lower" ]; then
            log "Tag match: '$trimmed_tag' == '$pattern_lower'"
            return 0
        fi
    done

    return 1
}

# Function to check if area path matches a pattern
check_area_path_match() {
    local pattern="$1"

    # Skip if no area path in work item
    if [ -z "$WORK_ITEM_AREA_PATH" ]; then
        return 1
    fi

    # Normalize backslashes
    local normalized_pattern="${pattern//\\\\/\\}"
    local normalized_area="${WORK_ITEM_AREA_PATH//\\\\/\\}"

    # Check for wildcard pattern (ends with *)
    if [[ "$normalized_pattern" == *'*' ]]; then
        # Remove the trailing * for prefix matching
        local prefix="${normalized_pattern%\*}"
        prefix="${prefix%\\}"  # Remove trailing backslash if any

        if [[ "$normalized_area" == "$prefix"* ]]; then
            log "Area path wildcard match: '$normalized_area' starts with '$prefix'"
            return 0
        fi
    else
        # Exact match
        if [ "$normalized_area" = "$normalized_pattern" ]; then
            log "Area path exact match: '$normalized_area'"
            return 0
        fi
    fi

    return 1
}

# Function to check if a system config matches the work item
check_system_match() {
    local system_dir="$1"
    local config_file="$system_dir/config.yml"
    local system_name
    system_name=$(basename "$system_dir")

    log "Checking system: $system_name"

    # Skip _default (it's the fallback)
    if [ "$system_name" = "_default" ]; then
        return 1
    fi

    # Skip if no config file
    if [ ! -f "$config_file" ]; then
        log "No config.yml found for $system_name"
        return 1
    fi

    # Check for fallback flag (skip)
    if grep -q "^[[:space:]]*fallback:[[:space:]]*true" "$config_file" 2>/dev/null; then
        log "System $system_name has fallback: true, skipping"
        return 1
    fi

    # Check tag matches
    while IFS= read -r tag_pattern; do
        if [ -n "$tag_pattern" ] && check_tag_match "$tag_pattern"; then
            return 0
        fi
    done < <(extract_detection_list "$config_file" "tags")

    # Check area path matches
    while IFS= read -r area_pattern; do
        if [ -n "$area_pattern" ] && check_area_path_match "$area_pattern"; then
            return 0
        fi
    done < <(extract_detection_list "$config_file" "area_path")

    return 1
}

# Process system directories (alphabetically, excluding _default)
# Search in order: organization systems first, then template systems
MATCHED_SYSTEM=""

for systems_dir in "${VALID_DIRS[@]}"; do
    log "Searching in: $systems_dir"
    for system_dir in "$systems_dir"/*/; do
        if [ ! -d "$system_dir" ]; then
            continue
        fi

        if check_system_match "$system_dir"; then
            MATCHED_SYSTEM=$(basename "$system_dir")
            log "Found matching system: $MATCHED_SYSTEM in $systems_dir"
            break 2  # Break out of both loops
        fi
    done
done

# Return result
if [ -n "$MATCHED_SYSTEM" ]; then
    echo "$MATCHED_SYSTEM"
else
    echo "_default"
fi
