# TruffleHog Pre-Commit Secret Scanner

A pre-commit hook that scans **only your staged changes** for secrets before allowing commits. This ensures:

- ✅ **Only YOUR code is scanned** - Not commits from remote/main when you merge
- ✅ **Fast execution** - Doesn't scan entire git history
- ✅ **No false positives from others' code** - Only checks what you're committing

## Quick Setup

```bash
# 1. Clone this repo and run setup
./setup-hooks.sh

# 2. That's it! Now every commit will be scanned automatically
```

## How It Works

### Old Approach (❌ Problematic)
```bash
# Old: Scanned git history with --since-commit HEAD
trufflehog git file://. --since-commit HEAD --branch main
```
**Problem**: When you merge main into your branch, it scans ALL those commits too!

### New Approach (✅ Correct)
```bash
# New: Scans only STAGED files using filesystem mode
git diff --cached --name-only  # Get staged files
trufflehog filesystem <staged-files>  # Scan only those
```
**Result**: Only YOUR changes are scanned, regardless of what's in git history.

## Testing Locally

Run the test suite to validate the scanner works correctly:

```bash
./test-scanner.sh
```

This will verify:
1. ✅ Unstaged secret files are NOT scanned
2. ✅ Staged secret files ARE detected
3. ✅ Existing repo secrets don't trigger false positives

## Manual Testing

```bash
# Test 1: Stage a clean file (should PASS)
echo "x = 42" > test.py
git add test.py
git commit -m "test"  # Should succeed

# Test 2: Stage a file with secrets (should FAIL)
echo 'key = "AKIAIOSFODNN7EXAMPLE"' > secret.py
git add secret.py
git commit -m "test"  # Should be blocked!
```

## Configuration

### Exclusion List
Edit `~/.pre-commit-scripts/exclusion_list.txt` to exclude files from scanning:

```txt
# Exclude test files
**/test/**
*.test.js

# Exclude lock files
package-lock.json
yarn.lock

# Exclude docs
*.md
```

### Logs
Logs are stored in `~/trufflehog_logs/`:
- `trufflehog_debug.log` - Debug output
- `trufflehog_results.csv` - Detected secrets (when found)

## Bypassing the Hook (Emergency Only!)

If you absolutely need to skip the scan:

```bash
git commit --no-verify -m "your message"
```

⚠️ **Warning**: Only do this in emergencies! Skipping the scan could expose secrets.

## File Structure

```
.
├── thog-scan.sh      # Main scanner script (improved)
├── setup-hooks.sh    # One-time setup script
├── test-scanner.sh   # Test suite for validation
└── README.md         # This file
```

## Troubleshooting

### "Trufflehog not found"
```bash
brew install trufflehog
```

### "jq not found"  
```bash
brew install jq
```

### False Positives
Add the pattern to `~/.pre-commit-scripts/exclusion_list.txt`

### Scanner not running
Check if the hook is installed:
```bash
cat .git/hooks/pre-commit
```

Re-run setup if needed:
```bash
./setup-hooks.sh
```
