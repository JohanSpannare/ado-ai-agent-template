#!/usr/bin/env bash
# get-workitem-context.sh
# Fetches work item details from Azure DevOps REST API
# Including attachments (images, PDFs, etc.)

set -e

# Default values
WORK_ITEM_ID=""
OUTPUT_FILE=""
ATTACHMENTS_DIR=""
DOWNLOAD_ATTACHMENTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --work-item-id)
            WORK_ITEM_ID="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --attachments-dir)
            ATTACHMENTS_DIR="$2"
            DOWNLOAD_ATTACHMENTS=true
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
    AUTH_HEADER="Authorization: Bearer $AZURE_DEVOPS_PAT"
else
    # Use -w 0 to avoid line wrapping in base64
    AUTH=$(echo -n ":$AZURE_DEVOPS_PAT" | base64 -w 0)
    AUTH_HEADER="Authorization: Basic $AUTH"
fi

# Azure DevOps API URL
API_URL="https://dev.azure.com/$AZURE_DEVOPS_ORG/$AZURE_DEVOPS_PROJECT/_apis/wit/workitems/$WORK_ITEM_ID?\$expand=all&api-version=7.0"

echo "Fetching work item $WORK_ITEM_ID..."

# Fetch work item
RESPONSE=$(curl -s -X GET \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    "$API_URL")

# Check for errors
if echo "$RESPONSE" | grep -q '"message"'; then
    echo "Error fetching work item:"
    echo "$RESPONSE"
    exit 1
fi

# Extract relevant fields
TITLE=$(echo "$RESPONSE" | jq -r '.fields["System.Title"] // "No title"')
DESCRIPTION=$(echo "$RESPONSE" | jq -r '.fields["System.Description"] // "No description"')
ACCEPTANCE_CRITERIA=$(echo "$RESPONSE" | jq -r '.fields["Microsoft.VSTS.Common.AcceptanceCriteria"] // "No acceptance criteria"')
WORK_ITEM_TYPE=$(echo "$RESPONSE" | jq -r '.fields["System.WorkItemType"] // "Unknown"')
STATE=$(echo "$RESPONSE" | jq -r '.fields["System.State"] // "Unknown"')
TAGS=$(echo "$RESPONSE" | jq -r '.fields["System.Tags"] // ""')
AREA_PATH=$(echo "$RESPONSE" | jq -r '.fields["System.AreaPath"] // ""')
REPRO_STEPS=$(echo "$RESPONSE" | jq -r '.fields["Microsoft.VSTS.TCM.ReproSteps"] // ""')

