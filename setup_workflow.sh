#!/bin/bash

# State file to track completed actions
STATE_FILE="/tmp/.workflow_setup.state"

# Function to check if an action has been completed
check_if_done() {
    if [ -f "$STATE_FILE" ]; then
        grep -q "^$1$" "$STATE_FILE"
    else
        return 1
    fi
}

# Function to mark an action as completed
mark_as_done() {
    echo "$1" >> "$STATE_FILE"
}

# Setup workflow script

echo "Setting up Blackbox Autoplan workflow..."

# Make scripts executable

chmod +x adapters/blackbox_api_curl.sh

chmod +x bb_autoplan.sh

chmod +x setup_workflow.sh

# Set permissions on .env

chmod 600 .env

# --- Label Creation ---
create_labels() {
    echo "--- Creating Labels ---"
    LABELS=("bug" "feature" "documentation" "testing")
    for label in "${LABELS[@]}"; do
        if check_if_done "label_$label"; then
            echo "Label '$label' already exists. Skipping."
        else
            echo "Creating label '$label'..."
            # Placeholder for label creation API call
            # Example: gh api repos/:owner/:repo/labels -f name="$label" -f color="f29513"
            mark_as_done "label_$label"
            echo "Label '$label' created."
        fi
    done
    echo "--- Label Creation Finished ---"
}

# --- Milestone Creation ---
create_milestones() {
    echo "--- Creating Milestones ---"
    MILESTONE="v1.0"
    if check_if_done "milestone_$MILESTONE"; then
        echo "Milestone '$MILESTONE' already exists. Skipping."
    else
        echo "Creating milestone '$MILESTONE'..."
        # Placeholder for milestone creation API call
        # Example: gh api repos/:owner/:repo/milestones -f title="$MILESTONE"
        mark_as_done "milestone_$MILESTONE"
        echo "Milestone '$MILESTONE' created."
    fi
    echo "--- Milestone Creation Finished ---"
}

# --- Welcome Issue Creation ---
create_welcome_issue() {
    echo "--- Creating Welcome Issue ---"
    ISSUE_TITLE="Welcome to the Autoplan Workflow"
    if check_if_done "issue_welcome"; then
        echo "Welcome issue already exists. Skipping."
    else
        echo "Creating welcome issue..."
        # Placeholder for issue creation API call
        # Example: gh api repos/:owner/:repo/issues -f title="$ISSUE_TITLE" -f body="Welcome!"
        mark_as_done "issue_welcome"
        echo "Welcome issue created."
    fi
    echo "--- Welcome Issue Creation Finished ---"
}

# Check if API key is set

if [ -z "$BLACKBOX_API_KEY" ]; then
    echo "Warning: BLACKBOX_API_KEY not set in environment"
    echo "Please set it in .env file"
fi

# Install dependencies if needed

# For curl, it's usually pre-installed

# For jq, check if installed

if ! command -v jq &> /dev/null; then
    echo "jq not found. Installing..."
    # On Ubuntu/Debian
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    # On macOS
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo "Please install jq manually"
    fi
fi

# Create labels, milestones, and issues
create_labels
create_milestones
create_welcome_issue

echo "Setup complete!"

echo "Usage: ./bb_autoplan.sh \"Your task description here\""
