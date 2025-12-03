#!/bin/bash

# =============================================================================
# TruffleHog Pre-Commit Secret Scanner
# =============================================================================
# This script scans ONLY staged changes (not entire git history) to ensure:
# 1. Only YOUR commits are scanned (not commits from remote/main)
# 2. Fast execution - no scanning of unchanged files
# 3. Accurate detection - focused on what you're about to commit
# =============================================================================

# Exit on any error
set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
TRUFFLEHOG_LOG_DIR="$HOME/trufflehog_logs"
TRUFFLEHOG_RAW_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_raw_output.json"
TRUFFLEHOG_CSV_RESULT="$TRUFFLEHOG_LOG_DIR/trufflehog_results.csv"
LOG_FILE="$TRUFFLEHOG_LOG_DIR/trufflehog_debug.log"
STAGED_FILES_DIR="$TRUFFLEHOG_LOG_DIR/staged_files"

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
USER_IDENTIFIER=$(git config user.email 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")

# Local config paths
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
    rm -rf "$STAGED_FILES_DIR" 2>/dev/null || true
    rm -f "$TRUFFLEHOG_RAW_RESULT" 2>/dev/null || true
}

# Google Form Submission Function (for metrics)
submit_to_google_form() {
    curl -s -m 15 -X POST -d \
    "entry.1616042941=$1&entry.1600342824=$2&entry.1072243270=$3&entry.1945687837=$4&entry.11844011=$5&entry.1576914356=$6&entry.832012544=$7" \
    "https://docs.google.com/forms/d/e/1FAIpQLScEm0PJWP_0WzU_l6tORaJMSUDwdXyUqp3-RyF-olzrZTsgyg/formResponse" > /dev/null 2>&1 || true
}

# Progress animation
dots_animation() {
    local pid=$1
    local delay=0.2
    local dots=0
    local max_dots=4

    while kill -0 "$pid" 2>/dev/null; do
        dots=$(( (dots + 1) % max_dots ))
        printf "\r🔍 Scanning staged changes for secrets%s   " "$(printf ".%.0s" $(seq 1 $dots))"
        sleep "$delay"
    done
    printf "\r🔍 Scanning staged changes for secrets... Done!   \n"
}

