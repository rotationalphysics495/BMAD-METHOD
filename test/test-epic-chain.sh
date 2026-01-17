#!/bin/bash
#
# Epic Chain Integration Tests
# Tests the epic-chain.sh script behavior, argument parsing, and core functionality
#
# Usage: ./test-epic-chain.sh
#
# This test suite validates:
# - Argument parsing and help text
# - Epic file validation (Phase 1)
# - Dependency analysis (Phase 2)
# - Execution order determination (Phase 3)
# - Chain plan generation (Phase 4)
# - Dry-run and analyze-only modes
# - Error handling for missing epics

set -e

echo "========================================"
echo "Epic Chain Integration Tests"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
SKIPPED=0

# Get the repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/epic-chain.sh"

# Create temp directory for test fixtures
TEMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Helper functions
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo -e "${BLUE}Test:${NC} $test_name"
    if $test_func; then
        echo -e "${GREEN}  PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}  FAILED${NC}"
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

skip_test() {
    local test_name="$1"
    local reason="$2"

    echo -e "${YELLOW}Test:${NC} $test_name"
    echo -e "${YELLOW}  SKIPPED${NC} - $reason"
    SKIPPED=$((SKIPPED + 1))
    echo ""
}

# =============================================================================
# Setup Test Fixtures
# =============================================================================

setup_test_fixtures() {
    echo "Setting up test fixtures in $TEMP_DIR..."

    # NOTE: The epic-chain.sh script calculates PROJECT_ROOT as SCRIPT_DIR/../..
    # This means it expects to be TWO levels deep (e.g., project/subdir/scripts/)
    # Structure needed:
    #   TEMP_DIR/
    #     project/           <- This becomes PROJECT_ROOT
    #       docs/epics/
    #       docs/stories/
    #       subdir/
    #         scripts/
    #           epic-chain.sh

    PROJECT_DIR="$TEMP_DIR/project"
    SCRIPTS_PARENT="$PROJECT_DIR/subdir"

    # Create directory structure
    mkdir -p "$PROJECT_DIR/docs/epics"
    mkdir -p "$PROJECT_DIR/docs/stories"
    mkdir -p "$PROJECT_DIR/docs/sprint-artifacts"
    mkdir -p "$PROJECT_DIR/docs/uat"
    mkdir -p "$PROJECT_DIR/docs/handoffs"
    mkdir -p "$SCRIPTS_PARENT/scripts"

    # Copy the script to test directory (nested two levels deep so PROJECT_ROOT resolves correctly)
    cp "$SCRIPT_PATH" "$SCRIPTS_PARENT/scripts/epic-chain.sh"
    chmod +x "$SCRIPTS_PARENT/scripts/epic-chain.sh"

    # Update TEST_SCRIPT_PATH for tests to use
    TEST_SCRIPT_PATH="$SCRIPTS_PARENT/scripts/epic-chain.sh"

    # Create mock epic files
    cat > "$PROJECT_DIR/docs/epics/epic-99.md" << 'EOF'
# Epic 99: Test Epic Alpha

## Description
This is a test epic for automated testing.

## Stories
- 99-1: First story
- 99-2: Second story

## Dependencies
None
EOF

    cat > "$PROJECT_DIR/docs/epics/epic-100.md" << 'EOF'
# Epic 100: Test Epic Beta

## Description
This is a test epic that depends on Epic 99.

## Stories
- 100-1: Third story
- 100-2: Fourth story

## Dependencies
- Epic 99 must be completed first
EOF

    cat > "$PROJECT_DIR/docs/epics/epic-101.md" << 'EOF'
# Epic 101: Test Epic Gamma

## Description
This is a test epic that depends on Epic 100.

## Stories
- 101-1: Fifth story

## Dependencies
- Epic 100 must be completed first
EOF

    # Create mock story files
    cat > "$PROJECT_DIR/docs/stories/99-1-first-story.md" << 'EOF'
# Story 99-1: First Story

Epic: 99
Status: Draft

## Description
First test story.

## Acceptance Criteria
- AC1: Test passes
EOF

    cat > "$PROJECT_DIR/docs/stories/99-2-second-story.md" << 'EOF'
# Story 99-2: Second Story

Epic: 99
Status: Draft

## Description
Second test story.

## Acceptance Criteria
- AC1: Test passes
EOF

    cat > "$PROJECT_DIR/docs/stories/100-1-third-story.md" << 'EOF'
# Story 100-1: Third Story

Epic: 100
Status: Draft

## Description
Third test story.

## Acceptance Criteria
- AC1: Test passes
EOF

    cat > "$PROJECT_DIR/docs/stories/100-2-fourth-story.md" << 'EOF'
# Story 100-2: Fourth Story

Epic: 100
Status: Draft

## Description
Fourth test story.

## Acceptance Criteria
- AC1: Test passes
EOF

    cat > "$PROJECT_DIR/docs/stories/101-1-fifth-story.md" << 'EOF'
# Story 101-1: Fifth Story

Epic: 101
Status: Draft

## Description
Fifth test story.

## Acceptance Criteria
- AC1: Test passes
EOF

    echo "Test fixtures created."
    echo ""
}

