cd /Users/shivamvv/Desktop/rippling/security-hooks && git checkout shivam-pch

# ============================================
# TEST: Verify Diff-Based Scanning Logic
# ============================================

echo "🔍 Checking secret-scan.sh implementation..."
echo ""

# Check 1: Is it using trufflehog filesystem (not git)?
echo "1️⃣  Scanning mode check:"
if grep -q "trufflehog filesystem" secret-scan.sh; then
    echo "   ✅ Uses 'trufflehog filesystem' (diff-based scanning)"
else
    echo "   ❌ Still uses 'trufflehog git' (scans git history - WRONG)"
fi

# Check 2: Does it extract diff lines?
echo ""
echo "2️⃣  Diff extraction check:"
if grep -q "git diff --cached.*grep.*\"\^+\"" secret-scan.sh; then
    echo "   ✅ Extracts only added lines (grep ^+)"
else
    echo "   ❌ Missing diff extraction logic"
fi

# Check 3: Does it have DIFF_FILES_DIR?
echo ""
echo "3️⃣  Temp directory for diffs:"
if grep -q "DIFF_FILES_DIR" secret-scan.sh; then
    echo "   ✅ Has DIFF_FILES_DIR for staging diff content"
else
    echo "   ❌ Missing DIFF_FILES_DIR"
fi

# Check 4: Merge detection
echo ""
echo "4️⃣  Merge detection:"
if grep -q "is_merge_commit" secret-scan.sh && grep -q "is_main_or_master" secret-scan.sh; then
    echo "   ✅ Has merge detection functions"
else
    echo "   ❌ Missing merge detection"
fi

# Check 5: Skip logic for pure merges
echo ""
echo "5️⃣  Skip scan for pure merges:"
if grep -q "SKIP_SCAN=true" secret-scan.sh; then
    echo "   ✅ Skips scan for pure merges from main"
else
    echo "   ❌ Missing skip logic"
fi

echo ""
echo "============================================"
echo "📊 Summary of key lines:"
echo "============================================"
grep -n "trufflehog" secret-scan.sh | head -5
echo ""
echo "============================================"
