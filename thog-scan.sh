#!/bin/bash

# Exit on any error
set -e

# Configurable variables
TRUFFLEHOG_LOG_DIR="$HOME/trufflehog_logs"
TRUFFLEHOG_RAW_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_raw_output.json"
TRUFFLEHOG_CSV_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_results.csv"
LOG_FILE="$TRUFFLEHOG_LOG_DIR/trufflehog_debug.log"
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
USER_IDENTIFIER=$(git config user.email)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
LOCAL_REPO_DIR="$HOME/.pre-commit-scripts"
SCRIPT_NAME="secret-scan.sh"
EXCLUSION_FILE="exclusion_list.txt"
SCRIPT_PATH="$LOCAL_REPO_DIR/$SCRIPT_NAME"
EXCLUSION_PATH="$LOCAL_REPO_DIR/$EXCLUSION_FILE"
COMMIT_STATUS="Success"

# Check for required files
[ ! -f "$EXCLUSION_PATH" ] && { echo "Error: Exclusion list not found at $EXCLUSION_PATH"; exit 1; }

# Ensure the log directory exists
mkdir -p "$TRUFFLEHOG_LOG_DIR"

# Check if the OS is Darwin (macOS)
osname=$(uname)
if [ "$osname" != "Darwin" ]; then
    echo "Operating system is not macOS (Darwin). Skipping pre-commit checks."
    exit 0  # Exit successfully to pass the pre-commit hook
fi

# Check for internet connection
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    echo "No internet connection detected. Skipping pre-commit checks."
    exit 0  # Exit successfully to pass the pre-commit hook
fi

# Check if trufflehog is installed; if not, install using brew
if ! command -v trufflehog &>/dev/null; then
    echo "🚨 Trufflehog not found. 🔧 Setting up secret scanning locally by installing Trufflehog with Homebrew 🍺.
✨ This is a one-time setup, please do not cancel... ⏳"
    if command -v brew &>/dev/null; then
        brew install trufflehog || { echo "Failed to install Trufflehog. Please install it manually."; exit 1; }
    else
        echo "Homebrew is not installed. Please install Homebrew first."; exit 1;
    fi
fi

# Check if jq is installed; if not, install using brew
if ! command -v jq &>/dev/null; then
    echo "jq not found. Installing via brew..."
    if command -v brew &>/dev/null; then
        brew install jq || { echo "Failed to install jq. Please install it manually."; exit 1; }
    else
        echo "\x1B[1;31mHomebrew is not installed. Please visit https://brew.sh/ for installation instructions.\x1B[0m"; exit 1;
    fi
fi

# Google Form Submission Function
submit_to_google_form() {
    curl -s -m 15 -X POST -d \
    "entry.1616042941=$1&entry.1600342824=$2&entry.1072243270=$3&entry.1945687837=$4&entry.11844011=$5&entry.1576914356=$6&entry.832012544=$7" \
    "https://docs.google.com/forms/d/e/1FAIpQLScEm0PJWP_0WzU_l6tORaJMSUDwdXyUqp3-RyF-olzrZTsgyg/formResponse" > /dev/null 2>&1
}

# Function to show progress bar
dots_animation() {
    local pid=$1
    local delay=0.2
    local dots=0
    local max_dots=4

    while kill -0 "$pid" 2>/dev/null; do
        dots=$(( (dots + 1) % max_dots ))
        printf "\rRunning secret scan%s" "$(printf ".%.0s" $(seq 1 $dots))"
        sleep "$delay"
    done
    printf "\rRunning secret scan... Done!\n"
}

# Start time
START_TIME=$(date +%s)

# Check if this is the initial commit
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    # Not the initial commit, use --since-commit HEAD
    SINCE_COMMIT="--since-commit HEAD"
else
    # Initial commit, scan everything
    SINCE_COMMIT=""
fi

