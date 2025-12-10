---
name: Test Scenarios Plan
overview: Define comprehensive test scenarios for the diff-based secret scanning script and add temporary debug logging to verify only self-added commit diffs are scanned.
todos:
  - id: add-debug-flag
    content: Add DEBUG_MODE flag and helper function for conditional verbose logging
    status: pending
  - id: log-scan-mode
    content: Add logging after merge detection to show which scan mode was selected
    status: pending
  - id: log-diff-extraction
    content: Add logging in diff extraction loop to show exactly what lines are being scanned
    status: pending
  - id: log-scan-summary
    content: Add pre-scan summary showing all content that will be sent to TruffleHog
    status: pending
---

# Test Scenarios and Debug Logging for thog-scan.sh

## Understanding the Current Logic

The script at [`thog-scan.sh`](thog-scan.sh) has three scanning modes:

1. **SKIP_SCAN** - Pure merge from main/master (no additional changes)
2. **SCAN_ADDITIONAL_ONLY** - Merge from main/master WITH extra staged changes
3. **Regular scan** - Normal commits on any branch

The key diff extraction happens at lines 260-285, where only lines starting with `+` are extracted.

---

## Test Scenarios

### Scenario 1: Pure Merge from Main/Master (Should SKIP)

```bash
# Setup: On feature branch, merge main without any additional changes
git checkout -b test-merge
git checkout main && echo "main change" >> main-file.txt && git add . && git commit -m "main commit"
git checkout test-merge && git merge main
git commit  # Should show "Skipping scan: Merge from main/master"
```

### Scenario 2: Merge from Main/Master with Additional Changes (Scan ONLY additional)

```bash
# Setup: Merge main, then stage extra changes before committing
git checkout test-merge && git merge main
echo "my new secret = AKIA1234567890ABCDEF" >> my-file.txt
git add my-file.txt
git commit  # Should scan ONLY my-file.txt diff, not merged content
```

### Scenario 3: Regular Commit with New Secret (Should DETECT)

```bash
# Add a file with a secret and commit
echo "aws_secret = AKIAIOSFODNN7EXAMPLE" > new-secret.py
git add new-secret.py
git commit -m "test"  # Should detect the secret in diff
```

### Scenario 4: Pre-existing Secret - Modify Unrelated Lines (Should PASS)

```bash
# File already contains a secret, modify different lines
# Pre-existing: aws_key = AKIAIOSFODNN7EXAMPLE on line 5
echo "# safe comment" >> file-with-secret.py
git add file-with-secret.py
git commit  # Should NOT detect pre-existing secret (only scans added lines)
```

### Scenario 5: Only Deletions (Should PASS - no new content)

```bash
# Delete lines without adding anything
# Remove lines from a file
git add -u
git commit  # Should show "No new content to scan"
```

### Scenario 6: Mixed Changes (Should Scan ONLY Additions)

```bash
# Modify file: delete some lines, add others
# Only the ADDED lines should be scanned, not the deleted or unchanged
git diff --cached  # Shows +/- lines
git commit  # Only + lines get scanned
```

### Scenario 7: Empty Staged Changes (Should PASS)

```bash
# No files staged
git commit  # Should show "No staged files to scan"
```

---

## Temporary Logging Additions

Add verbose logging to [`thog-scan.sh`](thog-scan.sh) to prove only diffs are scanned:

### Location 1: After mode detection (around line 223)

Log which scanning mode was selected and why.

### Location 2: Inside the diff extraction loop (lines 262-285)

Log exactly what content is being extracted for each file.

### Location 3: Before TruffleHog execution (around line 300)

Show a summary of all diff content that will be scanned.

### Location 4: Add a new `--verbose` or `DEBUG` flag

Enable/disable detailed logging without cluttering normal output.

---

## Proposed Logging Code Changes

I will add a `DEBUG_MODE` variable and conditional logging blocks that:

1. Print the scan mode selected (SKIP, ADDITIONAL_ONLY, or FULL_DIFF)
2. Show each file being processed and its extracted diff lines
3. Display total diff content before TruffleHog runs
4. Confirm what was NOT scanned (full file content, merged content)

This will be toggleable via `DEBUG_MODE=true` at the top of the script.