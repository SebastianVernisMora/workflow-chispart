#!/bin/bash
set -euo pipefail

# Blackbox Autoplan Script

# Default values
EXCLUDE_PATTERNS=""
TASK=""

# --- Helper Functions ---

# Function to display help message
show_help() {
  cat << EOF
Usage: ./bb_autoplan.sh [OPTIONS] <task_description>

Generates a development plan using Blackbox AI based on your task and codebase.

Options:
  -h, --help            Show this help message and exit.
  --exclude <patterns>  Comma-separated list of file/directory patterns to exclude.
                        Example: --exclude "dist,node_modules,*.log"

Arguments:
  <task_description>    A description of the task to be planned.
EOF
}

# Function to build find command exclude arguments with pruning
build_find_exclude_args() {
  local patterns=$1
  local find_args=()

  if [ -n "$patterns" ]; then
    IFS=',' read -ra ADDR <<< "$patterns"
    for pattern in "${ADDR[@]}"; do
      # Trim leading/trailing whitespace
      pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -n "$pattern" ]; then
        # Prune matching paths (directories or files)
        find_args+=(-path "./$pattern" -prune -o)
      fi
    done
  fi

  echo "${find_args[@]}"
}

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    --exclude)
      if [[ $# -lt 2 ]]; then
        echo "Error: --exclude requires a comma-separated argument."
        exit 1
      fi
      EXCLUDE_PATTERNS="$2"
      shift 2
      ;;
    *)
      # Append all remaining args as part of the task description
      TASK="$TASK $1"
      shift
      ;;
  esac
done

# Trim leading/trailing whitespace from TASK
TASK=$(echo "$TASK" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# --- Load environment variables ---

if [ -f .env ]; then
  # shellcheck source=/dev/null
  source .env
fi

# --- Validate environment and inputs ---

if [ -z "${BLACKBOX_API_KEY:-}" ]; then
  echo "Error: BLACKBOX_API_KEY environment variable is not set."
  exit 1
fi

if [ -z "$TASK" ]; then
  echo "Error: No task description provided."
  show_help
  exit 1
fi

# --- Build exclude arguments for find ---

EXCLUDE_ARGS=()
if [ -n "$EXCLUDE_PATTERNS" ]; then
  read -r -a EXCLUDE_ARGS <<< "$(build_find_exclude_args "$EXCLUDE_PATTERNS")"
fi

# --- Read system prompt ---

if [ ! -f prompts/blackbox_autoplan_system.md ]; then
  echo "Error: System prompt file 'prompts/blackbox_autoplan_system.md' not found."
  exit 1
fi

SYSTEM_PROMPT=$(cat prompts/blackbox_autoplan_system.md)

# --- Codebase Analysis ---

echo "Analyzing codebase..."

# Generate tree output (try tree command if available)
if command -v tree &> /dev/null; then
  if [ -n "$EXCLUDE_PATTERNS" ]; then
    TREE_OUTPUT=$(tree -a -I "$EXCLUDE_PATTERNS" -L 3)
  else
    TREE_OUTPUT=$(tree -a -L 3)
  fi
else
  # fallback to find with excludes
  TREE_OUTPUT=$(find . "${EXCLUDE_ARGS[@]}" -print | sed 's|[^/]*|--|g;s/--/ /g;s/--/|/g' | sed 's/|/|--/g')
fi

# Generate KEYFILES section
KEYFILES_PROMPT=""
while IFS= read -r file; do
  if [ -s "$file" ]; then
    KEYFILES_PROMPT+="
### KEYFILE: $file
\`\`\`
$(cat "$file")
\`\`\`
"
  fi
done < <(find . "${EXCLUDE_ARGS[@]}" -type f -print)

CONTEXT_PROMPT="
### TREE
\`\`\`
$TREE_OUTPUT
\`\`\`

$KEYFILES_PROMPT
"

# --- Create user prompt ---

USER_PROMPT="Task: $TASK

Please provide a detailed plan and implementation for this task."

# --- Call API adapter ---

echo "Generating plan for: $TASK"

AI_PLAN=$(./adapters/blackbox_api_curl.sh "$SYSTEM_PROMPT
$CONTEXT_PROMPT
$USER_PROMPT")

# Save plan to a temporary markdown file
TMP_PLAN_FILE="/tmp/propuesta_plan.md"
echo "$AI_PLAN" > "$TMP_PLAN_FILE"

# --- Human-in-the-Loop Validation ---

while true; do
    echo ""
    echo "AI plan proposal has been saved to: $TMP_PLAN_FILE"
    echo "Please review the plan. You can edit it in your preferred editor."
    read -rp "Do you want to [c]ontinue with the plan, [e]dit it, or [a]bort the process? " choice

    case "$choice" in
        c|C )
            echo "Plan approved. Continuing execution..."
            # Placeholder for the next step in the workflow
            # For example: ./execute_plan.sh "$TMP_PLAN_FILE"
            break
            ;;
        e|E )
            # Open the file with the default editor, fallback to nano or vi
            if [ -n "${EDITOR:-}" ]; then
                "$EDITOR" "$TMP_PLAN_FILE"
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