# BMAD Epic-Execute v2 Fixes & Improvements

**Date:** 2026-01-26
**Scope:** `scripts/epic-execute.sh` and `scripts/epic-execute-lib/` modules
**Purpose:** Ensure reliable, error-free execution of the epic-execute automation

---

## Executive Summary

This document identifies critical issues in the epic-execute library that can cause execution failures, unreliable behavior, or silent errors. It also identifies opportunities to leverage existing BMAD workflows instead of custom prompts.

**Key Findings:**
1. **5 Critical Issues** that can cause execution failures
2. **5 High-Priority Issues** that cause unreliable behavior
3. **5 Medium-Priority Issues** affecting quality/reliability
4. **5 Low-Priority Improvements** for better UX
5. **4 BMAD Workflow Integration Gaps** where custom prompts should use existing workflows

---

## Table of Contents

1. [Critical Issues](#critical-issues)
2. [High-Priority Issues](#high-priority-issues)
3. [Medium-Priority Issues](#medium-priority-issues)
4. [Low-Priority Improvements](#low-priority-improvements)
5. [BMAD Workflow Integration Gaps](#bmad-workflow-integration-gaps)
6. [Implementation Priority](#implementation-priority)

---

## Critical Issues

Issues that can cause execution failures. **Must fix before production use.**

### C1. Fragile Path Resolution

**File:** `scripts/epic-execute.sh:27-28`

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
```

**Problem:** Assumes script is always 2 directories below project root. If the script is moved, renamed, or run from a different location, this breaks silently.

**Fix:**
```bash
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../.." && pwd)}"
if [ ! -f "$PROJECT_ROOT/package.json" ] && [ ! -d "$PROJECT_ROOT/.git" ]; then
    log_error "Cannot determine project root. Set PROJECT_ROOT or run from within a git repository."
    exit 1
fi
```

---

### C2. Silent Module Loading Failures

**File:** `scripts/epic-execute.sh:36-40`

```bash
[ -f "$LIB_DIR/decision-log.sh" ] && source "$LIB_DIR/decision-log.sh"
```

**Problem:** If a module file exists but has a syntax error, `source` fails silently due to `&&`. The script continues without these functions, causing later failures when functions are called.

**Fix:**
```bash
for module in decision-log regression-gate design-phase json-output tdd-flow; do
    if [ -f "$LIB_DIR/${module}.sh" ]; then
        source "$LIB_DIR/${module}.sh" || {
            log_error "Failed to load module: ${module}.sh"
            exit 1
        }
    else
        log_warn "Optional module not found: ${module}.sh"
    fi
done
```

---

### C3. Non-Numeric EPIC_ID Crashes Printf

**File:** `scripts/epic-execute.sh:585`

```bash
EPIC_ID_PADDED=$(printf "%03d" "$EPIC_ID" 2>/dev/null || echo "$EPIC_ID")
```

**Problem:** If EPIC_ID contains non-numeric characters (e.g., "epic-1"), printf fails. The error is suppressed but can cause issues downstream.

**Fix:** Validate EPIC_ID format early:
```bash
# After parsing EPIC_ID
if ! [[ "$EPIC_ID" =~ ^[0-9]+$ ]]; then
    log_error "EPIC_ID must be numeric. Got: '$EPIC_ID'"
    log_error "Usage: $0 <epic-number> [options]"
    exit 1
fi
```

---

### C4. Claude CLI Invocations Can Hang Indefinitely

**File:** `scripts/epic-execute.sh:818` (and all other `claude` invocations)

```bash
result=$(claude --dangerously-skip-permissions -p "$dev_prompt" 2>&1) || true
```

**Problem:** No timeout. Claude can hang, stall, or wait for input, blocking execution forever.

**Fix:** Add timeout wrapper:
```bash
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-600}"  # 10 minutes default

execute_claude_prompt() {
    local prompt="$1"
    local timeout="${2:-$CLAUDE_TIMEOUT}"

    local result
    result=$(timeout "$timeout" claude --dangerously-skip-permissions -p "$prompt" 2>&1) || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Claude timed out after ${timeout}s"
            echo "TIMEOUT"
            return 124
        fi
        echo "$result"
        return $exit_code
    }
    echo "$result"
}

# Usage:
result=$(execute_claude_prompt "$dev_prompt")
if [ "$result" = "TIMEOUT" ]; then
    log_error "Dev phase timed out for $story_id"
    return 1
fi
```

---

### C5. JSON Extraction Fails on Multi-line JSON

**File:** `scripts/epic-execute-lib/json-output.sh:37-38`

```bash
json_block=$(echo "$output" | sed -n '/```json/,/```/p' | sed '1d;$d')
```

**Problem:** This sed pattern is fragile. If Claude outputs multiple JSON blocks, nested backticks, or the JSON contains special characters, parsing fails.

**Fix:** Use a more robust extraction that handles edge cases:
```bash
extract_json_result() {
    local output="$1"
    LAST_JSON_RESULT=""

    # Method 1: Extract last ```json block using awk (handles multiple blocks)
    local json_block
    json_block=$(echo "$output" | awk '
        /```json/ { capture=1; content=""; next }
        /```/ && capture { last=content; capture=0; next }
        capture { content = content (content ? "\n" : "") $0 }
        END { print last }
    ')

    # Method 2: Fallback to ```result block
    if [ -z "$json_block" ]; then
        json_block=$(echo "$output" | awk '
            /```result/ { capture=1; content=""; next }
            /```/ && capture { last=content; capture=0; next }
            capture { content = content (content ? "\n" : "") $0 }
            END { print last }
        ')
    fi

    # Method 3: Find standalone JSON object
    if [ -z "$json_block" ]; then
        json_block=$(echo "$output" | grep -oE '\{[^{}]*"status"[^{}]*\}' | tail -1)
    fi

    # Validate JSON
    if [ -n "$json_block" ]; then
        if command -v jq >/dev/null 2>&1; then
            if echo "$json_block" | jq . >/dev/null 2>&1; then
                LAST_JSON_RESULT="$json_block"
                echo "$json_block"
                return 0
            fi
        else
            LAST_JSON_RESULT="$json_block"
            echo "$json_block"
            return 0
        fi
    fi

    echo ""
    return 1
}
```

---

## High-Priority Issues

Issues that cause unreliable behavior. **Should fix for reliable operation.**

### H1. Git Add -A Commits Everything ✅ DONE

> **Implemented in commit `ce2f9fb3`** - Added `check_sensitive_files()` function, replaced `git add -A` with `git add -u`, updated all prompts to use explicit file staging.

**File:** `scripts/epic-execute.sh:2246`

```bash
git add -A
```

**Problem:** Stages ALL changes including untracked files. Could accidentally commit `.env` files with secrets, IDE configuration, large binaries, or unrelated work-in-progress.

**Fix:**
```bash
commit_story() {
    local story_id="$1"

    if [ "$NO_COMMIT" = true ]; then
        log "Skipping commit (--no-commit)"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would commit: feat(epic-$EPIC_ID): complete $story_id"
        return 0
    fi

    # Safety check: verify .gitignore covers sensitive files
    local sensitive_files=(".env" ".env.local" "credentials.json" ".secrets")
    for file in "${sensitive_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ] && ! git check-ignore -q "$PROJECT_ROOT/$file" 2>/dev/null; then
            log_error "SAFETY: $file exists and is not gitignored. Add to .gitignore before committing."
            return 1
        fi
    done

    # Use git add -u (tracked files only) + explicit new files from story
    git add -u
    # Stage any new files that were explicitly created during this story
    # (Claude should have staged them with git add)

    git commit -m "feat(epic-$EPIC_ID): complete $story_id" || {
        log_warn "Nothing to commit for $story_id"
    }

    log_success "Committed: $story_id"
}
```

---

### H2. No Cleanup on Script Exit ✅ DONE

> **Implemented in commit `ce2f9fb3`** - Added `cleanup()` function with trap handler for EXIT/INT/TERM, saves checkpoint file for resume, finalizes metrics, reports uncommitted changes.

**File:** `scripts/epic-execute.sh` (missing)

**Problem:** If the script is interrupted (Ctrl+C, kill, error), partial state remains: uncommitted git changes, incomplete metrics files, partial decision logs.

**Fix:** Add trap handler at the beginning of the script:
```bash
# Add after set -e
cleanup() {
    local exit_code=$?
    log "Cleaning up (exit code: $exit_code)..."

    # Save progress metrics
    if [ -n "$METRICS_FILE" ] && [ -f "$METRICS_FILE" ]; then
        local duration=$(($(date +%s) - EPIC_START_SECONDS))
        finalize_metrics "${#STORIES[@]}" "$COMPLETED" "$FAILED" "$((${#STORIES[@]} - COMPLETED - FAILED))" "$duration"
        log "Metrics saved to: $METRICS_FILE"
    fi

    # Report uncommitted changes
    local uncommitted
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$uncommitted" -gt 0 ]; then
        log_warn "Uncommitted changes remain ($uncommitted files). Run 'git status' to review."
    fi

    # Save checkpoint for resume
    if [ -n "$SPRINT_ARTIFACTS_DIR" ] && [ -n "$EPIC_ID" ]; then
        echo "LAST_STORY_INDEX=$current_story_index" > "$SPRINT_ARTIFACTS_DIR/.epic-${EPIC_ID}-checkpoint"
        echo "COMPLETED=$COMPLETED" >> "$SPRINT_ARTIFACTS_DIR/.epic-${EPIC_ID}-checkpoint"
        echo "FAILED=$FAILED" >> "$SPRINT_ARTIFACTS_DIR/.epic-${EPIC_ID}-checkpoint"
        echo "SKIPPED=$SKIPPED" >> "$SPRINT_ARTIFACTS_DIR/.epic-${EPIC_ID}-checkpoint"
    fi

    exit $exit_code
}
trap cleanup EXIT INT TERM
```

---

### H3. Test Count Parsing Is Framework-Dependent ✅ DONE

> **Implemented in commit `ce2f9fb3`** - Added `extract_test_count()` function supporting Jest, Mocha, Vitest, AVA, TAP, pytest, Go, and Rust formats. Tries JSON output first, falls back to regex patterns.

**File:** `scripts/epic-execute-lib/regression-gate.sh:42-53`

```bash
BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE '[0-9]+ passing' | grep -oE '[0-9]+' | head -1 || echo "0")
```

**Problem:** Pattern matching varies by test framework. Vitest, AVA, tap, and other frameworks have different output formats. Many false negatives.

**Fix:** Add more patterns and prefer JSON output:
```bash
extract_test_count() {
    local test_output="$1"
    local count=0

    # Try JSON output first (most reliable - jest --json)
    if echo "$test_output" | jq -e '.numPassedTests' >/dev/null 2>&1; then
        count=$(echo "$test_output" | jq '.numPassedTests // 0')
        echo "$count"
        return 0
    fi

    # Pattern matching fallbacks (ordered by specificity)
    local patterns=(
        # Jest
        'Tests:[[:space:]]*[0-9]+ passed'
        # Mocha
        '[0-9]+ passing'
        # Vitest
        '[0-9]+ passed'
        # Generic
        '[0-9]+ tests? passed'
        # TAP
        '# pass[[:space:]]+[0-9]+'
        # Python pytest
        '[0-9]+ passed'
    )

    for pattern in "${patterns[@]}"; do
        count=$(echo "$test_output" | grep -oE "$pattern" | grep -oE '[0-9]+' | head -1 || echo "")
        if [ -n "$count" ] && [ "$count" != "0" ]; then
            echo "$count"
            return 0
        fi
    done

    echo "0"
}
```

---

### H4. Story Discovery Can Match Wrong Files ✅ DONE

> **Implemented in commit `ce2f9fb3`** - Fixed grep pattern with word boundary `${EPIC_ID}([^0-9]|$)` to prevent "Epic: 1" from matching "Epic: 10". Added associative array deduplication with bash 3.x fallback.

**File:** `scripts/epic-execute.sh:618-643`

```bash
grep -l -Z "Epic.*:.*${EPIC_ID}\|epic-${EPIC_ID}\|Epic.*${EPIC_ID}" "$search_dir"/*.md
```

**Problem:** Pattern `Epic.*${EPIC_ID}` matches "Epic: 1" but also "Epic: 10", "Epic: 100" if EPIC_ID=1. Deduplication with array membership test fails if paths contain spaces.

**Fix:** Use word boundaries and associative array:
```bash
# Use word boundaries in grep
grep -l -Z -E "Epic[^0-9]*:?[^0-9]*\b${EPIC_ID}\b|epic-${EPIC_ID}\b" "$search_dir"/*.md 2>/dev/null || true

# Use associative array for deduplication (bash 4+)
declare -A seen_stories
STORIES=()

for search_dir in "${STORY_LOCATIONS[@]}"; do
    [ ! -d "$search_dir" ] && continue

    while IFS= read -r -d '' file; do
        # Normalize path for deduplication
        local normalized
        normalized=$(realpath "$file" 2>/dev/null || echo "$file")

        if [ -z "${seen_stories[$normalized]:-}" ]; then
            seen_stories[$normalized]=1
            STORIES+=("$file")
        fi
    done < <(find "$search_dir" -maxdepth 1 -name "*.md" -print0 2>/dev/null | \
             xargs -0 grep -l -Z -E "Epic[^0-9]*:?[^0-9]*\b${EPIC_ID}\b" 2>/dev/null || true)
done
```

---

### H5. Large Prompts Can Exceed Claude Context Limits ✅ DONE

> **Implemented in commit `ce2f9fb3`** - Added `MAX_PROMPT_SIZE` config (default 150KB), `get_byte_size()`, `truncate_content()`, `build_sized_prompt()`, and `log_prompt_size()` functions. Truncates large workflow YAML and decision logs.

**File:** `scripts/epic-execute.sh` (various execute_* functions)

**Problem:** Prompts include entire files (story, architecture, workflow YAML, instructions XML, decision log, etc.). For large projects, this can exceed context window.

**Fix:** Add prompt size monitoring and truncation:
```bash
MAX_PROMPT_SIZE="${MAX_PROMPT_SIZE:-150000}"  # ~150KB default

build_prompt_with_limit() {
    local base_prompt="$1"
    local decision_context="$2"
    local arch_contents="$3"

    local prompt="$base_prompt"
    local prompt_size=${#prompt}

    # Add architecture if within limit
    if [ -n "$arch_contents" ]; then
        local arch_size=${#arch_contents}
        if [ $((prompt_size + arch_size)) -lt $MAX_PROMPT_SIZE ]; then
            prompt+="$arch_contents"
            prompt_size=$((prompt_size + arch_size))
        else
            # Truncate architecture to essential sections
            local truncated_arch
            truncated_arch=$(echo "$arch_contents" | head -c 20000)
            prompt+="$truncated_arch\n\n[Architecture truncated for size...]"
            prompt_size=$((prompt_size + 20000))
            log_warn "Architecture truncated to fit context limit"
        fi
    fi

    # Add decision context if within limit
    if [ -n "$decision_context" ]; then
        local remaining=$((MAX_PROMPT_SIZE - prompt_size - 5000))  # Reserve 5K
        if [ $remaining -gt 0 ]; then
            local truncated_decisions
            truncated_decisions=$(echo "$decision_context" | tail -c "$remaining")
            prompt+="$truncated_decisions"
        else
            log_warn "Decision context skipped due to size limit"
        fi
    fi

    echo "$prompt"
}
```

---

## Medium-Priority Issues

Issues that affect quality and reliability. **Recommended for quality.**

### M1. No Retry Logic for Transient Failures ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `execute_with_retry()` with exponential backoff, `execute_claude_with_retry()` wrapper, configurable via `RETRY_MAX_ATTEMPTS`, `RETRY_INITIAL_DELAY`, `RETRY_MAX_DELAY`.

**Problem:** Network issues, Claude rate limits, or temporary failures cause immediate failure without retry.

**Fix:** Add retry wrapper:
```bash
execute_with_retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi

        local exit_code=$?
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Attempt $attempt failed (exit code: $exit_code). Retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        ((attempt++))
    done

    log_error "All $max_attempts attempts failed"
    return 1
}

# Usage in execute_dev_phase:
result=$(execute_with_retry 3 5 timeout "$CLAUDE_TIMEOUT" claude --dangerously-skip-permissions -p "$dev_prompt")
```

---

### M2. yq Dependency Version Incompatibility ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `validate_yq()` to detect Go vs Python yq versions, `YQ_AVAILABLE` flag, `safe_yq()` wrapper with fallback support.

**File:** `scripts/epic-execute.sh:164`

**Problem:** `yq` has multiple incompatible versions (Mike Farah's Go version vs Python version). The syntax differs between them.

**Fix:** Validate yq version:
```bash
validate_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        return 1
    fi

    # Check if it's the Go version (mikefarah/yq) which we expect
    if yq --version 2>&1 | grep -qE "(mikefarah|version v4)"; then
        return 0
    fi

    # Python yq has different syntax
    if yq --version 2>&1 | grep -q "jq wrapper"; then
        log_warn "Python yq detected - using sed fallback for YAML updates"
        return 1
    fi

    log_warn "Unknown yq version - YAML updates may fail"
    return 1
}

# Use at startup
YQ_AVAILABLE=false
if validate_yq; then
    YQ_AVAILABLE=true
fi
```

---

### M3. Completion Signal Detection Is Unreliable ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `check_phase_completion_fuzzy()` with case-insensitive pattern matching for all phases (dev, review, fix, arch, test_quality, trace, uat). Enhanced `check_phase_completion()` in json-output.sh to use fuzzy matching as fallback.

**File:** `scripts/epic-execute-lib/json-output.sh:253-313`

**Problem:** Relies on Claude outputting exact strings like "IMPLEMENTATION COMPLETE". AI output varies - might output "Implementation complete!", "COMPLETE - IMPLEMENTATION", etc.

**Fix:** Use case-insensitive fuzzy matching:
```bash
check_phase_completion() {
    local output="$1"
    local phase_type="$2"
    local story_id="$3"

    # Try JSON parsing first
    if [ "$USE_LEGACY_OUTPUT" != true ]; then
        local json_result
        json_result=$(extract_json_result "$output")
        if [ -n "$json_result" ]; then
            local status
            status=$(get_result_status "$json_result")
            case "$status" in
                COMPLETE|PASSED|COMPLIANT|APPROVED|SUCCESS|DONE)
                    return 0 ;;
                BLOCKED|FAILED|VIOLATIONS|ERROR|INCOMPLETE)
                    return 1 ;;
            esac
        fi
    fi

    # Fuzzy text matching fallback (case-insensitive)
    case "$phase_type" in
        dev)
            if echo "$output" | grep -iqE "(implementation|dev|story).*(complete|done|finished|success)"; then
                return 0
            elif echo "$output" | grep -iqE "(implementation|dev).*(block|fail|error|cannot|unable)"; then
                return 1
            fi
            ;;
        review)
            if echo "$output" | grep -iqE "review.*(pass|approv|success|complete)"; then
                return 0
            elif echo "$output" | grep -iqE "review.*(fail|reject|issue|problem)"; then
                return 1
            fi
            ;;
        # ... similar for other phases
    esac

    return 2  # Unclear
}
```

---

### M4. sed -i Not Portable ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `sed_inplace()` and `sed_inplace_backup()` functions that detect `$OSTYPE` and use correct syntax for macOS (BSD sed) vs Linux (GNU sed). Updated `update_story_status()` and `update_sprint_status()` in epic-execute.sh to use these functions.

**File:** `scripts/epic-execute.sh:289`

```bash
sed -i.bak "s/^Status:.*$/Status: $new_status/" "$story_file" && rm -f "${story_file}.bak"
```

**Problem:** `sed -i` behaves differently on macOS vs Linux. macOS requires `-i ''` for no backup.

**Fix:** Use cross-platform approach:
```bash
sed_inplace() {
    local pattern="$1"
    local file="$2"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}

# Usage:
sed_inplace "s/^Status:.*$/Status: $new_status/" "$story_file"
```

---

### M5. No Branch Protection ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `check_branch_protection()` that checks current branch against `PROTECTED_BRANCHES` (default: "main master"). Exits with error if on protected branch. Called during initialization in epic-execute.sh (skipped if `--no-commit`).

**Problem:** Script commits directly to current branch without checking if it's protected (main/master).

**Fix:** Add branch protection check:
```bash
check_branch_protection() {
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD)

    local protected_branches="${PROTECTED_BRANCHES:-main master}"

    if echo "$protected_branches" | grep -qw "$current_branch"; then
        log_error "Cannot commit directly to protected branch: $current_branch"
        log_error "Create a feature branch first: git checkout -b epic-${EPIC_ID}"
        exit 1
    fi

    log "Working on branch: $current_branch"
}

# Call early in script
check_branch_protection
```

---

## Low-Priority Improvements

Nice-to-have improvements for better UX and maintainability.

### L1. No Progress Persistence / Resume Capability ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `load_checkpoint()`, `save_checkpoint()`, `clear_checkpoint()`, and `get_resume_index()` functions. Added `--resume` flag to epic-execute.sh. Checkpoint includes story index, completed/failed/skipped counts, and timestamp. Old checkpoints (>7 days) are automatically ignored.

**Problem:** If script fails at story 5/10, user must use `--start-from` manually. No automatic resume.

**Fix:** Add checkpoint file support:
```bash
CHECKPOINT_FILE=""

save_checkpoint() {
    local story_index="$1"
    local story_id="$2"

    [ -z "$CHECKPOINT_FILE" ] && return

    cat > "$CHECKPOINT_FILE" << EOF
LAST_COMPLETED_STORY=$story_id
LAST_STORY_INDEX=$story_index
COMPLETED=$COMPLETED
FAILED=$FAILED
SKIPPED=$SKIPPED
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

load_checkpoint() {
    CHECKPOINT_FILE="$SPRINT_ARTIFACTS_DIR/.epic-${EPIC_ID}-checkpoint"

    if [ -f "$CHECKPOINT_FILE" ] && [ -z "$START_FROM" ]; then
        source "$CHECKPOINT_FILE"
        if [ -n "$LAST_COMPLETED_STORY" ]; then
            log "Found checkpoint from previous run"
            log "  Last completed: $LAST_COMPLETED_STORY"
            log "  Progress: $COMPLETED completed, $FAILED failed, $SKIPPED skipped"

            # Auto-set START_FROM to next story
            # (implementation would find index + 1)
        fi
    fi
}
```

---

### L2. Missing --help Option ✅ DONE

> **Implemented in `scripts/epic-execute.sh`** - Added `show_help()` function with comprehensive documentation of all options, examples, and environment variables. Added `-h` and `--help` flag handling at start of argument parsing.

**Problem:** No built-in help. Users must read script header comments.

**Fix:** Add proper help function at argument parsing:
```bash
show_help() {
    cat << 'EOF'
BMAD Epic Execute - Automated Story Execution with Context Isolation

USAGE:
    epic-execute.sh <epic-id> [OPTIONS]

ARGUMENTS:
    epic-id             Numeric ID of the epic to execute (e.g., 1, 42)

OPTIONS:
    --dry-run           Show what would be executed without running
    --skip-review       Skip code review phase (not recommended)
    --no-commit         Stage changes but don't commit
    --parallel          Run independent stories in parallel (experimental)
    --verbose           Show detailed output including Claude responses
    --start-from ID     Start from a specific story (e.g., 31-2)
    --skip-done         Skip stories with Status: Done
    --skip-arch         Skip architecture compliance check
    --skip-test-quality Skip test quality review
    --skip-traceability Skip traceability check (not recommended)
    --skip-static-analysis  Skip static analysis gate
    --skip-design       Skip pre-implementation design phase
    --skip-regression   Skip regression test gate
    --skip-tdd          Skip all test-first development phases
    --skip-test-spec    Skip test specification phase only
    --skip-test-impl    Skip test implementation phase only
    --legacy-output     Use legacy text-based output parsing (no JSON)
    -h, --help          Show this help message

EXAMPLES:
    # Execute epic 1 with all gates
    ./epic-execute.sh 1

    # Dry run to preview execution
    ./epic-execute.sh 1 --dry-run --verbose

    # Skip already-completed stories
    ./epic-execute.sh 1 --skip-done

    # Resume from specific story
    ./epic-execute.sh 1 --start-from 1-3

    # Fast mode (skip optional gates)
    ./epic-execute.sh 1 --skip-arch --skip-traceability

ENVIRONMENT:
    CLAUDE_TIMEOUT      Timeout for Claude invocations (default: 600s)
    PROJECT_ROOT        Override project root detection
    PROTECTED_BRANCHES  Space-separated list of protected branches

For more information, see: docs/bmad_improvements_v2.md
EOF
    exit 0
}

# Add at start of argument parsing
[[ "${1:-}" =~ ^(-h|--help)$ ]] && show_help
```

---

### L3. No Verbose Logging Option for Claude Output ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `execute_claude_verbose()` function that streams Claude output to both terminal and log file when `--verbose` is set. Includes timeout handling and prompt size logging.

**Problem:** Claude output only goes to log file. Debugging requires reading `/tmp/bmad-epic-execute-$$.log`.

**Fix:** Add streaming option when verbose:
```bash
execute_claude_prompt() {
    local prompt="$1"
    local phase_name="${2:-claude}"

    if [ "$VERBOSE" = true ]; then
        log ">>> Claude $phase_name prompt (${#prompt} bytes)"
        local result
        result=$(claude --dangerously-skip-permissions -p "$prompt" 2>&1 | tee -a "$LOG_FILE")
        echo "$result"
    else
        local result
        result=$(claude --dangerously-skip-permissions -p "$prompt" 2>&1)
        echo "$result" >> "$LOG_FILE"
        echo "$result"
    fi
}
```

---

### L4. Metrics File Can Grow Unbounded ✅ DONE

> **Implemented in `scripts/epic-execute.sh`** - Updated `init_metrics()` to archive existing metrics files before creating new ones. Archives stored in `metrics/archive/` directory. Automatically cleans up old archives, keeping only the last 10 per epic.

**Problem:** YAML metrics with arrays (issues, story_details) grow indefinitely across multiple runs.

**Fix:** Archive old metrics before new run:
```bash
init_metrics() {
    METRICS_DIR="$SPRINT_ARTIFACTS_DIR/metrics"
    METRICS_FILE="$METRICS_DIR/epic-${EPIC_ID}-metrics.yaml"
    mkdir -p "$METRICS_DIR"

    # Archive existing metrics file
    if [ -f "$METRICS_FILE" ]; then
        local archive_name="epic-${EPIC_ID}-metrics.$(date +%Y%m%d%H%M%S).yaml"
        mv "$METRICS_FILE" "$METRICS_DIR/$archive_name"
        log "Archived previous metrics to: $archive_name"
    fi

    # Create fresh metrics file
    # ... rest of init_metrics
}
```

---

### L5. No Validation of Workflow Files Content ✅ DONE

> **Implemented in `scripts/epic-execute-lib/utils.sh`** - Added `validate_yaml_content()`, `validate_xml_content()`, and `validate_workflow_content()` functions. Uses yq for YAML validation (with fallback basic syntax checks) and xmllint for XML validation. Updated `validate_workflows()` in epic-execute.sh to call content validation.

**Problem:** Script checks if workflow files exist but not if they're valid YAML/XML.

**Fix:** Add content validation:
```bash
validate_workflow_content() {
    local file="$1"
    local file_type="${file##*.}"

    case "$file_type" in
        yaml|yml)
            if command -v yq >/dev/null 2>&1; then
                if ! yq '.' "$file" >/dev/null 2>&1; then
                    log_error "Invalid YAML in: $file"
                    return 1
                fi
            fi
            ;;
        xml)
            if command -v xmllint >/dev/null 2>&1; then
                if ! xmllint --noout "$file" 2>/dev/null; then
                    log_error "Invalid XML in: $file"
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# In validate_workflows():
for workflow_file in "$DEV_WORKFLOW_YAML" "$REVIEW_WORKFLOW_YAML"; do
    if ! validate_workflow_content "$workflow_file"; then
        ((missing++))
    fi
done
```

---

## BMAD Workflow Integration Gaps

The following modules in `scripts/epic-execute-lib/` use custom prompts instead of leveraging existing BMAD workflows. This creates inconsistency and misses the benefits of the established workflow patterns.

### W1. Design Phase Should Use BMAD Dev Workflow

**File:** `scripts/epic-execute-lib/design-phase.sh`

**Current State:** Uses a custom prompt for design planning.

**Recommended Change:** The design phase should invoke the BMAD dev-story workflow in "plan mode" or leverage a dedicated design workflow.

**Available BMAD Workflows:**
- `src/modules/bmm/workflows/4-implementation/dev-story/workflow.yaml` - Has planning steps
- Consider creating a dedicated `design-review` workflow

**Implementation:**
```bash
execute_design_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log ">>> DESIGN PHASE: $story_id (using BMAD dev-story workflow in plan mode)"

    # Load BMAD workflow components
    local workflow_yaml=$(cat "$DEV_WORKFLOW_YAML")
    local workflow_instructions=$(cat "$DEV_WORKFLOW_INSTRUCTIONS")
    local workflow_executor=$(cat "$WORKFLOW_EXECUTOR")
    local story_contents=$(cat "$story_file")

    # Build design prompt using BMAD workflow structure
    local design_prompt="You are executing a BMAD dev-story workflow in DESIGN-ONLY mode.

## Workflow Execution Context

You are running the BMAD dev-story workflow to CREATE AN IMPLEMENTATION PLAN ONLY.
Do NOT write any code. Output only your design plan.

### CRITICAL DESIGN-ONLY RULES
- Do NOT implement any code
- Do NOT create or modify files
- Execute ONLY the planning/design steps of the workflow
- Output a detailed implementation plan

## Workflow Executor Engine

<workflow-executor>
$workflow_executor
</workflow-executor>

## Dev-Story Workflow Configuration

<workflow-yaml>
$workflow_yaml
</workflow-yaml>

## Dev-Story Workflow Instructions

<workflow-instructions>
$workflow_instructions
</workflow-instructions>

## Story to Plan

**Story Path:** $story_file
**Story ID:** $story_id

<story-contents>
$story_contents
</story-contents>

## Required Output

Output your implementation plan in the DESIGN START/END format, then:
DESIGN COMPLETE: $story_id"

    # ... rest of execution
}
```

---

### W2. TDD Flow Should Use BMAD TestArch ATDD Workflow

**File:** `scripts/epic-execute-lib/tdd-flow.sh`

**Current State:** Uses custom prompts for test specification and implementation.

**Available BMAD Workflows:**
- `src/modules/bmm/workflows/testarch/atdd/workflow.yaml` - Acceptance Test Driven Development
- `src/modules/bmm/workflows/testarch/test-design/workflow.yaml` - Test design planning

**Recommended Change:**
- `execute_test_spec_phase()` should invoke `testarch/test-design` or `testarch/atdd` workflow
- `execute_test_impl_phase()` should invoke `testarch/atdd` workflow

**Implementation:**
```bash
# In tdd-flow.sh

# Workflow paths
ATDD_WORKFLOW_DIR="$BMAD_SRC_DIR/src/modules/bmm/workflows/testarch/atdd"
ATDD_WORKFLOW_YAML="$ATDD_WORKFLOW_DIR/workflow.yaml"
ATDD_INSTRUCTIONS="$ATDD_WORKFLOW_DIR/instructions.md"
ATDD_CHECKLIST="$ATDD_WORKFLOW_DIR/checklist.md"

TEST_DESIGN_WORKFLOW_DIR="$BMAD_SRC_DIR/src/modules/bmm/workflows/testarch/test-design"
TEST_DESIGN_WORKFLOW_YAML="$TEST_DESIGN_WORKFLOW_DIR/workflow.yaml"
TEST_DESIGN_INSTRUCTIONS="$TEST_DESIGN_WORKFLOW_DIR/instructions.md"

execute_test_spec_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log ">>> TEST SPEC PHASE: $story_id (using BMAD testarch/test-design workflow)"

    # Load BMAD workflow components
    local workflow_yaml=""
    local workflow_instructions=""

    if [ -f "$TEST_DESIGN_WORKFLOW_YAML" ]; then
        workflow_yaml=$(cat "$TEST_DESIGN_WORKFLOW_YAML")
    fi
    if [ -f "$TEST_DESIGN_INSTRUCTIONS" ]; then
        workflow_instructions=$(cat "$TEST_DESIGN_INSTRUCTIONS")
    fi

    local workflow_executor=$(cat "$WORKFLOW_EXECUTOR")
    local story_contents=$(cat "$story_file")

    local spec_prompt="You are executing a BMAD testarch/test-design workflow in automated mode.

## Workflow Execution Context

You are running the BMAD test-design workflow to generate test specifications.
This is EPIC-LEVEL mode for story: $story_id

### CRITICAL AUTOMATION RULES
- Do NOT pause for user confirmation
- Generate BDD-style test specifications
- Do NOT write test code yet
- Output specifications in the TEST SPEC START/END format

## Workflow Executor Engine

<workflow-executor>
$workflow_executor
</workflow-executor>

## Test-Design Workflow Configuration

<workflow-yaml>
$workflow_yaml
</workflow-yaml>

## Test-Design Workflow Instructions

<workflow-instructions>
$workflow_instructions
</workflow-instructions>

## Story to Analyze

<story>
$story_contents
</story>

## Completion Signal

TEST SPEC COMPLETE: $story_id - Generated N specifications"

    # ... rest of execution
}

execute_test_impl_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log ">>> TEST IMPL PHASE: $story_id (using BMAD testarch/atdd workflow)"

    # Load BMAD ATDD workflow
    local workflow_yaml=""
    local workflow_instructions=""
    local workflow_checklist=""

    if [ -f "$ATDD_WORKFLOW_YAML" ]; then
        workflow_yaml=$(cat "$ATDD_WORKFLOW_YAML")
    fi
    if [ -f "$ATDD_INSTRUCTIONS" ]; then
        workflow_instructions=$(cat "$ATDD_INSTRUCTIONS")
    fi
    if [ -f "$ATDD_CHECKLIST" ]; then
        workflow_checklist=$(cat "$ATDD_CHECKLIST")
    fi

    # ... build prompt using ATDD workflow structure
}
```

---

### W3. Test Quality Phase Should Use BMAD TestArch Test-Review Workflow

**File:** `scripts/epic-execute.sh:1694-1819` (execute_test_quality_phase)

**Current State:** Uses custom prompt for test quality review.

**Available BMAD Workflow:**
- `src/modules/bmm/workflows/testarch/test-review/workflow.yaml` - Test quality review with best practices

**Recommended Change:** `execute_test_quality_phase()` should invoke the `testarch/test-review` workflow.

**Implementation:**
```bash
# Add workflow paths
TEST_REVIEW_WORKFLOW_DIR="$WORKFLOWS_DIR/../testarch/test-review"
TEST_REVIEW_WORKFLOW_YAML="$TEST_REVIEW_WORKFLOW_DIR/workflow.yaml"
TEST_REVIEW_INSTRUCTIONS="$TEST_REVIEW_WORKFLOW_DIR/instructions.md"
TEST_REVIEW_CHECKLIST="$TEST_REVIEW_WORKFLOW_DIR/checklist.md"

execute_test_quality_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    LAST_TEST_QUALITY_ISSUES=""

    log ">>> TEST QUALITY: $story_id (using BMAD testarch/test-review workflow)"

    # Load BMAD workflow components
    local workflow_yaml=""
    local workflow_instructions=""
    local workflow_checklist=""

    if [ -f "$TEST_REVIEW_WORKFLOW_YAML" ]; then
        workflow_yaml=$(cat "$TEST_REVIEW_WORKFLOW_YAML")
    fi
    if [ -f "$TEST_REVIEW_INSTRUCTIONS" ]; then
        workflow_instructions=$(cat "$TEST_REVIEW_INSTRUCTIONS")
    fi
    if [ -f "$TEST_REVIEW_CHECKLIST" ]; then
        workflow_checklist=$(cat "$TEST_REVIEW_CHECKLIST")
    fi

    local story_contents=$(cat "$story_file")

    local quality_prompt="You are executing a BMAD testarch/test-review workflow in automated mode.

## Workflow Execution Context

You are running the BMAD test-review workflow to review test quality for: $story_id
Review scope: single story

### CRITICAL AUTOMATION RULES
- Do NOT pause for user confirmation
- Execute the full quality review
- Fix CRITICAL and HIGH issues automatically
- Document MEDIUM and LOW issues

## Workflow Configuration

<workflow-yaml>
$workflow_yaml
</workflow-yaml>

## Test-Review Workflow Instructions

<workflow-instructions>
$workflow_instructions
</workflow-instructions>

## Validation Checklist

<checklist>
$workflow_checklist
</checklist>

## Story Context

<story>
$story_contents
</story>

## Completion Signals

If quality approved (score >= 70):
Output: TEST QUALITY APPROVED: $story_id - Score: N/100

If quality failed (score < 60):
Output: TEST QUALITY FAILED: $story_id - Score: N/100"

    # ... rest of execution
}
```

---

### W4. Traceability Phase Should Use BMAD TestArch Trace Workflow

**File:** `scripts/epic-execute.sh:1821-1960` (execute_traceability_phase)

**Current State:** Uses custom prompt for traceability analysis.

**Available BMAD Workflow:**
- `src/modules/bmm/workflows/testarch/trace/workflow.yaml` - Requirements traceability

**Recommended Change:** `execute_traceability_phase()` should invoke the `testarch/trace` workflow.

---

## Implementation Priority

### Phase 1: Critical Fixes (Immediate)

| ID | Issue | Effort | Risk if Unfixed |
|----|-------|--------|-----------------|
| C1 | Path Resolution | Low | Script fails in different directories |
| C2 | Module Loading | Low | Silent failures, missing functions |
| C3 | EPIC_ID Validation | Low | Crashes on non-numeric input |
| C4 | Claude Timeout | Medium | Indefinite hangs |
| C5 | JSON Extraction | Medium | Failed parsing, missed completions |

### Phase 2: High-Priority ✅ COMPLETE

| ID | Issue | Effort | Status |
|----|-------|--------|--------|
| H1 | Git Add Safety | Low | ✅ Done (commit `ce2f9fb3`) |
| H2 | Cleanup Handler | Medium | ✅ Done (commit `ce2f9fb3`) |
| H3 | Test Count Parsing | Medium | ✅ Done (commit `ce2f9fb3`) |
| H4 | Story Discovery | Low | ✅ Done (commit `ce2f9fb3`) |
| H5 | Prompt Size Limits | Medium | ✅ Done (commit `ce2f9fb3`) |

### Phase 3: BMAD Workflow Integration (Medium-term)

| ID | Integration | Effort | Benefit |
|----|-------------|--------|---------|
| W1 | Design Phase + Dev Workflow | Medium | Consistency with BMAD patterns |
| W2 | TDD + ATDD Workflow | High | Leverage test-design knowledge base |
| W3 | Test Quality + Test-Review | Medium | Better test quality detection |
| W4 | Traceability + Trace Workflow | Medium | Consistent traceability format |

### Phase 4: Medium Priority ✅ COMPLETE

| ID | Improvement | Effort | Status |
|----|-------------|--------|--------|
| M1 | Retry Logic | Medium | ✅ Done |
| M2 | yq Version Check | Low | ✅ Done |
| M3 | Fuzzy Completion Detection | Medium | ✅ Done |
| M4 | Cross-platform sed | Low | ✅ Done |
| M5 | Branch Protection | Low | ✅ Done |

### Phase 5: Low Priority ✅ COMPLETE

| ID | Improvement | Effort | Status |
|----|-------------|--------|--------|
| L1 | Progress Persistence / Resume | Medium | ✅ Done |
| L2 | --help Option | Low | ✅ Done |
| L3 | Verbose Claude Output | Low | ✅ Done |
| L4 | Metrics File Archival | Low | ✅ Done |
| L5 | Workflow Content Validation | Medium | ✅ Done |

---

## Conclusion

The epic-execute library has a solid architecture with multi-phase validation and self-healing fix loops. The following improvements have been implemented:

### Completed
- ✅ **High-Priority Issues (5)** - All fixed (H1-H5) in commit `ce2f9fb3`
- ✅ **Medium-Priority Issues (5)** - All fixed (M1-M5) via new `utils.sh` module
- ✅ **Low-Priority Issues (5)** - All fixed (L1-L5) for better UX

### Remaining
- ⏳ **Critical Issues (5)** - Must be fixed to ensure basic reliability
- ⏳ **BMAD Integration Gaps (4)** - Custom prompts should leverage existing workflows for consistency

### Implementation Summary

**New Module: `scripts/epic-execute-lib/utils.sh`**
- M1: `execute_with_retry()` - Exponential backoff for transient failures
- M2: `validate_yq()` - Detects Go vs Python yq versions
- M3: `check_phase_completion_fuzzy()` - Case-insensitive pattern matching
- M4: `sed_inplace()` / `sed_inplace_backup()` - Cross-platform sed
- M5: `check_branch_protection()` - Prevents commits to main/master
- L1: `load_checkpoint()` / `save_checkpoint()` / `clear_checkpoint()` - Resume capability
- L3: `execute_claude_verbose()` - Verbose Claude output streaming
- L5: `validate_yaml_content()` / `validate_xml_content()` / `validate_workflow_content()` - Content validation

**Updated Files:**
- `scripts/epic-execute.sh` - Sources utils.sh, uses cross-platform sed, branch protection on startup, --help option, --resume flag, metrics archival, workflow content validation
- `scripts/epic-execute-lib/json-output.sh` - Enhanced JSON extraction, fuzzy matching fallback

The epic-execute script is now more reliable with better error handling, cross-platform support, safety checks, and improved UX.
