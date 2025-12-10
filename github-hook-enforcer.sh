#!/bin/bash

# Configuration
WRAPPER_SCRIPT="wrapper-secret-scan.sh"
WRAPPER_PATH="$HOME/.pre-commit-scripts/$WRAPPER_SCRIPT"
LOGS_DIR="$HOME/.logs/github_hook_enforcer"
BACKUP_DIR="$LOGS_DIR/backups"
LOG_FILE="$LOGS_DIR/enforcer.log"
OUTPUT_FILE="$LOGS_DIR/hook_enforcement_report.csv"

# Ensure directories exist
mkdir -p "$LOGS_DIR"
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $message" >> "$LOG_FILE"
    echo ">>> $message"
}

# Function to check if secret scan exists in file
has_secret_scan() {
    local file="$1"
    grep -q "bash.*$WRAPPER_PATH" "$file" 2>/dev/null
}

# Function to get safe filename from repo path
get_safe_repo_name() {
    local repo_path="$1"
    # Get the last directory name from the path and replace special characters with underscore
    echo "$(basename "$repo_path" | sed 's/[^a-zA-Z0-9]/_/g')"
}

# Function to append secret scan to file
append_secret_scan() {
    local file="$1"
    local framework="$2"
    local repo_path="$3"
    
    echo "  - Processing $framework hook file: $file"
    
    # If file doesn't exist, create it with execute permissions
    if [ ! -f "$file" ]; then
        echo "    - Creating new pre-commit hook file..."
        touch "$file" 2>/dev/null || {
            log "Failed to create $file"
            return 1
        }
        chmod +x "$file" 2>/dev/null || {
            log "Failed to make $file executable"
            rm "$file" 2>/dev/null
            return 1
        }
        echo "#!/bin/bash" > "$file" || {
            log "Failed to initialize $file"
            rm "$file" 2>/dev/null
            return 1
        }
        # Add newline after shebang
        echo "" >> "$file"
        log "Created new pre-commit hook file: $file"
    else
        echo "    - Backing up existing hook file..."
        # Create timestamped backup with repo name
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local repo_name=$(get_safe_repo_name "$repo_path")
        local backup_path="$BACKUP_DIR/pre-commit_${repo_name}_${framework}_${timestamp}.bak"
        
        cp "$file" "$backup_path" 2>/dev/null || {
            log "Failed to create backup at $backup_path"
            return 1
        }
        log "Created backup at: $backup_path"

        # Ensure existing file has executable permissions
        if [ ! -x "$file" ]; then
            chmod +x "$file" 2>/dev/null || {
                log "Failed to make existing file $file executable"
                return 1
            }
            log "Added executable permissions to existing hook: $file"
        fi
        
        # Check if file ends with newline
        if [ -s "$file" ]; then
            if [ "$(tail -c1 "$file" | xxd -p)" != "0a" ]; then
                echo "" >> "$file"
                log "Added missing newline to end of file"
            fi
        fi
    fi
    
    # Append secret scan with proper line ending
    echo "    - Adding secret scan hook..."
    echo "bash $WRAPPER_PATH" >> "$file" || {
        log "Failed to append to $file"
        if [ -f "$backup_path" ]; then
            echo "    - Restoring from backup due to failure..."
            cp "$backup_path" "$file" || log "Failed to restore from backup"
        fi
        return 1
    }
    
    # Ensure file ends with newline
    echo "" >> "$file"
    
    log "Added secret scan to $file ($framework)"
    echo "    - Successfully processed hook file"
    return 0
}

# Function to process repository
process_repo() {
    local repo="$1"
    
    # Skip if not a git repository
    [ ! -d "$repo/.git" ] && return
    
    echo "  Checking repository type..."
    # Check for Husky
    if [ -d "$repo/.husky" ]; then
        echo "  - Found Husky configuration"
        local husky_hook="$repo/.husky/pre-commit"
        if ! has_secret_scan "$husky_hook"; then
            append_secret_scan "$husky_hook" "husky" "$repo"
        fi
        return
    fi
    
    # Check for pre-commit framework
    if [ -f "$repo/.pre-commit-config.yaml" ]; then
        echo "  - Found pre-commit framework configuration"
        local precommit_hook="$repo/.git/hooks/pre-commit"
        if ! has_secret_scan "$precommit_hook"; then
            append_secret_scan "$precommit_hook" "pre-commit" "$repo"
        fi
        return
    fi
    
    # No framework case (native)
    echo "  - Using native Git hooks"
    local native_hook="$repo/.git/hooks/pre-commit"
    if ! has_secret_scan "$native_hook"; then
        append_secret_scan "$native_hook" "no-framework" "$repo"
    fi
}