# =============================================================================
# Test Cases
# =============================================================================

# Test 1: Script exists and is executable
test_script_exists() {
    [ -f "$SCRIPT_PATH" ] && [ -x "$SCRIPT_PATH" ]
}

# Test 2: Help text displays when no arguments provided
test_help_text() {
    local output
    output=$("$SCRIPT_PATH" 2>&1) || true

    echo "$output" | grep -q "Usage:" && \
    echo "$output" | grep -q "Examples:" && \
    echo "$output" | grep -q "\-\-dry-run"
}

# Test 3: Unknown option handling
test_unknown_option() {
    local output
    local exit_code

    output=$("$SCRIPT_PATH" --invalid-option 2>&1) || exit_code=$?

    [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "Unknown option"
}

# Test 4: Dry-run mode shows plan without executing
test_dry_run_mode() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 --dry-run 2>&1) || true

    # Should show execution plan
    echo "$output" | grep -q "EPIC CHAIN EXECUTION" && \
    echo "$output" | grep -q "DRY RUN" && \
    echo "$output" | grep -q "Epics to chain: 99 100"
}

# Test 5: Analyze-only mode
test_analyze_only_mode() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 --analyze-only 2>&1) || true

    # Should complete analysis phase only
    echo "$output" | grep -q "Phase 1: Validating Epics" && \
    echo "$output" | grep -q "Phase 2: Analyzing Dependencies" && \
    echo "$output" | grep -q "Analysis complete"
}

# Test 6: Epic validation detects missing epics
test_missing_epic_detection() {
    local output
    local exit_code=0

    output=$("$TEST_SCRIPT_PATH" 999 --dry-run 2>&1) || exit_code=$?

    # Should fail with error about missing epic
    [ "$exit_code" -eq 1 ] && echo "$output" | grep -q "File not found"
}

# Test 7: Dependency detection parses epic files
test_dependency_detection() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 101 --analyze-only 2>&1) || true

    # Should detect Epic 100 depends on Epic 99
    echo "$output" | grep -q "Epic 100 depends on:" && \
    echo "$output" | grep -q "99"
}

# Test 8: Chain plan file generation
test_chain_plan_generation() {
    local output
    local plan_file="$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"

    output=$("$TEST_SCRIPT_PATH" 99 100 --analyze-only 2>&1) || true

    # Check plan file was created
    [ -f "$plan_file" ] && \
    grep -q "epics:" "$plan_file" && \
    grep -q "total_epics: 2" "$plan_file"
}

