#!/bin/bash

# =============================================================================
# TruffleHog Scanner Test Script
# =============================================================================
# Use this script to validate that the scanner works correctly
# It tests various scenarios without actually committing
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/.test-scanner"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  🧪 TruffleHog Scanner Test Suite                                  ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# Cleanup function
cleanup() {
    git reset HEAD --quiet 2>/dev/null || true
    rm -rf "$TEST_DIR" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/test-secret-file.py" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/test-clean-file.py" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/test-real-secret.py" 2>/dev/null || true
}

# Clean up any leftover files from previous runs
cleanup

trap cleanup EXIT

# =============================================================================
# TEST 1: Verify scanner only scans staged files
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TEST 1: Scanner should only scan STAGED files${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Create a file with a realistic secret but DON'T stage it

echo "Created test-secret-file.py with fake secrets (NOT staged)"

# Create a clean file and stage it
cat > "$SCRIPT_DIR/test-clean-file.py" << 'EOF'
# This is a clean file with no secrets
def hello():
    print("Hello, World!")
EOF

git add "$SCRIPT_DIR/test-clean-file.py"
echo "Created and staged test-clean-file.py (clean file)"

echo ""
echo "Running scanner..."
echo ""

# Run the scanner
if bash "$SCRIPT_DIR/thog-scan.sh"; then
    echo ""
    echo -e "${GREEN}✅ TEST 1 PASSED: Scanner correctly ignored unstaged secret file${NC}"
else
    echo ""
    echo -e "${RED}❌ TEST 1 FAILED: Scanner should have passed (secret file was not staged)${NC}"
fi

# Cleanup test 1
git reset HEAD --quiet
rm -f "$SCRIPT_DIR/test-secret-file.py" "$SCRIPT_DIR/test-clean-file.py"

echo ""

# =============================================================================
# TEST 2: Verify scanner detects secrets in staged files
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TEST 2: Scanner should DETECT secrets in staged files${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Create and STAGE a file with a realistic-looking secret
# (TruffleHog ignores obvious "EXAMPLE" keys)

git add "$SCRIPT_DIR/test-secret-file.py"
echo "Created and STAGED test-secret-file.py with fake secrets"

echo ""
echo "Running scanner..."
echo ""

# Run the scanner - it should fail (detect the secret)
if bash "$SCRIPT_DIR/thog-scan.sh"; then
    echo ""
    echo -e "${RED}❌ TEST 2 FAILED: Scanner should have detected the staged secret${NC}"
else
    echo ""
    echo -e "${GREEN}✅ TEST 2 PASSED: Scanner correctly detected the staged secret${NC}"
fi

# Cleanup test 2
git reset HEAD --quiet
rm -f "$SCRIPT_DIR/test-secret-file.py"

echo ""

# =============================================================================
# TEST 3: Verify existing commits from remote are NOT scanned
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TEST 3: Existing repo secrets should NOT trigger scanner${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "The repo already has configs/settings.py with secrets from previous commits."
echo "Staging a NEW clean file to test..."

# Create and stage a clean file
cat > "$SCRIPT_DIR/test-clean-file.py" << 'EOF'
# Just a clean test file
x = 42
EOF

git add "$SCRIPT_DIR/test-clean-file.py"

echo ""
echo "Running scanner..."
echo ""

# Run the scanner - should pass since we're only scanning the clean staged file
if bash "$SCRIPT_DIR/thog-scan.sh"; then
    echo ""
    echo -e "${GREEN}✅ TEST 3 PASSED: Scanner correctly ignored existing repo secrets${NC}"
    echo -e "${GREEN}   (Only scanned the new staged file, not configs/settings.py)${NC}"
else
    echo ""
    echo -e "${RED}❌ TEST 3 FAILED: Scanner incorrectly scanned existing repo files${NC}"
fi

# Cleanup test 3
git reset HEAD --quiet
rm -f "$SCRIPT_DIR/test-clean-file.py"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🏁 All tests completed!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

