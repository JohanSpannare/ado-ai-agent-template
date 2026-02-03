#!/usr/bin/env bash
# send-teams-notification.sh
# Sends notifications to Microsoft Teams via webhook

set -e

# Default values
NOTIFICATION_TYPE="info"
WORK_ITEM_ID=""
MESSAGE=""
PIPELINE_URL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            NOTIFICATION_TYPE="$2"
            shift 2
            ;;
        --work-item-id)
            WORK_ITEM_ID="$2"
            shift 2
            ;;
        --message)
            MESSAGE="$2"
            shift 2
            ;;
        --pipeline-url)
            PIPELINE_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate environment
if [ -z "$TEAMS_WEBHOOK_URL" ]; then
    echo "Warning: TEAMS_WEBHOOK_URL not set, skipping notification"
    exit 0
fi

# Set color based on type
case $NOTIFICATION_TYPE in
    error)
        COLOR="attention"
        TITLE="AI Agent Error"
        ;;
    success)
        COLOR="good"
        TITLE="AI Agent Success"
        ;;
    *)
        COLOR="default"
        TITLE="AI Agent Notification"
        ;;
esac

# Build work item URL if we have the ID
WORK_ITEM_URL=""
if [ -n "$WORK_ITEM_ID" ] && [ -n "$AZURE_DEVOPS_ORG" ] && [ -n "$AZURE_DEVOPS_PROJECT" ]; then
    WORK_ITEM_URL="https://dev.azure.com/$AZURE_DEVOPS_ORG/$AZURE_DEVOPS_PROJECT/_workitems/edit/$WORK_ITEM_ID"
fi

# Build adaptive card payload
read -r -d '' PAYLOAD << EOF || true
{
    "type": "message",
    "attachments": [
        {
            "contentType": "application/vnd.microsoft.card.adaptive",
            "content": {
                "\$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                "type": "AdaptiveCard",
                "version": "1.4",
                "body": [
                    {
                        "type": "TextBlock",
                        "text": "$TITLE",
                        "weight": "bolder",
                        "size": "large",
                        "color": "$COLOR"
                    },
                    {
                        "type": "TextBlock",
                        "text": "$MESSAGE",
                        "wrap": true
                    },
                    {
                        "type": "FactSet",
                        "facts": [
                            {
                                "title": "Work Item",
                                "value": "#$WORK_ITEM_ID"
                            },
                            {
                                "title": "Type",
                                "value": "$NOTIFICATION_TYPE"
                            }
                        ]
                    }
                ],
                "actions": [
                    ${WORK_ITEM_URL:+"{
                        \"type\": \"Action.OpenUrl\",
                        \"title\": \"View Work Item\",
                        \"url\": \"$WORK_ITEM_URL\"
                    },"}
                    ${PIPELINE_URL:+"{
                        \"type\": \"Action.OpenUrl\",
                        \"title\": \"View Pipeline\",
                        \"url\": \"$PIPELINE_URL\"
                    }"}
                ]
            }
        }
    ]
}
EOF

# Clean up JSON (remove trailing commas in actions array)
PAYLOAD=$(echo "$PAYLOAD" | sed 's/,\s*]/]/g')

echo "Sending Teams notification..."

# Send to webhook
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$TEAMS_WEBHOOK_URL")

# Check response
if [ "$RESPONSE" == "1" ] || [ -z "$RESPONSE" ]; then
    echo "Teams notification sent successfully"
else
    echo "Warning: Teams notification may have failed"
    echo "Response: $RESPONSE"
fi