# Extract and download attachments
ATTACHMENTS_JSON="[]"
if [ "$DOWNLOAD_ATTACHMENTS" = true ] && [ -n "$ATTACHMENTS_DIR" ]; then
    mkdir -p "$ATTACHMENTS_DIR"
    echo "Downloading attachments to $ATTACHMENTS_DIR..."

    # Extract attachment relations (rel = "AttachedFile")
    ATTACHMENT_URLS=$(echo "$RESPONSE" | jq -r '.relations[]? | select(.rel == "AttachedFile") | .url')

    ATTACHMENT_LIST=()
    for URL in $ATTACHMENT_URLS; do
        # Fetch attachment metadata
        ATTACHMENT_META=$(curl -s -X GET \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            "$URL")

        FILENAME=$(echo "$ATTACHMENT_META" | jq -r '.attributes.name // "unknown"')
        DOWNLOAD_URL=$(echo "$ATTACHMENT_META" | jq -r '.url // empty')
        FILE_SIZE=$(echo "$ATTACHMENT_META" | jq -r '.attributes.resourceSize // 0')

        if [ -n "$DOWNLOAD_URL" ] && [ -n "$FILENAME" ]; then
            # Sanitize filename (remove special chars)
            SAFE_FILENAME=$(echo "$FILENAME" | sed 's/[^a-zA-Z0-9._-]/_/g')
            LOCAL_PATH="$ATTACHMENTS_DIR/$SAFE_FILENAME"

            echo "  Downloading: $FILENAME ($FILE_SIZE bytes)"

            # Download the file
            curl -s -X GET \
                -H "$AUTH_HEADER" \
                -o "$LOCAL_PATH" \
                "$DOWNLOAD_URL"

            # Determine file type for context
            FILE_EXT="${FILENAME##*.}"
            FILE_TYPE="unknown"
            case "${FILE_EXT,,}" in
                jpg|jpeg|png|gif|bmp|webp)
                    FILE_TYPE="image"
                    ;;
                pdf)
                    FILE_TYPE="pdf"
                    ;;
                doc|docx)
                    FILE_TYPE="word"
                    ;;
                xls|xlsx)
                    FILE_TYPE="excel"
                    ;;
                txt|md|json|xml|csv)
                    FILE_TYPE="text"
                    ;;
                zip|tar|gz|7z)
                    FILE_TYPE="archive"
                    ;;
            esac

            # Add to list
            ATTACHMENT_LIST+=("{\"name\": \"$FILENAME\", \"path\": \"$LOCAL_PATH\", \"type\": \"$FILE_TYPE\", \"size\": $FILE_SIZE}")
        fi
    done

    # Extract inline images from HTML fields (Description, Acceptance Criteria, Repro Steps)
    # These are <img src="..."> tags pointing to Azure DevOps attachment URLs
    echo "Checking for inline images in HTML fields..."

    # Combine all HTML content
    ALL_HTML="$DESCRIPTION $ACCEPTANCE_CRITERIA $REPRO_STEPS"

    # Extract image URLs from <img src="..."> tags
    # Use sed to extract src attribute values from img tags
    INLINE_IMG_URLS=$(echo "$ALL_HTML" | \
        grep -oE '<img[^>]+src="[^"]*"' | \
        sed 's/.*src="\([^"]*\)".*/\1/' | \
        sort -u)

    # Also check for single-quoted src attributes
    INLINE_IMG_URLS_SQ=$(echo "$ALL_HTML" | \
        grep -oE "<img[^>]+src='[^']*'" | \
        sed "s/.*src='\([^']*\)'.*/\1/" | \
        sort -u)

    # Combine both
    INLINE_IMG_URLS=$(echo -e "$INLINE_IMG_URLS\n$INLINE_IMG_URLS_SQ" | grep -v '^$' | sort -u)

    INLINE_COUNT=0
    for IMG_URL in $INLINE_IMG_URLS; do
        # Skip data: URLs (base64 embedded images) - we'd need different handling
        if [[ "$IMG_URL" == data:* ]]; then
            echo "  Skipping base64 embedded image"
            continue
        fi

        # Handle relative URLs (Azure DevOps internal)
        if [[ "$IMG_URL" == /* ]]; then
            IMG_URL="https://dev.azure.com$IMG_URL"
        fi

        # Only download Azure DevOps URLs (security: don't fetch arbitrary external URLs)
        if [[ "$IMG_URL" == *"dev.azure.com"* ]] || [[ "$IMG_URL" == *"visualstudio.com"* ]]; then
            # Generate filename from URL or use counter
            if [[ "$IMG_URL" == *"fileName="* ]]; then
                FILENAME=$(echo "$IMG_URL" | grep -oP '(?<=fileName=)[^&]*')
            else
                INLINE_COUNT=$((INLINE_COUNT + 1))
                FILENAME="inline_image_${INLINE_COUNT}.png"
            fi

            SAFE_FILENAME=$(echo "$FILENAME" | sed 's/[^a-zA-Z0-9._-]/_/g')
            LOCAL_PATH="$ATTACHMENTS_DIR/$SAFE_FILENAME"

            # Skip if already downloaded
            if [ -f "$LOCAL_PATH" ]; then
                echo "  Already downloaded: $SAFE_FILENAME"
                continue
            fi

            echo "  Downloading inline image: $SAFE_FILENAME"

            # Download the image
            HTTP_CODE=$(curl -s -w "%{http_code}" -X GET \
                -H "$AUTH_HEADER" \
                -o "$LOCAL_PATH" \
                "$IMG_URL")

            if [ "$HTTP_CODE" = "200" ] && [ -s "$LOCAL_PATH" ]; then
                FILE_SIZE=$(stat -f%z "$LOCAL_PATH" 2>/dev/null || stat -c%s "$LOCAL_PATH" 2>/dev/null || echo "0")
                ATTACHMENT_LIST+=("{\"name\": \"$FILENAME\", \"path\": \"$LOCAL_PATH\", \"type\": \"image\", \"size\": $FILE_SIZE, \"source\": \"inline\"}")
            else
                echo "    Failed to download (HTTP $HTTP_CODE)"
                rm -f "$LOCAL_PATH"
            fi
        else
            echo "  Skipping external URL: ${IMG_URL:0:50}..."
        fi
    done

    # Build JSON array of attachments
    if [ ${#ATTACHMENT_LIST[@]} -gt 0 ]; then
        ATTACHMENTS_JSON=$(printf '%s\n' "${ATTACHMENT_LIST[@]}" | jq -s '.')
        echo "Downloaded ${#ATTACHMENT_LIST[@]} attachment(s) total"
    else
        echo "No attachments found"
    fi
fi

# =============================================================================
# Fetch comments
# =============================================================================
echo "Fetching comments..."

COMMENTS_API_URL="https://dev.azure.com/$AZURE_DEVOPS_ORG/$AZURE_DEVOPS_PROJECT/_apis/wit/workitems/$WORK_ITEM_ID/comments?api-version=7.1-preview.4"

COMMENTS_RESPONSE=$(curl -s -X GET \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    "$COMMENTS_API_URL")

# Extract comments into a simpler format (newest first, limit to last 20)
COMMENTS_JSON=$(echo "$COMMENTS_RESPONSE" | jq '[
    .comments[:20] | .[] | {
        id: .id,
        author: .createdBy.displayName,
        date: .createdDate,
        modifiedDate: .modifiedDate,
        text: .text
    }
]' 2>/dev/null || echo "[]")

COMMENTS_COUNT=$(echo "$COMMENTS_JSON" | jq 'length')
echo "Found $COMMENTS_COUNT comment(s)"

# Build context JSON
CONTEXT=$(jq -n \
    --arg id "$WORK_ITEM_ID" \
    --arg title "$TITLE" \
    --arg description "$DESCRIPTION" \
    --arg acceptance_criteria "$ACCEPTANCE_CRITERIA" \
    --arg type "$WORK_ITEM_TYPE" \
    --arg state "$STATE" \
    --arg tags "$TAGS" \
    --arg areaPath "$AREA_PATH" \
    --arg repro_steps "$REPRO_STEPS" \
    --argjson attachments "$ATTACHMENTS_JSON" \
    --argjson comments "$COMMENTS_JSON" \
    '{
        id: $id,
        title: $title,
        type: $type,
        state: $state,
        tags: $tags,
        areaPath: $areaPath,
        description: $description,
        acceptance_criteria: $acceptance_criteria,
        repro_steps: $repro_steps,
        attachments: $attachments,
        comments: $comments
    }')

# Output result
if [ -n "$OUTPUT_FILE" ]; then
    echo "$CONTEXT" > "$OUTPUT_FILE"
    echo "Work item context saved to $OUTPUT_FILE"
else
    echo "$CONTEXT"
fi