# Check if a file should be excluded
should_exclude_file() {
    local file="$1"
    
    # If no exclusion file exists, don't exclude anything
    [ ! -f "$EXCLUSION_PATH" ] && return 1
    
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip empty lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
        
        # Check if file matches the pattern
        if [[ "$file" == $pattern ]] || [[ "$file" =~ $pattern ]]; then
            return 0  # Should exclude
        fi
    done < "$EXCLUSION_PATH"
    
    return 1  # Should not exclude
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

# Ensure log directory exists
mkdir -p "$TRUFFLEHOG_LOG_DIR"

# Check if the OS is Darwin (macOS)
osname=$(uname)
if [ "$osname" != "Darwin" ]; then
    echo "⚠️  Operating system is not macOS (Darwin). Skipping pre-commit checks."
    exit 0
fi

# Check for internet connection (with timeout)
if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "⚠️  No internet connection detected. Skipping pre-commit checks."
    exit 0
fi

# Check if trufflehog is installed
if ! command -v trufflehog &>/dev/null; then
    echo "🚨 Trufflehog not found. 🔧 Installing via Homebrew..."
    if command -v brew &>/dev/null; then
        brew install trufflehog || { echo "❌ Failed to install Trufflehog. Please install it manually."; exit 1; }
    else
        echo "❌ Homebrew is not installed. Please install Homebrew first: https://brew.sh/"
        exit 1
    fi
fi

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "🔧 jq not found. Installing via Homebrew..."
    if command -v brew &>/dev/null; then
        brew install jq || { echo "❌ Failed to install jq. Please install it manually."; exit 1; }
    else
        echo "❌ Homebrew is not installed. Please install Homebrew first: https://brew.sh/"
        exit 1
    fi
fi

# =============================================================================
# MAIN SCANNING LOGIC - SCAN ONLY STAGED CHANGES
# =============================================================================

START_TIME=$(date +%s)

# Get list of staged files (only added, modified, or copied - not deleted)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)

if [ -z "$STAGED_FILES" ]; then
    echo "✅ No staged files to scan. Passing the commit."
    exit 0
fi

# Count lines of code being staged
LINES_OF_CODE_SCANNED=$(git diff --cached --numstat 2>/dev/null | awk '
    $1 != "-" { added += $1 }
    END { print (added ? added : 0) }
')
LINES_OF_CODE_SCANNED=${LINES_OF_CODE_SCANNED:-0}

# Create temp directory for staged file contents
cleanup  # Clean any previous run
mkdir -p "$STAGED_FILES_DIR"

# Export staged file contents (what's actually being committed)
echo "$STAGED_FILES" | while IFS= read -r file; do
    # Skip if file should be excluded
    if should_exclude_file "$file"; then
        echo "  ⏭️  Skipping excluded file: $file" >> "$LOG_FILE"
        continue
    fi
    
    # Create directory structure
    dir=$(dirname "$file")
    mkdir -p "$STAGED_FILES_DIR/$dir"
    
    # Export the staged version of the file (not the working directory version!)
    git show ":$file" > "$STAGED_FILES_DIR/$file" 2>/dev/null || true
done

# Count files to scan
FILES_TO_SCAN=$(find "$STAGED_FILES_DIR" -type f 2>/dev/null | wc -l | xargs)

if [ "$FILES_TO_SCAN" -eq 0 ]; then
    echo "✅ No files to scan after exclusions. Passing the commit."
    cleanup
    exit 0
fi

echo "📁 Scanning $FILES_TO_SCAN staged file(s)..."

# Run TruffleHog on staged files using FILESYSTEM mode (not git mode!)
# This ensures we ONLY scan what's being committed
(trufflehog filesystem "$STAGED_FILES_DIR" \
    --json \
    --no-update \
    --no-verification \
    --concurrency=5 \
    > "$TRUFFLEHOG_RAW_RESULT" 2>> "$LOG_FILE") &

SCAN_PID=$!
dots_animation "$SCAN_PID"
wait "$SCAN_PID" || true

# =============================================================================
# PROCESS RESULTS
# =============================================================================

if [ -s "$TRUFFLEHOG_RAW_RESULT" ]; then
    # Parse results and create CSV
    echo "file,detector_name,raw,redacted,line" > "$TRUFFLEHOG_CSV_RESULT"
    
    # Process findings and map back to original file paths
    jq -r --arg staged_dir "$STAGED_FILES_DIR/" '
        select(.SourceMetadata != null) | 
        [
            (.SourceMetadata.Data.Filesystem.file // "unknown" | gsub($staged_dir; "")),
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
        echo "║  ❌ SECRETS DETECTED IN STAGED CHANGES ❌                           ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  Found: $TRUFFLEHOG_FINDINGS potential secret(s)                              ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  📄 Details saved to:                                              ║"
        echo "║     $TRUFFLEHOG_CSV_RESULT"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  🔧 How to fix:                                                    ║"
        echo "║  1. Remove the secret from your code                               ║"
        echo "║  2. Use environment variables or a secrets manager                 ║"
        echo "║  3. If false positive, add pattern to exclusion_list.txt           ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Show which files have secrets
        echo "📍 Files with detected secrets:"
        jq -r --arg staged_dir "$STAGED_FILES_DIR/" '
            select(.SourceMetadata != null) | 
            "   • " + (.SourceMetadata.Data.Filesystem.file // "unknown" | gsub($staged_dir; "")) + 
            " [" + .DetectorName + "]"
        ' "$TRUFFLEHOG_RAW_RESULT" 2>/dev/null | sort -u
        echo ""
    else
        echo "✅ 🔒 No secrets detected in staged changes. Passing the commit ✅"
        rm -f "$TRUFFLEHOG_CSV_RESULT" "$TRUFFLEHOG_RAW_RESULT"
    fi
else
    echo "✅ 🔒 No secrets detected in staged changes. Passing the commit ✅"
    TRUFFLEHOG_FINDINGS=0
fi

# Cleanup temp files
cleanup

# =============================================================================
# METRICS & SUMMARY
# =============================================================================

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

# Submit metrics (async, don't block)
submit_to_google_form "$TIMESTAMP" "$REPO_NAME" "$USER_IDENTIFIER" "$RUNTIME" "$TRUFFLEHOG_FINDINGS" "$LINES_OF_CODE_SCANNED" "$COMMIT_STATUS" &

# Final summary
echo "────────────────────────────────────────"
echo "⏱️  Runtime: ${RUNTIME}s | 📊 Lines scanned: $LINES_OF_CODE_SCANNED | 🔍 Secrets found: $TRUFFLEHOG_FINDINGS"
echo "────────────────────────────────────────"

if [ "$COMMIT_STATUS" = "Failed" ]; then
    exit 1
else
    exit 0
fi
