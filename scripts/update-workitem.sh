#!/bin/bash
# update-workitem.sh
# Updates work item with comments and tags via Azure DevOps REST API

set -e

# Default values
WORK_ITEM_ID=""
ADD_COMMENT=""
ADD_TAGS=()
REMOVE_TAGS=()
ADD_REACTION=""
REACTION_COMMENT_ID=""
REACTION_COMMENT_PATTERN=""
LIST_COMMENTS=false
DELETE_COMMENT_ID=""
DELETE_AI_COMMENTS=false
UPDATE_COMMENT_ID=""
UPSERT_MARKER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --work-item-id)
            WORK_ITEM_ID="$2"
            shift 2
            ;;
        --add-comment)
            ADD_COMMENT="$2"
            shift 2
            ;;
        --add-tag)
            ADD_TAGS+=("$2")
            shift 2
            ;;
        --remove-tag)
            REMOVE_TAGS+=("$2")
            shift 2
            ;;
        --add-reaction)
            # Reaction type: like, dislike, heart, hooray, smile, confused
            ADD_REACTION="$2"
            shift 2
            ;;
        --reaction-comment-id)
            # Specific comment ID to react to
            REACTION_COMMENT_ID="$2"
            shift 2
            ;;
        --reaction-comment-pattern)
            # Pattern to search for in comments (e.g., "@ai")
            # Will find the most recent comment containing this pattern
            REACTION_COMMENT_PATTERN="$2"
            shift 2
            ;;
        --list-comments)
            # List all comments on the work item
            LIST_COMMENTS=true
            shift
            ;;
        --delete-comment)
            # Delete a specific comment by ID
            DELETE_COMMENT_ID="$2"
            shift 2
            ;;
        --delete-ai-comments)
            # Delete all comments from AI/Build Service
            DELETE_AI_COMMENTS=true
            shift
            ;;
        --update-comment)
            # Update an existing comment (use with --add-comment for new text)
            UPDATE_COMMENT_ID="$2"
            shift 2
            ;;
        --upsert-comment)
            # Upsert: find comment with marker and update, or create new
            # Use with --add-comment for the content
            UPSERT_MARKER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$WORK_ITEM_ID" ]; then
    echo "Error: --work-item-id is required"
    exit 1
fi

# Validate environment variables
if [ -z "$AZURE_DEVOPS_ORG" ] || [ -z "$AZURE_DEVOPS_PROJECT" ] || [ -z "$AZURE_DEVOPS_PAT" ]; then
    echo "Error: AZURE_DEVOPS_ORG, AZURE_DEVOPS_PROJECT, and AZURE_DEVOPS_PAT must be set"
    exit 1
fi

# Set up authorization header
# System.AccessToken uses Bearer auth, PAT uses Basic auth
if [[ "$AZURE_DEVOPS_PAT" == ey* ]]; then
    # JWT token (System.AccessToken) - use Bearer auth
    AUTH_HEADER="Authorization: Bearer $AZURE_DEVOPS_PAT"
else
    # PAT - use Basic auth (use -w 0 to avoid line wrapping)
    AUTH=$(echo -n ":$AZURE_DEVOPS_PAT" | base64 -w 0)
    AUTH_HEADER="Authorization: Basic $AUTH"
fi

# Base API URL
BASE_URL="https://dev.azure.com/$AZURE_DEVOPS_ORG/$AZURE_DEVOPS_PROJECT/_apis"

