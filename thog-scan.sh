#!/bin/bash

# =============================================================================
# TruffleHog Pre-Commit Secret Scanner (Diff-Based)
# =============================================================================
# This script scans ONLY YOUR changes (diff lines), not full files:
# 1. Detects merge from main/master and skips scanning those commits
# 2. For self-commits, scans only the lines YOU added/modified
# 3. Pre-existing secrets in files won't trigger false positives
# =============================================================================

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
TRUFFLEHOG_LOG_DIR="$HOME/trufflehog_logs"
TRUFFLEHOG_RAW_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_raw_output.json"
TRUFFLEHOG_CSV_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_results.csv"
LOG_FILE="$TRUFFLEHOG_LOG_DIR/trufflehog_debug.log"
DIFF_FILES_DIR="$TRUFFLEHOG_LOG_DIR/diff_files"

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
USER_IDENTIFIER=$(git config user.email 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")

LOCAL_REPO_DIR="$HOME/.pre-commit-scripts"
EXCLUSION_FILE="exclusion_list.txt"
EXCLUSION_PATH="$LOCAL_REPO_DIR/$EXCLUSION_FILE"

COMMIT_STATUS="Success"
TRUFFLEHOG_FINDINGS=0

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Cleanup function
cleanup() {
    rm -rf "$DIFF_FILES_DIR" 2>/dev/null || true
    rm -f "$TRUFFLEHOG_RAW_RESULT" 2>/dev/null || true
}

# Log debug messages
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Google Form Submission Function
submit_to_google_form() {
    curl -s -m 15 -X POST -d \
    "entry.1616042941=$1&entry.1600342824=$2&entry.1072243270=$3&entry.1945687837=$4&entry.11844011=$5&entry.1576914356=$6&entry.832012544=$7" \
    "https://docs.google.com/forms/d/e/1FAIpQLScEm0PJWP_0WzU_l6tORaJMSUDwdXyUqp3-RyF-olzrZTsgyg/formResponse" > /dev/null 2>&1 || true
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

# Function to check if we're in a merge commit state
is_merge_commit() {
    local git_dir=$(git rev-parse --git-dir 2>/dev/null)
    [ -f "$git_dir/MERGE_HEAD" ]
}

# Function to get the merge source commit SHA
get_merge_source() {
    local git_dir=$(git rev-parse --git-dir 2>/dev/null)
    if [ -f "$git_dir/MERGE_HEAD" ]; then
        cat "$git_dir/MERGE_HEAD" 2>/dev/null | head -n1
    fi
}

# Function to check if a commit is in main/master branch
is_main_or_master() {
    local merge_sha="$1"
    [ -z "$merge_sha" ] && return 1
    
    local default_branch=""
    
    # Check for origin/main first (most common in remote workflows)
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        default_branch="origin/main"
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then
        default_branch="origin/master"
    elif git rev-parse --verify main >/dev/null 2>&1; then
        default_branch="main"
    elif git rev-parse --verify master >/dev/null 2>&1; then
        default_branch="master"
    else
        return 1
    fi
    
    # Check if merge commit is the same as the tip of main/master
    local branch_tip=$(git rev-parse "$default_branch" 2>/dev/null)
    if [ "$merge_sha" = "$branch_tip" ]; then
        log_debug "Merge SHA matches $default_branch tip"
        return 0
    fi
    
    # Check if merge commit is in the main/master branch history
    if git merge-base --is-ancestor "$merge_sha" "$default_branch" 2>/dev/null; then
        log_debug "Merge SHA is ancestor of $default_branch"
        return 0
    fi
    
    # Additional check: verify the commit is reachable from main/master
    if git branch --contains "$merge_sha" 2>/dev/null | grep -qE "(^|\s)($default_branch|main|master)(\s|$)"; then
        return 0
    fi
    
    return 1
}

# Function to check if there are staged changes beyond the merge
has_additional_staged_changes() {
    local merge_sha="$1"
    [ -z "$merge_sha" ] && return 1
    
    local staged_diff=$(git diff --cached "$merge_sha" --name-only 2>/dev/null)
    [ -n "$staged_diff" ] && return 0
    
    return 1
}

# Function to get list of files with additional staged changes
get_additional_files() {
    local merge_sha="$1"
    if [ -n "$merge_sha" ]; then
        git diff --cached "$merge_sha" --name-only --diff-filter=ACMR 2>/dev/null
    fi
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

# Ensure the log directory exists
mkdir -p "$TRUFFLEHOG_LOG_DIR"
log_debug "=== Starting pre-commit scan ==="

# Check for required files
[ ! -f "$EXCLUSION_PATH" ] && { echo "Error: Exclusion list not found at $EXCLUSION_PATH"; exit 1; }

# Check if the OS is Darwin (macOS)
osname=$(uname)
if [ "$osname" != "Darwin" ]; then
    echo "Operating system is not macOS (Darwin). Skipping pre-commit checks."
    exit 0
fi

# Check for internet connection
if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "No internet connection detected. Skipping pre-commit checks."
    exit 0
fi

# Check if trufflehog is installed
if ! command -v trufflehog &>/dev/null; then
    echo "🚨 Trufflehog not found. 🔧 Setting up secret scanning locally by installing Trufflehog with Homebrew 🍺.
✨ This is a one-time setup, please do not cancel... ⏳"
    if command -v brew &>/dev/null; then
        brew install trufflehog || { echo "Failed to install Trufflehog. Please install it manually."; exit 1; }
    else
        echo "Homebrew is not installed. Please install Homebrew first."; exit 1;
    fi
fi

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "jq not found. Installing via brew..."
    if command -v brew &>/dev/null; then
        brew install jq || { echo "Failed to install jq. Please install it manually."; exit 1; }
    else
        echo "\x1B[1;31mHomebrew is not installed. Please visit https://brew.sh/ for installation instructions.\x1B[0m"; exit 1;
    fi
fi

# =============================================================================
# MERGE DETECTION LOGIC
# =============================================================================

START_TIME=$(date +%s)
MERGE_SHA=""
SKIP_SCAN=false
SCAN_ADDITIONAL_ONLY=false
FILES_TO_SCAN=""

if is_merge_commit; then
    MERGE_SHA=$(get_merge_source)
    log_debug "Detected merge commit. MERGE_SHA: $MERGE_SHA"
    
    if [ -n "$MERGE_SHA" ] && is_main_or_master "$MERGE_SHA"; then
        log_debug "Merge is from main/master"
        
        if has_additional_staged_changes "$MERGE_SHA"; then
            # Merge from main WITH additional changes - scan only additional files
            SCAN_ADDITIONAL_ONLY=true
            FILES_TO_SCAN=$(get_additional_files "$MERGE_SHA")
            echo "🔍 Merge from main/master detected with additional changes."
            echo "   Scanning only your additional staged files..."
            log_debug "Additional files to scan: $FILES_TO_SCAN"
        else
            # Pure merge from main - skip scan entirely
            SKIP_SCAN=true
            echo "⏭️  Skipping scan: Merge from main/master (already scanned remotely)"
            echo "   No additional staged changes detected."
            log_debug "Pure merge - skipping scan"
        fi
    fi
fi

# Fast path: Skip scan for pure merges from main/master
if [ "$SKIP_SCAN" = true ]; then
    END_TIME=$(date +%s)
    RUNTIME=$((END_TIME - START_TIME))
    RUNTIME=$(echo "$RUNTIME" | xargs)
    
    submit_to_google_form "$TIMESTAMP" "$REPO_NAME" "$USER_IDENTIFIER" "$RUNTIME" "0" "0" "Skipped"
    
    echo "✅ Scan skipped (merge from main/master)"
    echo "Script runtime: $RUNTIME seconds."
    exit 0
fi

# =============================================================================
# DIFF-BASED SCANNING LOGIC
# =============================================================================

# Get list of files to scan
if [ "$SCAN_ADDITIONAL_ONLY" = true ]; then
    # Already have FILES_TO_SCAN from additional files check
    :
else
    # Get all staged files (added, copied, modified, renamed - not deleted)
    FILES_TO_SCAN=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
fi

if [ -z "$FILES_TO_SCAN" ]; then
    echo "✅ No staged files to scan. Passing the commit."
    exit 0
fi

# Clean up and create temp directory for diff files
cleanup
mkdir -p "$DIFF_FILES_DIR"

# Extract ONLY the added/modified lines (diff) from each file
# This is the key: we scan only YOUR changes, not full file content
echo "$FILES_TO_SCAN" | while IFS= read -r file; do
    [ -z "$file" ] && continue
    
    # Create directory structure
    dir=$(dirname "$file")
    mkdir -p "$DIFF_FILES_DIR/$dir"
    
    # Extract ONLY the lines that were ADDED (start with +)
    if [ "$SCAN_ADDITIONAL_ONLY" = true ] && [ -n "$MERGE_SHA" ]; then
        # For merge with additional changes, diff against merge SHA
        git diff --cached "$MERGE_SHA" -U0 -- "$file" 2>/dev/null | \
            grep "^+" | \
            grep -v "^+++" | \
            sed 's/^+//' > "$DIFF_FILES_DIR/$file" 2>/dev/null || true
    else
        # For regular commits, diff against HEAD
        git diff --cached -U0 -- "$file" 2>/dev/null | \
            grep "^+" | \
            grep -v "^+++" | \
            sed 's/^+//' > "$DIFF_FILES_DIR/$file" 2>/dev/null || true
    fi
    
    log_debug "Extracted diff for: $file"
done

# Count files with actual content to scan
FILES_WITH_DIFF=$(find "$DIFF_FILES_DIR" -type f -size +0 2>/dev/null | wc -l | xargs)

if [ "$FILES_WITH_DIFF" -eq 0 ]; then
    echo "✅ No new content to scan (only deletions or empty changes). Passing the commit."
    cleanup
    exit 0
fi

# Count lines of code in diffs
LINES_OF_CODE_SCANNED=$(find "$DIFF_FILES_DIR" -type f -exec cat {} \; 2>/dev/null | wc -l | xargs)
LINES_OF_CODE_SCANNED=${LINES_OF_CODE_SCANNED:-0}

echo "📁 Scanning $FILES_WITH_DIFF file(s) ($LINES_OF_CODE_SCANNED lines of your changes)..."

# Run TruffleHog on the diff files using FILESYSTEM mode
(trufflehog filesystem "$DIFF_FILES_DIR" \
    --json \
    --no-update \
    --concurrency=5 \
    > "$TRUFFLEHOG_RAW_RESULT" 2>> "$LOG_FILE") &

SCAN_PID=$!
dots_animation "$SCAN_PID"
wait "$SCAN_PID" || true

# =============================================================================
# PROCESS RESULTS
# =============================================================================

if [ -s "$TRUFFLEHOG_RAW_RESULT" ]; then
    # Parse results and create CSV (using filesystem format)
    echo "file,detector_name,raw,redacted,line" > "$TRUFFLEHOG_CSV_RESULT"
    
    jq -r --arg diff_dir "$DIFF_FILES_DIR/" '
        select(.SourceMetadata != null) | 
        [
            (.SourceMetadata.Data.Filesystem.file // "unknown" | gsub($diff_dir; "")),
            .DetectorName,
            .Raw,
            .Redacted,
            (.SourceMetadata.Data.Filesystem.line // "N/A")
        ] | @csv
    ' "$TRUFFLEHOG_RAW_RESULT" >> "$TRUFFLEHOG_CSV_RESULT" 2>/dev/null || true

    TRUFFLEHOG_FINDINGS=$(jq -s 'map(select(.SourceMetadata != null)) | length' "$TRUFFLEHOG_RAW_RESULT" 2>/dev/null || echo "0")
    TRUFFLEHOG_FINDINGS=$(echo "$TRUFFLEHOG_FINDINGS" | xargs)

    if [ "$TRUFFLEHOG_FINDINGS" -gt 0 ]; then
        COMMIT_STATUS="Failed"
        
        echo ""
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║  ❌ SECRETS DETECTED IN YOUR CHANGES ❌                             ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  Found: $TRUFFLEHOG_FINDINGS potential secret(s) in your diff                    ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  📄 Details: $TRUFFLEHOG_CSV_RESULT"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  🔧 How to fix:                                                    ║"
        echo "║  1. Remove the secret from your code                               ║"
        echo "║  2. Use environment variables or a secrets manager                 ║"
        echo "║  3. See: https://rippling.atlassian.net/wiki/x/BIAhMgE             ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        echo "📍 Files with detected secrets:"
        jq -r --arg diff_dir "$DIFF_FILES_DIR/" '
            select(.SourceMetadata != null) | 
            "   • " + (.SourceMetadata.Data.Filesystem.file // "unknown" | gsub($diff_dir; "")) + 
            " [" + .DetectorName + "]"
        ' "$TRUFFLEHOG_RAW_RESULT" 2>/dev/null | sort -u
        echo ""
    else
        echo "✅ 🔒 No secrets detected by Trufflehog 🔒. Passing the commit ✅"
        rm -f "$TRUFFLEHOG_CSV_RESULT" "$TRUFFLEHOG_RAW_RESULT"
    fi
else
    echo "✅ 🔒 No secrets detected by Trufflehog 🔒. Passing the commit ✅"
    TRUFFLEHOG_FINDINGS=0
    rm -f "$TRUFFLEHOG_CSV_RESULT" "$TRUFFLEHOG_RAW_RESULT"
fi

# Cleanup temp files
cleanup

# =============================================================================
# METRICS & SUMMARY
# =============================================================================

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))
RUNTIME=$(echo "$RUNTIME" | xargs)

# Submit metrics
submit_to_google_form "$TIMESTAMP" "$REPO_NAME" "$USER_IDENTIFIER" "$RUNTIME" "$TRUFFLEHOG_FINDINGS" "$LINES_OF_CODE_SCANNED" "$COMMIT_STATUS"

# Final message
echo "Script runtime: $RUNTIME seconds."
echo "Total secrets discovered: $TRUFFLEHOG_FINDINGS"
echo "Total lines scanned: $LINES_OF_CODE_SCANNED"
echo "Commit status: $COMMIT_STATUS"

if [ "$COMMIT_STATUS" = "Failed" ]; then
    exit 1
else
    exit 0
fi
