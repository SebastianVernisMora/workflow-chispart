#!/bin/bash

# Blackbox API adapter using curl

# Usage: ./adapters/blackbox_api_curl.sh <prompt>

# Set API key from environment

API_KEY="${BLACKBOX_API_KEY}"

if [ -z "$API_KEY" ]; then
    echo "Error: BLACKBOX_API_KEY not set"
    exit 1
fi

# Get prompt from argument

PROMPT="$1"

if [ -z "$PROMPT" ]; then
    echo "Error: No prompt provided"
    exit 1
fi

# Make API call

RESPONSE=$(curl -X POST "https://api.blackbox.ai/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{\"model\": \"gpt-4\", \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]}" \
    2>/dev/null)

echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "Error: Failed to parse response"
