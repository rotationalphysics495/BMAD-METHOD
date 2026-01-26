#!/bin/bash
#
# BMAD Epic Execute - Regression Gate Module
#
# Provides functions to track test baselines and verify no regressions
# occur during epic execution.
#
# Usage: Sourced by epic-execute.sh
#

# =============================================================================
# Regression Gate Variables
# =============================================================================

BASELINE_PASSING_TESTS=0
BASELINE_COVERAGE=0
REGRESSION_INITIALIZED=false

# =============================================================================
# Regression Gate Functions
# =============================================================================

# Initialize regression baseline before epic starts
# Captures current test count and coverage (if available)
init_regression_baseline() {
    if [ -z "$PROJECT_ROOT" ]; then
        log_warn "Cannot initialize regression baseline: PROJECT_ROOT not set"
        return 1
    fi

    log "Initializing regression baseline..."

    # Detect project type and capture baseline
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        # Node.js/TypeScript project
        if grep -q '"test"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
            log "Capturing baseline test count..."
            local test_output
            test_output=$(cd "$PROJECT_ROOT" && npm test 2>&1) || true

            # Try multiple patterns to extract passing test count
            # Pattern 1: "X passing" (mocha/jest)
            BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE '[0-9]+ passing' | grep -oE '[0-9]+' | head -1 || echo "0")

            # Pattern 2: "Tests: X passed" (jest)
            if [ "$BASELINE_PASSING_TESTS" = "0" ]; then
                BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE 'Tests:.*[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || echo "0")
            fi

            # Pattern 3: "X tests passed" (generic)
            if [ "$BASELINE_PASSING_TESTS" = "0" ]; then
                BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE '[0-9]+ tests? passed' | grep -oE '[0-9]+' | head -1 || echo "0")
            fi

            log "Baseline passing tests: $BASELINE_PASSING_TESTS"
        fi

        # Capture baseline coverage if available
        if grep -q '"coverage"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
            log "Capturing baseline coverage..."
            local coverage_output
            coverage_output=$(cd "$PROJECT_ROOT" && npm run coverage -- --json 2>/dev/null) || true

            # Try to extract coverage percentage
            if command -v jq >/dev/null 2>&1; then
                BASELINE_COVERAGE=$(echo "$coverage_output" | jq '.total.lines.pct // 0' 2>/dev/null || echo "0")
            fi

            [ "$BASELINE_COVERAGE" != "0" ] && log "Baseline coverage: ${BASELINE_COVERAGE}%"
        fi

    elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        # Rust project
        log "Capturing baseline test count (Rust)..."
        local test_output
        test_output=$(cd "$PROJECT_ROOT" && cargo test 2>&1) || true
        BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || echo "0")
        log "Baseline passing tests: $BASELINE_PASSING_TESTS"

    elif [ -f "$PROJECT_ROOT/go.mod" ]; then
        # Go project
        log "Capturing baseline test count (Go)..."
        local test_output
        test_output=$(cd "$PROJECT_ROOT" && go test ./... -v 2>&1) || true
        BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -c "^--- PASS" || echo "0")
        log "Baseline passing tests: $BASELINE_PASSING_TESTS"

    elif [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        # Python project
        if command -v pytest >/dev/null 2>&1; then
            log "Capturing baseline test count (Python)..."
            local test_output
            test_output=$(cd "$PROJECT_ROOT" && pytest --co -q 2>&1) || true
            BASELINE_PASSING_TESTS=$(echo "$test_output" | grep -oE '[0-9]+ tests? collected' | grep -oE '[0-9]+' | head -1 || echo "0")
            log "Baseline test count: $BASELINE_PASSING_TESTS"
        fi
    fi

    REGRESSION_INITIALIZED=true
    log_success "Regression baseline initialized: $BASELINE_PASSING_TESTS tests"
    return 0
}

# Execute regression gate after a story completes
# Compares current test count against baseline
# Arguments:
#   $1 - story_id
execute_regression_gate() {
    local story_id="$1"

    if [ "$REGRESSION_INITIALIZED" != true ]; then
        log_warn "Regression gate skipped: baseline not initialized"
        return 0
    fi

    log ">>> REGRESSION GATE: $story_id"

    local current_tests=0

    # Get current test count based on project type
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        local test_output
        test_output=$(cd "$PROJECT_ROOT" && npm test 2>&1) || true

        current_tests=$(echo "$test_output" | grep -oE '[0-9]+ passing' | grep -oE '[0-9]+' | head -1 || echo "0")
        if [ "$current_tests" = "0" ]; then
            current_tests=$(echo "$test_output" | grep -oE 'Tests:.*[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || echo "0")
        fi
        if [ "$current_tests" = "0" ]; then
            current_tests=$(echo "$test_output" | grep -oE '[0-9]+ tests? passed' | grep -oE '[0-9]+' | head -1 || echo "0")
        fi

    elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        local test_output
        test_output=$(cd "$PROJECT_ROOT" && cargo test 2>&1) || true
        current_tests=$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || echo "0")

    elif [ -f "$PROJECT_ROOT/go.mod" ]; then
        local test_output
        test_output=$(cd "$PROJECT_ROOT" && go test ./... -v 2>&1) || true
        current_tests=$(echo "$test_output" | grep -c "^--- PASS" || echo "0")

    elif [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        if command -v pytest >/dev/null 2>&1; then
            local test_output
            test_output=$(cd "$PROJECT_ROOT" && pytest -v 2>&1) || true
            current_tests=$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | head -1 || echo "0")
        fi
    fi

    # Check for regression
    if [ "$current_tests" -lt "$BASELINE_PASSING_TESTS" ]; then
        log_error "REGRESSION DETECTED: Test count decreased ($BASELINE_PASSING_TESTS -> $current_tests)"
        add_metrics_issue "$story_id" "regression" "Test count decreased from $BASELINE_PASSING_TESTS to $current_tests"
        return 1
    fi

    # Update baseline for next story (allow growth)
    local previous_baseline=$BASELINE_PASSING_TESTS
    BASELINE_PASSING_TESTS=$current_tests

    log_success "Regression gate passed: $current_tests tests (baseline was $previous_baseline)"
    return 0
}