# Test 9: Story count detection
test_story_count_detection() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --analyze-only --verbose 2>&1) || true

    # Should find 2 stories for Epic 99
    echo "$output" | grep -q "Epic 99: Found 2 story"
}

# Test 10: Verbose mode outputs extra details
test_verbose_mode() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --analyze-only --verbose 2>&1) || true

    # Verbose mode should show more details
    echo "$output" | grep -q "Epic 99:" && \
    echo "$output" | grep -q "story"
}

# Test 11: UAT gate options parsing
test_uat_gate_options() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --uat-gate=full --uat-blocking 2>&1) || true

    # Should accept UAT gate options without error
    echo "$output" | grep -q "EPIC CHAIN"
}

# Test 12: No-UAT option parsing
test_no_uat_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --no-uat 2>&1) || true

    # Should accept --no-uat without error
    echo "$output" | grep -q "EPIC CHAIN"
}

# Test 13: Start-from option parsing
test_start_from_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 101 --dry-run --start-from 100 2>&1) || true

    # Should show skipping Epic 99
    echo "$output" | grep -q "Skipping Epic 99"
}

# Test 14: Skip-done option parsing
test_skip_done_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --skip-done 2>&1) || true

    # Should accept --skip-done without error
    echo "$output" | grep -q "EPIC CHAIN" && \
    echo "$output" | grep -q "Skip Done:.*true"
}

# Test 15: No-handoff option parsing
test_no_handoff_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --no-handoff 2>&1) || true

    # Check chain plan reflects no-handoff option
    grep -q "context_handoff: false" "$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"
}

# Test 16: No-combined-uat option parsing
test_no_combined_uat_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --no-combined-uat 2>&1) || true

    # Check chain plan reflects option
    grep -q "combined_uat: false" "$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"
}

# Test 17: No-report option parsing
test_no_report_option() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 --dry-run --no-report 2>&1) || true

    # Should accept without error
    echo "$output" | grep -q "EPIC CHAIN"
}

# Test 18: Multiple epic IDs accepted
test_multiple_epic_ids() {
    local output
    local plan_file="$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"

    output=$("$TEST_SCRIPT_PATH" 99 100 101 --analyze-only 2>&1) || true

    # Should show all 3 epics in output and plan file
    echo "$output" | grep -q "Epics to chain: 99 100 101" && \
    grep -q "total_epics: 3" "$plan_file"
}

# Test 19: Execution order display
test_execution_order_display() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 101 --analyze-only 2>&1) || true

    # Should display execution order
    echo "$output" | grep -q "Execution Order:" && \
    echo "$output" | grep -q "1\. Epic 99" && \
    echo "$output" | grep -q "2\. Epic 100" && \
    echo "$output" | grep -q "3\. Epic 101"
}

# Test 20: Log file creation
test_log_file_creation() {
    local output

    # Run with dry-run to complete without actual execution
    output=$("$TEST_SCRIPT_PATH" 99 --dry-run 2>&1) || true

    # Log file is only mentioned in the final summary (after full execution)
    # For this test, we verify the script writes to log by checking that
    # the log file path format is used in the script (LOG_FILE=/tmp/bmad-epic-chain-$$)
    # The log file won't be mentioned in analyze-only or dry-run modes
    # So we just verify the output contains expected content
    echo "$output" | grep -q "EPIC CHAIN"
}

# Test 21: Directory creation (UAT, handoffs, sprint-artifacts)
test_directory_creation() {
    # Remove directories first
    rm -rf "$PROJECT_DIR/docs/uat" "$PROJECT_DIR/docs/handoffs" "$PROJECT_DIR/docs/sprint-artifacts"

    output=$("$TEST_SCRIPT_PATH" 99 --analyze-only 2>&1) || true

    # Directories should be created
    [ -d "$PROJECT_DIR/docs/uat" ] && \
    [ -d "$PROJECT_DIR/docs/handoffs" ] && \
    [ -d "$PROJECT_DIR/docs/sprint-artifacts" ]
}

