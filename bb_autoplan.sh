#!/bin/bash

# Blackbox Autoplan Script

# Default values
EXCLUDE_PATTERNS=""
TASK=""

# --- Helper Functions ---

# Function to display help message
show_help() {
  echo "Usage: ./bb_autoplan.sh [OPTIONS] <task_description>"
  echo ""
  echo "Generates a development plan using Blackbox AI based on your task and codebase."
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message and exit."
  echo "  --exclude <patterns> Comma-separated list of file/directory patterns to exclude."
  echo "                      Example: --exclude \"dist,node_modules,*.log\""
  echo ""
  echo "Arguments:"
  echo "  <task_description> A description of the task to be planned."
}

# --- Argument Parsing ---

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    --exclude)
      EXCLUDE_PATTERNS="$2"
      shift # past argument
      shift # past value
      ;;
    *)    # A non-option argument is the task description
      if [ -z "$TASK" ]; then
        TASK="$1"
        shift # past argument
      else
        # Handle case where task description might have spaces and is not the last argument
        # This is a simple approach; for more complex cases, other logic might be needed
        echo "Error: Multiple task descriptions provided or invalid argument '$1'."
        show_help
        exit 1
      fi
      ;;
  esac
done

# Function to build find command for excluding files
build_find_exclude_args() {
  local patterns=$1
  local find_args=()

  if [ -n "$patterns" ]; then
    IFS=',' read -ra ADDR <<< "$patterns"
    for pattern in "${ADDR[@]}"; do
      # Trim leading/trailing whitespace
      pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -n "$pattern" ]; then
        find_args+=(-not -path "./$pattern*")
      fi
    done
  fi

  echo "${find_args[@]}"
}

# --- Main Logic ---

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Check for BLACKBOX_API_KEY
if [ -z "$BLACKBOX_API_KEY" ]; then
  echo "Error: BLACKBOX_API_KEY environment variable is not set."
  exit 1
fi

# Check if a task description was provided
if [ -z "$TASK" ]; then
  echo "Error: No task description provided."
  show_help
  exit 1
fi

# Build exclude arguments for find
EXCLUDE_ARGS=$(build_find_exclude_args "$EXCLUDE_PATTERNS")

# Read system prompt
SYSTEM_PROMPT=$(cat prompts/blackbox_autoplan_system.md)

# --- Codebase Analysis ---

echo "Analyzing codebase..."

# Generate file tree
# We use find and sed to create a tree-like structure.
# The `find` command gets all files and dirs, respecting excludes.
# `sed` is used to add the tree-like formatting.
TREE_OUTPUT=$(find . -type d ${EXCLUDE_ARGS[@]} -print | sort -u | sed 's|[^/]*|--|g;s/--/ /g;s/--/|/g' | sed 's/|/|--/g')
TREE_FILES=$(find . -type f ${EXCLUDE_ARGS[@]} -print | sort -u | sed 's|[^/]*|--|g;s/--/ /g;s/--/|/g' | sed 's/|/|--/g')


# --- Prompt Generation ---

# Generate KEYFILES section
KEYFILES_PROMPT=""
for file in $(find . -type f ${EXCLUDE_ARGS[@]}); do
  if [ -s "$file" ]; then # check if file is not empty
    KEYFILES_PROMPT+="
### KEYFILE: $file
\`\`\`
$(cat "$file")
\`\`\`
"
  fi
done

CONTEXT_PROMPT="
### TREE
\`\`\`
.
$TREE_OUTPUT
$TREE_FILES
\`\`\`

$KEYFILES_PROMPT
"

# Create user prompt
USER_PROMPT="Task: $TASK

Please provide a detailed plan and implementation for this task."

# Call API adapter
echo "Generating plan for: $TASK"

./adapters/blackbox_api_curl.sh "$SYSTEM_PROMPT
$CONTEXT_PROMPT
$USER_PROMPT"
