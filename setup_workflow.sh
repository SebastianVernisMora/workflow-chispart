#!/bin/bash

# Setup workflow script

echo "Setting up Blackbox Autoplan workflow..."

# Make scripts executable

chmod +x adapters/blackbox_api_curl.sh

chmod +x bb_autoplan.sh

chmod +x setup_workflow.sh

# Set permissions on .env

chmod 600 .env

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

echo "Setup complete!"

echo "Usage: ./bb_autoplan.sh \"Your task description here\""