# Function to convert Markdown to HTML for Azure DevOps comments
markdown_to_html() {
    local text="$1"
    local result=""
    local in_list=false
    local list_buffer=""

    # Process line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Check if line is a list item
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            # Convert inline markdown in list item
            item=$(echo "$item" | sed -E 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g')
            item=$(echo "$item" | sed -E 's/\*([^*]+)\*/<i>\1<\/i>/g')
            item=$(echo "$item" | sed -E 's/\[([^]]+)\]\(([^)]+)\)/<a href="\2">\1<\/a>/g')

            if [ "$in_list" = false ]; then
                in_list=true
                list_buffer="<ul><li>$item</li>"
            else
                list_buffer="$list_buffer<li>$item</li>"
            fi
            continue
        fi

        # Close list if we were in one
        if [ "$in_list" = true ]; then
            result="$result$list_buffer</ul>"
            in_list=false
            list_buffer=""
        fi

        # Convert headers (## Header)
        if [[ "$line" =~ ^##[[:space:]]+(.*) ]]; then
            line="<h2>${BASH_REMATCH[1]}</h2>"
        # Convert bold (**text**)
        else
            line=$(echo "$line" | sed -E 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g')
            # Convert italic (*text*) - be careful not to match **
            line=$(echo "$line" | sed -E 's/([^*]|^)\*([^*]+)\*([^*]|$)/\1<i>\2<\/i>\3/g')
            # Convert links [text](url)
            line=$(echo "$line" | sed -E 's/\[([^]]+)\]\(([^)]+)\)/<a href="\2">\1<\/a>/g')
            # Convert bare URLs to links
            line=$(echo "$line" | sed -E 's/(^|[[:space:]])(https?:\/\/[^[:space:]<]+)/\1<a href="\2">\2<\/a>/g')
        fi

        # Add line with <br> for non-empty lines (except headers which are block elements)
        if [ -n "$line" ]; then
            if [[ "$line" =~ ^"<h2>" ]]; then
                result="$result$line"
            else
                if [ -n "$result" ] && [[ ! "$result" =~ "</h2>"$ ]] && [[ ! "$result" =~ "</ul>"$ ]]; then
                    result="$result<br>$line"
                else
                    result="$result$line"
                fi
            fi
        elif [ -n "$result" ]; then
            # Empty line - add break for spacing
            result="$result<br>"
        fi
    done <<< "$text"

    # Close any remaining list
    if [ "$in_list" = true ]; then
        result="$result$list_buffer</ul>"
    fi

    echo "$result"
}

# Function to add comment to work item
add_comment() {
    local comment="$1"

    echo "Adding comment to work item $WORK_ITEM_ID..."

    # Convert Markdown to HTML for Azure DevOps
    local html_comment=$(markdown_to_html "$comment")

    # Escape the comment for JSON
    local escaped_comment=$(echo "$html_comment" | jq -Rs .)

    RESPONSE=$(curl -s -X POST \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"text\": $escaped_comment}" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments?api-version=7.0-preview.3")

    if echo "$RESPONSE" | grep -q '"id"'; then
        echo "Comment added successfully"
    else
        echo "Warning: Could not add comment"
        echo "$RESPONSE"
    fi
}

# Function to update tags
update_tags() {
    # First, get current tags
    WORK_ITEM_URL="$BASE_URL/wit/workitems/$WORK_ITEM_ID?api-version=7.0"
    CURRENT=$(curl -s -X GET \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        "$WORK_ITEM_URL")

    CURRENT_TAGS=$(echo "$CURRENT" | jq -r '.fields["System.Tags"] // ""')

    # Convert to array
    IFS=';' read -ra TAG_ARRAY <<< "$CURRENT_TAGS"

    # Trim whitespace from existing tags
    TAGS=()
    for tag in "${TAG_ARRAY[@]}"; do
        trimmed=$(echo "$tag" | xargs)
        if [ -n "$trimmed" ]; then
            TAGS+=("$trimmed")
        fi
    done

    # Remove tags
    for tag_to_remove in "${REMOVE_TAGS[@]}"; do
        NEW_ARRAY=()
        for tag in "${TAGS[@]}"; do
            if [ "$tag" != "$tag_to_remove" ]; then
                NEW_ARRAY+=("$tag")
            fi
        done
        TAGS=("${NEW_ARRAY[@]}")
    done

    # Add tags
    for tag_to_add in "${ADD_TAGS[@]}"; do
        # Check if tag already exists
        if [[ ! " ${TAGS[*]} " =~ " ${tag_to_add} " ]]; then
            TAGS+=("$tag_to_add")
        fi
    done

    # Filter out empty elements and join
    NEW_TAGS=""
    for tag in "${TAGS[@]}"; do
        if [ -n "$tag" ]; then
            if [ -n "$NEW_TAGS" ]; then
                NEW_TAGS="$NEW_TAGS; $tag"
            else
                NEW_TAGS="$tag"
            fi
        fi
    done

    echo "Updating tags: $NEW_TAGS"

    # Update work item
    PATCH_URL="$BASE_URL/wit/workitems/$WORK_ITEM_ID?api-version=7.0"

    RESPONSE=$(curl -s -X PATCH \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json-patch+json" \
        -d "[{\"op\": \"replace\", \"path\": \"/fields/System.Tags\", \"value\": \"$NEW_TAGS\"}]" \
        "$PATCH_URL")

    if echo "$RESPONSE" | grep -q '"id"'; then
        echo "Tags updated successfully"
    else
        echo "Warning: Could not update tags"
        echo "$RESPONSE"
    fi
}

# Function to get the latest comment ID containing a specific pattern (e.g., @ai)
# Usage: get_comment_id_with_pattern "@ai" or get_comment_id_with_pattern "" for latest
get_comment_id_with_pattern() {
    local pattern="$1"

    echo "Fetching comments for work item $WORK_ITEM_ID..." >&2

    # Fetch recent comments (last 20, ordered by newest first)
    COMMENTS_RESPONSE=$(curl -s -X GET \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments?api-version=7.1-preview.4&\$top=20&order=desc")

    if [ -z "$pattern" ]; then
        # No pattern - just get the latest comment
        COMMENT_ID=$(echo "$COMMENTS_RESPONSE" | jq -r '.comments[0].id // empty')
    else
        # Search for the most recent comment containing the pattern (case-insensitive)
        COMMENT_ID=$(echo "$COMMENTS_RESPONSE" | jq -r --arg pat "$pattern" '
            .comments[] |
            select(.text | test($pat; "i")) |
            .id
        ' | head -n 1)
    fi

    if [ -z "$COMMENT_ID" ]; then
        if [ -z "$pattern" ]; then
            echo "Warning: Could not find any comments on work item" >&2
        else
            echo "Warning: Could not find comment containing '$pattern'" >&2
        fi
        return 1
    fi

    echo "Found comment ID: $COMMENT_ID" >&2
    echo "$COMMENT_ID"
}

# Function to add reaction to a comment
# Reaction types: like, dislike, heart, hooray, smile, confused
add_reaction() {
    local reaction_type="$1"
    local comment_id="$2"
    local search_pattern="$3"

    # If no comment ID provided, search for comment
    if [ -z "$comment_id" ]; then
        comment_id=$(get_comment_id_with_pattern "$search_pattern")
        if [ -z "$comment_id" ]; then
            echo "Error: Could not get comment ID for reaction"
            return 1
        fi
    fi

    echo "Adding '$reaction_type' reaction to comment $comment_id on work item $WORK_ITEM_ID..."

    # Azure DevOps uses PUT to add a reaction (need Content-Length: 0 for empty body)
    RESPONSE=$(curl -s -X PUT \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -H "Content-Length: 0" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments/$comment_id/reactions/$reaction_type?api-version=7.1-preview.1")

    if echo "$RESPONSE" | grep -q '"type"'; then
        echo "Reaction '$reaction_type' added successfully"
    else
        echo "Warning: Could not add reaction"
        echo "$RESPONSE"
    fi
}

# Function to list all comments on a work item
list_comments() {
    echo "Listing comments for work item $WORK_ITEM_ID..."

    RESPONSE=$(curl -s -X GET \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments?api-version=7.1-preview.4&\$top=100&order=desc")

    if echo "$RESPONSE" | jq -e '.comments' > /dev/null 2>&1; then
        COMMENT_COUNT=$(echo "$RESPONSE" | jq '.comments | length')
        echo "Found $COMMENT_COUNT comments:"
        echo ""
        echo "$RESPONSE" | jq -r '.comments[] | "ID: \(.id)\nAuthor: \(.createdBy.displayName)\nDate: \(.createdDate)\nText: \(.text | gsub("<[^>]*>"; "") | .[0:200])...\n---"'
    else
        echo "No comments found or error fetching comments"
        echo "$RESPONSE"
    fi
}

# Function to delete a specific comment
delete_comment() {
    local comment_id="$1"

    echo "Deleting comment $comment_id from work item $WORK_ITEM_ID..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
        -H "$AUTH_HEADER" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments/$comment_id?api-version=7.1-preview.4")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "Comment $comment_id deleted successfully"
    else
        echo "Warning: Could not delete comment (HTTP $HTTP_CODE)"
        echo "$BODY"
    fi
}

# Function to delete all AI/Build Service comments
delete_ai_comments() {
    echo "Finding and deleting AI comments from work item $WORK_ITEM_ID..."

    # Get all comments
    RESPONSE=$(curl -s -X GET \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments?api-version=7.1-preview.4&\$top=100")

    # Find comments from AI agent (by service account name patterns)
    # Common patterns: "Build Service", "Project Collection Build Service", contains "AI"
    COMMENT_IDS=$(echo "$RESPONSE" | jq -r '.comments[] |
        select(
            (.createdBy.displayName | test("Build Service"; "i")) or
            (.createdBy.displayName | test("\\bAI\\b"; "i")) or
            (.text | test("AI Agent"; "i"))
        ) |
        .id')

    if [ -z "$COMMENT_IDS" ]; then
        echo "No AI comments found"
        return 0
    fi

    DELETE_COUNT=0
    for id in $COMMENT_IDS; do
        delete_comment "$id"
        DELETE_COUNT=$((DELETE_COUNT + 1))
    done

    echo "Deleted $DELETE_COUNT AI comment(s)"
}

# Function to update an existing comment
update_comment() {
    local comment_id="$1"
    local new_text="$2"

    echo "Updating comment $comment_id on work item $WORK_ITEM_ID..."

    # Convert Markdown to HTML for Azure DevOps
    local html_comment=$(markdown_to_html "$new_text")

    # Escape the comment for JSON
    local escaped_comment=$(echo "$html_comment" | jq -Rs .)

    RESPONSE=$(curl -s -X PATCH \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{\"text\": $escaped_comment}" \
        "$BASE_URL/wit/workitems/$WORK_ITEM_ID/comments/$comment_id?api-version=7.1-preview.4")

    if echo "$RESPONSE" | grep -q '"id"'; then
        echo "Comment $comment_id updated successfully"
    else
        echo "Warning: Could not update comment"
        echo "$RESPONSE"
    fi
}

# Execute updates

# List comments (exits after listing)
if [ "$LIST_COMMENTS" = true ]; then
    list_comments
    exit 0
fi

# Delete AI comments
if [ "$DELETE_AI_COMMENTS" = true ]; then
    delete_ai_comments
fi

# Delete specific comment
if [ -n "$DELETE_COMMENT_ID" ]; then
    delete_comment "$DELETE_COMMENT_ID"
fi

# Upsert comment: find existing with marker and update, or create new
if [ -n "$UPSERT_MARKER" ] && [ -n "$ADD_COMMENT" ]; then
    # Search for existing comment with the marker
    EXISTING_COMMENT_ID=$(get_comment_id_with_pattern "$UPSERT_MARKER")

    # Prepend marker as small badge at top of comment
    COMMENT_WITH_MARKER="**[$UPSERT_MARKER]**

${ADD_COMMENT}"

    if [ -n "$EXISTING_COMMENT_ID" ]; then
        echo "Updating existing comment $EXISTING_COMMENT_ID (found marker: $UPSERT_MARKER)"
        update_comment "$EXISTING_COMMENT_ID" "$COMMENT_WITH_MARKER"
    else
        echo "Creating new comment with marker: $UPSERT_MARKER"
        add_comment "$COMMENT_WITH_MARKER"
    fi
# Update existing comment (use with --add-comment for new text)
elif [ -n "$UPDATE_COMMENT_ID" ] && [ -n "$ADD_COMMENT" ]; then
    update_comment "$UPDATE_COMMENT_ID" "$ADD_COMMENT"
# Add new comment (only if not updating)
elif [ -n "$ADD_COMMENT" ]; then
    add_comment "$ADD_COMMENT"
fi

if [ ${#ADD_TAGS[@]} -gt 0 ] || [ ${#REMOVE_TAGS[@]} -gt 0 ]; then
    update_tags
fi

if [ -n "$ADD_REACTION" ]; then
    add_reaction "$ADD_REACTION" "$REACTION_COMMENT_ID" "$REACTION_COMMENT_PATTERN"
fi

echo "Work item $WORK_ITEM_ID updated"
