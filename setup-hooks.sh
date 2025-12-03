#!/bin/bash

# =============================================================================
# TruffleHog Pre-Commit Hook Setup Script
# =============================================================================
# Run this script once to set up the pre-commit hook in your repository
# Usage: ./setup-hooks.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
PRE_COMMIT_SCRIPTS_DIR="$HOME/.pre-commit-scripts"

echo "🔧 Setting up TruffleHog pre-commit hook..."
echo ""

# Check if we're in a git repository
if [ -z "$REPO_ROOT" ]; then
    echo "❌ Error: Not in a git repository. Please run this from within a git repo."
    exit 1
fi

# Create the pre-commit scripts directory
mkdir -p "$PRE_COMMIT_SCRIPTS_DIR"

# Copy the scan script to the global location
cp "$SCRIPT_DIR/thog-scan.sh" "$PRE_COMMIT_SCRIPTS_DIR/secret-scan.sh"
chmod +x "$PRE_COMMIT_SCRIPTS_DIR/secret-scan.sh"
echo "✅ Copied secret-scan.sh to $PRE_COMMIT_SCRIPTS_DIR/"

# Create exclusion list if it doesn't exist
if [ ! -f "$PRE_COMMIT_SCRIPTS_DIR/exclusion_list.txt" ]; then
    cat > "$PRE_COMMIT_SCRIPTS_DIR/exclusion_list.txt" << 'EOF'
# =============================================================================
# TruffleHog Exclusion List
# =============================================================================
# Add file patterns to exclude from secret scanning
# One pattern per line. Lines starting with # are comments.
#
# Examples:
#   *.test.js           - Exclude all test files
#   package-lock.json   - Exclude package lock
#   vendor/*            - Exclude vendor directory
#   *.md                - Exclude markdown files
# =============================================================================

# Package lock files (often contain false positives)
package-lock.json
yarn.lock
pnpm-lock.yaml
Gemfile.lock
poetry.lock
Cargo.lock
go.sum

# Test fixtures and mock data
**/test/**
**/tests/**
**/__tests__/**
**/fixtures/**
**/mocks/**
*.test.*
*.spec.*

# Documentation
*.md
*.rst
docs/*

# Build artifacts
dist/*
build/*
*.min.js
*.bundle.js

# IDE and editor files
.idea/*
.vscode/*
*.swp

# Common false positive patterns
# (Add your own patterns below)

EOF
    echo "✅ Created exclusion_list.txt at $PRE_COMMIT_SCRIPTS_DIR/"
else
    echo "ℹ️  Exclusion list already exists at $PRE_COMMIT_SCRIPTS_DIR/exclusion_list.txt"
fi

# Create the pre-commit hook
PRE_COMMIT_HOOK="$REPO_ROOT/.git/hooks/pre-commit"

cat > "$PRE_COMMIT_HOOK" << 'EOF'
#!/bin/bash
# =============================================================================
# Pre-commit hook: TruffleHog Secret Scanner
# =============================================================================
# This hook runs the TruffleHog secret scanner on staged changes only.
# It does NOT scan commits from remote branches (e.g., when merging main).
# =============================================================================

SCRIPT_PATH="$HOME/.pre-commit-scripts/secret-scan.sh"

if [ -f "$SCRIPT_PATH" ]; then
    exec "$SCRIPT_PATH"
else
    echo "⚠️  Warning: Secret scan script not found at $SCRIPT_PATH"
    echo "   Run setup-hooks.sh to install it, or commit will proceed without scanning."
    exit 0
fi
EOF

chmod +x "$PRE_COMMIT_HOOK"
echo "✅ Created pre-commit hook at $PRE_COMMIT_HOOK"

# Create log directory
mkdir -p "$HOME/trufflehog_logs"
echo "✅ Created log directory at $HOME/trufflehog_logs/"

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  🎉 Setup Complete!                                                ║"
echo "╠════════════════════════════════════════════════════════════════════╣"
echo "║  The pre-commit hook will now scan for secrets before each commit. ║"
echo "║                                                                    ║"
echo "║  Key features:                                                     ║"
echo "║  ✓ Only scans YOUR staged changes (not remote commits)             ║"
echo "║  ✓ Fast - doesn't scan entire git history                          ║"
echo "║  ✓ Exclusions: ~/.pre-commit-scripts/exclusion_list.txt            ║"
echo "║  ✓ Logs: ~/trufflehog_logs/                                        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 To test the hook:"
echo "   1. Stage some files:  git add <file>"
echo "   2. Try to commit:     git commit -m 'test'"
echo ""
echo "📝 To bypass the hook (emergency only!):"
echo "   git commit --no-verify -m 'message'"
echo ""