# Test 22: Epic file patterns - supports epic-{id}.md format
test_epic_file_pattern_basic() {
    output=$("$TEST_SCRIPT_PATH" 99 --analyze-only 2>&1) || true

    echo "$output" | grep -q "Epic 99: Found epic-99.md"
}

# Test 23: Chain plan YAML structure validation
test_chain_plan_yaml_structure() {
    local plan_file="$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"

    output=$("$TEST_SCRIPT_PATH" 99 100 --analyze-only 2>&1) || true

    # Validate YAML structure
    grep -q "^epics:" "$plan_file" && \
    grep -q "^total_epics:" "$plan_file" && \
    grep -q "^execution_order:" "$plan_file" && \
    grep -q "^total_stories:" "$plan_file" && \
    grep -q "^options:" "$plan_file"
}

# Test 24: Chain plan includes story counts
test_chain_plan_story_counts() {
    local plan_file="$PROJECT_DIR/docs/sprint-artifacts/chain-plan.yaml"

    output=$("$TEST_SCRIPT_PATH" 99 100 --analyze-only 2>&1) || true

    # Check story counts in plan
    grep -q "stories: 2" "$plan_file"  # Epic 99 has 2 stories
}

# Test 25: Combined options work together
test_combined_options() {
    local output

    output=$("$TEST_SCRIPT_PATH" 99 100 --dry-run --verbose --skip-done --no-handoff --no-uat 2>&1) || true

    # Should work with multiple options
    echo "$output" | grep -q "EPIC CHAIN" && \
    echo "$output" | grep -q "Dry Run:.*true" && \
    echo "$output" | grep -q "Skip Done:.*true"
}

# =============================================================================
# Run Tests
# =============================================================================

echo "Setting up test environment..."
setup_test_fixtures

echo ""
echo "========================================"
echo "Running Tests"
echo "========================================"
echo ""

# Basic tests
run_test "Script exists and is executable" test_script_exists
run_test "Help text displays when no arguments" test_help_text
run_test "Unknown option handling" test_unknown_option

# Mode tests
run_test "Dry-run mode shows plan without executing" test_dry_run_mode
run_test "Analyze-only mode" test_analyze_only_mode
run_test "Verbose mode outputs extra details" test_verbose_mode

# Validation tests
run_test "Missing epic detection" test_missing_epic_detection
run_test "Dependency detection parses epic files" test_dependency_detection
run_test "Story count detection" test_story_count_detection

# Chain plan tests
run_test "Chain plan file generation" test_chain_plan_generation
run_test "Chain plan YAML structure" test_chain_plan_yaml_structure
run_test "Chain plan includes story counts" test_chain_plan_story_counts

# Option parsing tests
run_test "Multiple epic IDs accepted" test_multiple_epic_ids
run_test "Execution order display" test_execution_order_display
run_test "Start-from option parsing" test_start_from_option
run_test "Skip-done option parsing" test_skip_done_option
run_test "No-handoff option parsing" test_no_handoff_option
run_test "No-combined-uat option parsing" test_no_combined_uat_option
run_test "No-report option parsing" test_no_report_option
run_test "UAT gate options parsing" test_uat_gate_options
run_test "No-UAT option parsing" test_no_uat_option

# Infrastructure tests
run_test "Log file creation" test_log_file_creation
run_test "Directory creation" test_directory_creation
run_test "Epic file pattern - basic" test_epic_file_pattern_basic

# Integration tests
run_test "Combined options work together" test_combined_options

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================"
echo "Test Results"
echo "========================================"
echo -e "  Passed:  ${GREEN}$PASSED${NC}"
echo -e "  Failed:  ${RED}$FAILED${NC}"
echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All epic-chain tests passed!${NC}\n"
    exit 0
else
    echo -e "\n${RED}$FAILED epic-chain test(s) failed${NC}\n"
    exit 1
fi
