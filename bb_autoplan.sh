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

AI_PLAN=$(./adapters/blackbox_api_curl.sh "$SYSTEM_PROMPT

$USER_PROMPT")

# Save plan to a temporary file
# Note: The issue description mentions .json, but the AI prompt suggests markdown.
# Using a generic name for now.
TMP_PLAN_FILE="/tmp/propuesta_plan.json"
echo "$AI_PLAN" > "$TMP_PLAN_FILE"

# --- Human-in-the-Loop Validation ---
while true; do
    echo ""
    echo "AI plan proposal has been saved to: $TMP_PLAN_FILE"
    echo "Please review the plan. You can edit it in your preferred editor."
    read -p "Do you want to [c]ontinue with the plan, [e]dit it, or [a]bort the process? " choice

    case "$choice" in
        c|C )
            echo "Plan approved. Continuing execution..."
            # Placeholder for the next step in the workflow
            # For example: ./execute_plan.sh "$TMP_PLAN_FILE"
            break
            ;;
        e|E )
            # Open the file with the default editor, fallback to nano or vi
            if [ -n "$EDITOR" ]; then
                $EDITOR "$TMP_PLAN_FILE"
            elif command -v nano &> /dev/null; then
                nano "$TMP_PLAN_FILE"
            elif command -v vi &> /dev/null; then
                vi "$TMP_PLAN_FILE"
            else
                echo "No suitable editor found. Please set the \$EDITOR environment variable."
                echo "Aborting."
                exit 1
            fi
            echo "File edited. Please review again."
            ;;
        a|A )
            echo "Operation aborted by the user."
            exit 0
            ;;
        * )
            echo "Invalid option. Please enter 'c', 'e', or 'a'."
            ;;
    esac
done

echo "Workflow finished."
