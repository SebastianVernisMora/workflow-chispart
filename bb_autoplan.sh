#!/bin/bash

# Blackbox Autoplan Script

# Usage: ./bb_autoplan.sh <task_description>

# Load environment variables

source .env

export BLACKBOX_API_KEY

# Get task description

TASK="$1"

if [ -z "$TASK" ]; then
    echo "Error: No task description provided"
    echo "Usage: ./bb_autoplan.sh <task_description>"
    exit 1
fi

# Read system prompt

SYSTEM_PROMPT=$(cat prompts/blackbox_autoplan_system.md)

# Create user prompt

USER_PROMPT="Task: $TASK

Please provide a detailed plan and implementation for this task."

# Call API adapter

echo "Generating plan for: $TASK"

./adapters/blackbox_api_curl.sh "$SYSTEM_PROMPT

$USER_PROMPT"