# Run Trufflehog with progress bar
(trufflehog git file://. $SINCE_COMMIT --branch "$BRANCH_NAME" --json --debug --concurrency=5 --no-update --no-verification --exclude-paths="$EXCLUSION_PATH" >"$TRUFFLEHOG_RAW_RESULT" 2>>"$LOG_FILE") &
SCAN_PID=$!

dots_animation "$SCAN_PID"
wait "$SCAN_PID"

# Calculate lines of code being scanned in staged changes
# For initial commit, count all staged files
if [ -z "$SINCE_COMMIT" ]; then
    LINES_OF_CODE_SCANNED=$(git diff --cached --numstat | awk '
        # Skip binary files (shown as "-" in numstat)
        $1 != "-" { 
            # Sum up only additions (first column)
            added += $1
        } 
        END { 
            # Print total, default to 0 if no changes
            print (added ? added : 0)
        }
    ')
else
    LINES_OF_CODE_SCANNED=$(git diff --cached --numstat | awk '
        # Skip binary files (shown as "-" in numstat)
        $1 != "-" { 
            # Sum up only additions (first column)
            added += $1
        } 
        END { 
            # Print total, default to 0 if no changes
            print (added ? added : 0)
        }
    ')
fi

# Ensure we have a valid number, default to 0 if empty or invalid
LINES_OF_CODE_SCANNED=${LINES_OF_CODE_SCANNED:-0}

# Trim any extra spaces in variables
LINES_OF_CODE_SCANNED=$(echo "$LINES_OF_CODE_SCANNED" | xargs)

# Check Trufflehog results
if [ -s "$TRUFFLEHOG_RAW_RESULT" ]; then
    echo "commit,file,repository,line,detector_name,raw,redacted" >"$TRUFFLEHOG_CSV_RESULT"
    jq -r '. | select(.SourceMetadata != null) | [.SourceMetadata.Data.Git.commit, .SourceMetadata.Data.Git.file, .SourceMetadata.Data.Git.repository, .SourceMetadata.Data.Git.line, .DetectorName, .Raw, .Redacted] | @csv' "$TRUFFLEHOG_RAW_RESULT" >>"$TRUFFLEHOG_CSV_RESULT"

    TRUFFLEHOG_FINDINGS=$(jq -r '. | select(.SourceMetadata != null) | .SourceMetadata.Data.Git.file' "$TRUFFLEHOG_RAW_RESULT" | wc -l)

    # Trim any extra spaces in variables
    TRUFFLEHOG_FINDINGS=$(echo "$TRUFFLEHOG_FINDINGS" | xargs)

    COMMIT_STATUS="Failed"
    echo "❌🔑🤫Secrets detected in the commit. Please review $TRUFFLEHOG_CSV_RESULT and address the issues before committing as described in https://rippling.atlassian.net/wiki/spaces/SECENG/pages/4687691780/Pre-commit+secret+scan+Shifting+Left+to+Enhance+Security+and+Code+Quality#How-Do-I-Resolve-a-Secret-in-Code-When-the-Hook-Finds-Something 🔑🤫❌."
else
    echo "✅ 🔒 No secrets detected by Trufflehog 🔒. Passing the commit ✅"
    TRUFFLEHOG_FINDINGS=0
    rm -f "$TRUFFLEHOG_CSV_RESULT" "$TRUFFLEHOG_RAW_RESULT"
fi

# End time and calculate runtime
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
RUNTIME=$(echo "$RUNTIME" | xargs)

# Try to submit metrics
submit_to_google_form "$TIMESTAMP" "$REPO_NAME" "$USER_IDENTIFIER" "$RUNTIME" "$TRUFFLEHOG_FINDINGS" "$LINES_OF_CODE_SCANNED" "$COMMIT_STATUS"

# Final message
echo "Script runtime: $RUNTIME seconds."
echo "Total secrets discovered: $TRUFFLEHOG_FINDINGS "
echo "Total lines scanned: $LINES_OF_CODE_SCANNED"
echo "Commit status: $COMMIT_STATUS"

if [ "$COMMIT_STATUS" = "Failed" ]; then
    exit 1
else
    exit 0
fi