# Function to check hook type and secret presence
check_and_process_repo() {
    local repo_dir="$1"
    local has_husky="No"
    local has_pre_commit="No"
    local has_native="No"
    local has_secret="No"

    echo "\nAnalyzing repository: $repo_dir"
    echo "Checking for existing hook configurations..."

    # Check for husky
    if [ -f "$repo_dir/.husky/pre-commit" ]; then
        has_husky="Yes"
        echo "  - Found Husky pre-commit hook"
        if has_secret_scan "$repo_dir/.husky/pre-commit"; then
            has_secret="Yes"
            echo "    - Secret scan already exists"
        fi
    fi

    # Check for pre-commit config
    if [ -f "$repo_dir/.pre-commit-config.yaml" ]; then
        has_pre_commit="Yes"
        echo "  - Found pre-commit framework configuration"
        if [ -f "$repo_dir/.git/hooks/pre-commit" ] && has_secret_scan "$repo_dir/.git/hooks/pre-commit"; then
            has_secret="Yes"
            echo "    - Secret scan already exists"
        fi
    fi

    # Check for native hooks
    if [ "$has_husky" = "No" ] && [ "$has_pre_commit" = "No" ]; then
        if [ -f "$repo_dir/.git/hooks/pre-commit" ]; then
            has_native="Yes"
            echo "  - Found native Git pre-commit hook"
            if has_secret_scan "$repo_dir/.git/hooks/pre-commit"; then
                has_secret="Yes"
                echo "    - Secret scan already exists"
            fi
        fi
    fi

    # Log the status
    echo "$repo_dir,$has_husky,$has_pre_commit,$has_native,$has_secret" >> "$OUTPUT_FILE"

    # Process repo if no secret scan is found
    if [ "$has_secret" = "No" ]; then
        echo "\nNo secret scan found - adding hook..."
        log "Processing repository $repo_dir - no secret scan found"
        process_repo "$repo_dir"
    else
        echo "\nSecret scan already exists - skipping..."
        log "Skipping repository $repo_dir - secret scan already exists"
    fi
    
    echo "Repository processing complete\n"
}

# Main execution
echo "=== GitHub Hook Enforcer ==="
echo "Starting enforcement process..."
START_TIME=$(date +%s)
log "Starting GitHub hook enforcement"

echo "Scanning for GitHub repositories..."

# Initialize output file with timestamp
echo "# Scan performed on: $(date '+%Y-%m-%d %H:%M:%S')" > "$OUTPUT_FILE"
echo "repo_name,husky,pre_commit_config,native,contains_secret" >> "$OUTPUT_FILE"

# Find all GitHub repositories and process them
find ~ -name ".git" -type d 2>/dev/null | while read -r git_dir; do
    repo_dir="${git_dir%/.git}"
    
    # Check if it's a GitHub repository
    if grep -q "github.com" "$git_dir/config" 2>/dev/null; then
        log "Found GitHub repository: $repo_dir"
        check_and_process_repo "$repo_dir"
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Add summary to the report
echo "" >> "$OUTPUT_FILE"
echo "# Summary" >> "$OUTPUT_FILE"
echo "# Total repositories processed: $(grep -v '^#' "$OUTPUT_FILE" | grep -c '^')" >> "$OUTPUT_FILE"
echo "# Scan duration: $(printf '%02d:%02d' $((ELAPSED/60)) $((ELAPSED%60))) minutes" >> "$OUTPUT_FILE"

echo "\n=== Enforcement Complete ==="
log "Completed hook enforcement in $(printf '%02d:%02d' $((ELAPSED/60)) $((ELAPSED%60))) minutes"
echo "Time taken: $(printf '%02d:%02d' $((ELAPSED/60)) $((ELAPSED%60))) minutes"
echo "Results directory: $LOGS_DIR"
echo "  - Report: $(basename "$OUTPUT_FILE")"
echo "  - Logs: $(basename "$LOG_FILE")" 