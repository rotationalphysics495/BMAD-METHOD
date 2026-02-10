#!/bin/bash
#
# BMAD Epic Execute - Test Failure Filter Module
#
# Provides functions to:
# 1. Extract only failure details from test output (not passing tests)
# 2. Capture baseline failures before story execution
# 3. Compare to identify new failures introduced by current story
#
# This prevents prompt size explosion and focuses fix phases on relevant failures.
#
# Usage: Sourced by epic-execute.sh
#

# =============================================================================
# Test Failure Filter Variables
# =============================================================================

BASELINE_TEST_FAILURES=""
BASELINE_FAILURE_COUNT=0
TEST_FILTER_INITIALIZED=false

# Maximum size for test failure output in fix prompts (in bytes)
MAX_TEST_FAILURE_SIZE="${MAX_TEST_FAILURE_SIZE:-50000}"  # 50KB default

# =============================================================================
# Test Output Filtering Functions
# =============================================================================

# Extract only failure-related output from test results
# Filters out passing test lines, keeps:
#   - FAIL lines and their details
#   - Error messages and stack traces
#   - Summary lines
# Arguments:
#   $1 - full test output
# Returns: filtered output (echoed)
extract_test_failures() {
    local test_output="$1"
    local filtered=""

    # For Vitest/Jest/turbo output, use a more targeted extraction
    # We want:
    # 1. Lines containing "FAIL " (test failures)
    # 2. Lines with AssertionError or expected/received blocks
    # 3. Error location lines (file:line references)
    # 4. The final summary line
    #
    # We DO NOT want:
    # - Passing test lines (✓)
    # - stderr warnings (React warnings, etc.)
    # - Full stack traces from passing tests

    # Extract actual FAIL test blocks with their assertion errors
    # Use awk to capture FAIL blocks more intelligently
    filtered=$(echo "$test_output" | awk '
        BEGIN { in_fail_block = 0; fail_count = 0 }

        # Start of a FAIL block - the actual failure report, not stderr
        /^@.*:test:[[:space:]]+FAIL[[:space:]]/ {
            in_fail_block = 1
            fail_count++
            print
            next
        }

        # Assertion details (expected vs received)
        /AssertionError:|expected.*to be|Expected|Received|expected.*to equal/ {
            print
            next
        }

        # Error location with line numbers
        /❯.*:[0-9]+:[0-9]+/ {
            print
            next
        }

        # Source code context (numbered lines around error)
        /^@.*:test:[[:space:]]+[0-9]+\|/ {
            if (in_fail_block) print
            next
        }

        # Keep the comparison markers
        /^@.*:test:[[:space:]]+-[[:space:]]/ { if (in_fail_block) print; next }
        /^@.*:test:[[:space:]]+\+[[:space:]]/ { if (in_fail_block) print; next }

        # End of fail block indicators
        /^@.*:test:[[:space:]]+⎯⎯⎯/ {
            if (in_fail_block) print
            in_fail_block = 0
            next
        }

        # Summary lines - always keep
        /Test Files.*failed|Tests.*failed/ {
            print
            next
        }

        # Blank line ends a fail block context
        /^[[:space:]]*$/ {
            if (in_fail_block && fail_count > 0) {
                in_fail_block = 0
            }
        }
    ')

    # If awk filtering produced too little, fall back to grep
    local line_count
    line_count=$(echo "$filtered" | wc -l | tr -d ' ')

    if [ "$line_count" -lt 5 ]; then
        # Minimal grep fallback - just get FAIL lines and summary
        filtered=$(echo "$test_output" | grep -E \
            "^@.*FAIL[[:space:]]|Test Files.*failed|Tests.*failed|AssertionError" \
            2>/dev/null || echo "")
    fi

    # Always include the final summary line if present
    local summary
    summary=$(echo "$test_output" | grep -E "Test Files.*[0-9]+ failed.*Tests.*[0-9]+ failed" | tail -1)
    if [ -n "$summary" ]; then
        # Check if summary is already in filtered output
        if ! echo "$filtered" | grep -qF "$summary"; then
            filtered="$filtered"$'\n\n'"$summary"
        fi
    fi

    echo "$filtered"
}

# Extract failure signatures for comparison
# Returns a sorted, deduplicated list of failing test identifiers
# Arguments:
#   $1 - test output
# Returns: sorted failure signatures (one per line)
extract_failure_signatures() {
    local test_output="$1"

    # Extract test identifiers from FAIL lines
    # Handles formats like:
    #   FAIL  src/path/file.test.ts > Suite > Test Name
    #   FAIL  src/path/file.test.ts
    #   @revive/web:test:  FAIL  src/path/file.test.ts (turbo output)
    # The pattern matches FAIL anywhere in line (handles turbo prefix)
    printf '%s\n' "$test_output" | grep -E "[[:space:]]FAIL[[:space:]]+" | \
        sed 's/^.*FAIL[[:space:]]*//' | \
        sort -u
}

# =============================================================================
# Baseline Management Functions
# =============================================================================

# Capture current test failure state as baseline before story execution
# Should be called at the start of each story's dev phase
# Arguments:
#   $1 - story_id (for logging)
capture_failure_baseline() {
    local story_id="${1:-unknown}"

    if [ -z "$PROJECT_ROOT" ]; then
        log_warn "Cannot capture failure baseline: PROJECT_ROOT not set"
        return 1
    fi

    log "Capturing test failure baseline for $story_id..."

    local test_output=""

    # Run tests and capture output
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        if grep -q '"test"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
            test_output=$(cd "$PROJECT_ROOT" && npm test 2>&1) || true
        fi
    elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        test_output=$(cd "$PROJECT_ROOT" && cargo test 2>&1) || true
    elif [ -f "$PROJECT_ROOT/go.mod" ]; then
        test_output=$(cd "$PROJECT_ROOT" && go test ./... 2>&1) || true
    elif [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        if command -v pytest >/dev/null 2>&1; then
            test_output=$(cd "$PROJECT_ROOT" && pytest 2>&1) || true
        fi
    fi

    # Extract and store baseline failures
    BASELINE_TEST_FAILURES=$(extract_failure_signatures "$test_output")
    # Count non-empty lines - use wc -l and trim whitespace for clean integer
    if [ -z "$BASELINE_TEST_FAILURES" ]; then
        BASELINE_FAILURE_COUNT=0
    else
        BASELINE_FAILURE_COUNT=$(printf '%s\n' "$BASELINE_TEST_FAILURES" | grep -c . 2>/dev/null || echo "0")
        BASELINE_FAILURE_COUNT=$(echo "$BASELINE_FAILURE_COUNT" | tr -d '[:space:]')
    fi
    TEST_FILTER_INITIALIZED=true

    if [ "$BASELINE_FAILURE_COUNT" -gt 0 ]; then
        log_warn "Baseline has $BASELINE_FAILURE_COUNT pre-existing test failures"
    else
        log "Baseline captured: no pre-existing failures"
    fi

    return 0
}

# Compare current failures against baseline and return only NEW failures
# Arguments:
#   $1 - current test output
# Returns: filtered output containing only new failures
get_new_failures_only() {
    local current_output="$1"

    if [ "$TEST_FILTER_INITIALIZED" != true ]; then
        # No baseline - return all failures (filtered for size)
        extract_test_failures "$current_output"
        return 0
    fi

    # Get current failure signatures
    local current_signatures
    current_signatures=$(extract_failure_signatures "$current_output")

    # Find signatures that are in current but not in baseline (new failures)
    local new_signatures
    new_signatures=$(comm -13 \
        <(echo "$BASELINE_TEST_FAILURES" | sort) \
        <(echo "$current_signatures" | sort) \
    2>/dev/null || echo "$current_signatures")

    local new_count
    if [ -z "$new_signatures" ]; then
        new_count=0
    else
        new_count=$(printf '%s\n' "$new_signatures" | grep -c . 2>/dev/null || echo "0")
        new_count=$(echo "$new_count" | tr -d '[:space:]')
    fi

    if [ "$new_count" -eq 0 ]; then
        # No new failures - all failures are pre-existing
        echo "[INFO] All $BASELINE_FAILURE_COUNT failures are pre-existing from baseline."
        echo "No new failures introduced by this story."
        return 0
    fi

    # Extract full failure details for only the new failures
    local filtered_output=""
    local full_failures
    full_failures=$(extract_test_failures "$current_output")

    # For each new failure signature, include its full output
    while IFS= read -r sig; do
        [ -z "$sig" ] && continue
        # Escape special regex characters in signature
        local escaped_sig
        escaped_sig=$(printf '%s' "$sig" | sed 's/[[\.*^$()+?{|]/\\&/g')
        # Extract the block for this failure
        local block
        block=$(echo "$full_failures" | grep -A 50 "$escaped_sig" | head -60)
        if [ -n "$block" ]; then
            filtered_output+="$block"$'\n\n'
        fi
    done <<< "$new_signatures"

    # Add summary
    local total_current
    if [ -z "$current_signatures" ]; then
        total_current=0
    else
        total_current=$(printf '%s\n' "$current_signatures" | grep -c . 2>/dev/null || echo "0")
        total_current=$(echo "$total_current" | tr -d '[:space:]')
    fi
    filtered_output+="
---
**Failure Summary:**
- New failures (this story): $new_count
- Pre-existing failures (baseline): $BASELINE_FAILURE_COUNT
- Total current failures: $total_current

Only the $new_count NEW failures above need to be fixed by this story.
Pre-existing failures from the baseline have been filtered out.
"

    echo "$filtered_output"
}

# =============================================================================
# Truncation Functions
# =============================================================================

# Truncate test failure output to fit within size limits
# Preserves most relevant information (summary, first failures)
# Arguments:
#   $1 - failure output
#   $2 - max size (optional, defaults to MAX_TEST_FAILURE_SIZE)
# Returns: truncated output
truncate_test_failures() {
    local failures="$1"
    local max_size="${2:-$MAX_TEST_FAILURE_SIZE}"

    local current_size
    current_size=$(printf '%s' "$failures" | wc -c | tr -d ' ')

    if [ "$current_size" -le "$max_size" ]; then
        printf '%s' "$failures"
        return 0
    fi

    # Truncate but preserve summary at the end
    local summary
    summary=$(echo "$failures" | tail -20)

    local available=$((max_size - ${#summary} - 200))  # Reserve space for summary + notice

    local truncated
    truncated=$(printf '%s' "$failures" | head -c "$available")

    printf '%s\n\n... [TEST OUTPUT TRUNCATED: %sB total, showing first %sB + summary] ...\n\n%s' \
        "$truncated" "$current_size" "$available" "$summary"
}

# =============================================================================
# Main Filter Function (Used by Static Analysis Gate)
# =============================================================================

# Filter and prepare test failures for fix-phase prompt
# Combines all filtering: extracts failures, compares to baseline, truncates
# Arguments:
#   $1 - full test output
#   $2 - story_id (for logging)
# Returns: filtered, truncated failure output suitable for fix prompt
prepare_test_failures_for_fix() {
    local test_output="$1"
    local story_id="${2:-unknown}"

    # Step 1: Get only new failures (if baseline exists)
    local new_failures
    new_failures=$(get_new_failures_only "$test_output")

    # Step 2: Truncate if still too large
    local final_output
    final_output=$(truncate_test_failures "$new_failures")

    local final_size
    final_size=$(printf '%s' "$final_output" | wc -c | tr -d ' ')

    [ "$VERBOSE" = true ] && log "Test failure output for $story_id: ${final_size}B (limit: ${MAX_TEST_FAILURE_SIZE}B)"

    printf '%s' "$final_output"
}

# Count NEW test failures (not in baseline)
# Used by static analysis gate to decide pass/fail
# Arguments:
#   $1 - full test output
# Returns: count of NEW failures (0 if all failures are pre-existing)
count_new_test_failures() {
    local test_output="$1"

    if [ "$TEST_FILTER_INITIALIZED" != true ]; then
        # No baseline - count all failures
        local all_signatures
        all_signatures=$(extract_failure_signatures "$test_output")
        if [ -z "$all_signatures" ]; then
            echo "0"
        else
            printf '%s\n' "$all_signatures" | grep -c . 2>/dev/null || echo "0"
        fi
        return 0
    fi

    # Get current failure signatures
    local current_signatures
    current_signatures=$(extract_failure_signatures "$test_output")

    # Find signatures that are in current but not in baseline (new failures)
    local new_signatures
    new_signatures=$(comm -13 \
        <(printf '%s\n' "$BASELINE_TEST_FAILURES" | sort) \
        <(printf '%s\n' "$current_signatures" | sort) \
    2>/dev/null || echo "")

    if [ -z "$new_signatures" ]; then
        echo "0"
    else
        local count
        count=$(printf '%s\n' "$new_signatures" | grep -c . 2>/dev/null || echo "0")
        echo "$count" | tr -d '[:space:]'
    fi
}
