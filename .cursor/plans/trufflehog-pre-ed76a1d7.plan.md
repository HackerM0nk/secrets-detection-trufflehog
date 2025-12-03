<!-- ed76a1d7-3424-4e80-a874-b23840417b15 3a0a573a-3e35-485c-9bf2-c7617a268400 -->
# TruffleHog Pre-Commit Hook Testing Plan (Updated)

## Current State Analysis

Your existing setup:

- **Branch**: `shivam` with 3 commits + 1 merge commit
- **Secret**: AWS credentials in `configs/settings.py` (commit `ef746b2`)
- **Script**: `thog-scan.sh` with logging, metrics, and Google Form integration
- **User email**: `svaishampayan@rippling.com`

**Current Issue in `thog-scan.sh`**: Lines 91-98 use `--since-commit HEAD` which only scans the latest commit. This doesn't properly handle the merge scenario.

---

## Phase 1: Enhance thog-scan.sh with Commit Visibility

Add debug output after line 98 to show exactly which commits will be scanned. Insert this block:

```bash
# === DEBUG: Show commits being scanned ===
echo "=============================================="
echo "🔍 COMMITS TO BE SCANNED:"
echo "=============================================="
if [ -n "$SINCE_COMMIT" ]; then
    COMMITS_TO_SCAN=$(git log --oneline HEAD~1..HEAD 2>/dev/null || echo "Unable to determine")
else
    COMMITS_TO_SCAN=$(git log --oneline 2>/dev/null | head -20)
fi
echo "$COMMITS_TO_SCAN"
echo "=============================================="
```

---

## Phase 2: Fix the Core Scanning Logic

Replace the naive `--since-commit HEAD` approach with author-filtered scanning. Modify lines 91-98:

**From:**

```bash
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    SINCE_COMMIT="--since-commit HEAD"
else
    SINCE_COMMIT=""
fi
```

**To:**

```bash
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    # Find merge-base with origin/main (or main if no remote)
    MERGE_BASE=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD 2>/dev/null || echo "")
    
    if [ -n "$MERGE_BASE" ]; then
        # Get only commits by current user since merge-base
        USER_COMMITS=$(git rev-list --author="$USER_IDENTIFIER" "$MERGE_BASE"..HEAD 2>/dev/null)
        
        if [ -z "$USER_COMMITS" ]; then
            echo "✅ No new commits by current user to scan. Passing."
            exit 0
        fi
        
        # Use the oldest user commit as since-commit reference
        OLDEST_USER_COMMIT=$(echo "$USER_COMMITS" | tail -1)
        SINCE_COMMIT="--since-commit ${OLDEST_USER_COMMIT}^"
        
        # Store for debug output
        COMMITS_TO_SCAN_LIST="$USER_COMMITS"
    else
        SINCE_COMMIT="--since-commit HEAD"
    fi
else
    SINCE_COMMIT=""
fi
```

---

## Phase 3: Install as Pre-Commit Hook

Copy the modified script to `.git/hooks/pre-commit`:

```bash
cp thog-scan.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Also ensure the exclusion file exists:

```bash
mkdir -p ~/.pre-commit-scripts
touch ~/.pre-commit-scripts/exclusion_list.txt
```

---

## Phase 4: Test Scenario Execution

### Step 1: Complete User1's Setup (You)

- You already have 3 commits on `shivam` branch
- Secret is in commit `ef746b2`
- **Next**: Make a 4th commit (any small change)

### Step 2: User2 Actions (Your Colleague)

1. Clone the repo fresh
2. Create branch `user2-branch` from `main`
3. Make 4 commits with file changes (e.g., modify `src/app.py`, `src/main.py`)
4. Push and create PR to `main`
5. Merge PR

### Step 3: Verify the Problem

1. On your `shivam` branch: `git pull origin main`
2. Make a 5th commit
3. **Expected with OLD script**: All 9 commits scanned
4. **Expected with NEW script**: Only your 5 commits scanned

---

## Phase 5: Validation Checklist

After implementing the fix, verify:

| Test Case | Expected Result |

|-----------|-----------------|

| Debug output shows commits | Only User1's commits listed |

| TruffleHog finds secret | Yes (in commit `ef746b2`) |

| User2's commits scanned | No (filtered out by author) |

| Scan time | Reduced (fewer commits) |

---

## Files to Modify

| File | Action |

|------|--------|

| `thog-scan.sh` | Add debug output + author-filtered scanning logic |

| `.git/hooks/pre-commit` | Copy modified thog-scan.sh |

| `~/.pre-commit-scripts/exclusion_list.txt` | Create if missing |

---

## Key Insight

The fix uses `git rev-list --author="$USER_IDENTIFIER"` to filter commits, ensuring only the current developer's commits are scanned. This prevents re-scanning commits that came from merged branches (User2's commits) which were already scanned when they were pushed/merged.

### To-dos

- [ ] Add commit visibility debug output to thog-scan.sh
- [ ] Replace --since-commit HEAD with author-filtered merge-base logic
- [ ] Install modified script as .git/hooks/pre-commit and create exclusion file
- [ ] Make 4th commit on shivam branch before User2 test
- [ ] Document steps for User2 to create branch, 4 commits, push and merge PR
- [ ] Pull from main into shivam and verify only User1 commits are scanned
- [ ] Confirm secret in ef746b2 is still detected with new logic