#!/bin/bash
#
# BMAD Epic Execute - Automated Story Execution with Context Isolation
#
# Usage: ./epic-execute.sh <epic-id> [options]
#
# Options:
#   --dry-run       Show what would be executed without running
#   --skip-review   Skip code review phase (not recommended)
#   --no-commit     Stage changes but don't commit
#   --parallel      Run independent stories in parallel (experimental)
#   --verbose       Show detailed output
#   --start-from ID Start from a specific story (e.g., 31-2)
#   --skip-done     Skip stories with Status: Done
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BMAD_DIR="$PROJECT_ROOT/bmad"

STORIES_DIR="$PROJECT_ROOT/docs/stories"
SPRINT_ARTIFACTS_DIR="$PROJECT_ROOT/docs/sprint-artifacts"
SPRINTS_DIR="$PROJECT_ROOT/docs/sprints"
EPICS_DIR="$PROJECT_ROOT/docs/epics"
UAT_DIR="$PROJECT_ROOT/docs/uat"

LOG_FILE="/tmp/bmad-epic-execute-$$.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "${BLUE}[BMAD]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

# =============================================================================
# Metrics Functions
# =============================================================================

METRICS_DIR=""
METRICS_FILE=""

init_metrics() {
    METRICS_DIR="$SPRINT_ARTIFACTS_DIR/metrics"
    METRICS_FILE="$METRICS_DIR/epic-${EPIC_ID}-metrics.yaml"
    mkdir -p "$METRICS_DIR"

    local start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$METRICS_FILE" << EOF
epic_id: "$EPIC_ID"
execution:
  start_time: "$start_time"
  end_time: ""
  duration_seconds: 0
stories:
  total: 0
  completed: 0
  failed: 0
  skipped: 0
validation:
  gate_executed: false
  gate_status: "PENDING"
  fix_attempts: 0
issues: []
EOF

    log "Metrics initialized: $METRICS_FILE"
}

update_story_metrics() {
    local status="$1"  # completed|failed|skipped

    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        return
    fi

    # Check if yq is available for YAML manipulation
    if command -v yq >/dev/null 2>&1; then
        case "$status" in
            completed) yq -i '.stories.completed += 1' "$METRICS_FILE" ;;
            failed)    yq -i '.stories.failed += 1' "$METRICS_FILE" ;;
            skipped)   yq -i '.stories.skipped += 1' "$METRICS_FILE" ;;
        esac
    else
        # Fallback: log warning (metrics will be finalized at end)
        [ "$VERBOSE" = true ] && log_warn "yq not found - metrics update deferred"
    fi
}

add_metrics_issue() {
    local story_id="$1"
    local issue_type="$2"
    local message="$3"

    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        return
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v yq >/dev/null 2>&1; then
        yq -i ".issues += [{\"story\": \"$story_id\", \"type\": \"$issue_type\", \"message\": \"$message\", \"timestamp\": \"$timestamp\"}]" "$METRICS_FILE"
    fi
}

finalize_metrics() {
    local total_stories="$1"
    local completed="$2"
    local failed="$3"
    local skipped="$4"
    local duration="$5"

    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        return
    fi

    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v yq >/dev/null 2>&1; then
        yq -i ".execution.end_time = \"$end_time\"" "$METRICS_FILE"
        yq -i ".execution.duration_seconds = $duration" "$METRICS_FILE"
        yq -i ".stories.total = $total_stories" "$METRICS_FILE"
        yq -i ".stories.completed = $completed" "$METRICS_FILE"
        yq -i ".stories.failed = $failed" "$METRICS_FILE"
        yq -i ".stories.skipped = $skipped" "$METRICS_FILE"
    else
        # Fallback: rewrite the file with final values
        cat > "$METRICS_FILE" << EOF
epic_id: "$EPIC_ID"
execution:
  start_time: "$EPIC_START_TIME"
  end_time: "$end_time"
  duration_seconds: $duration
stories:
  total: $total_stories
  completed: $completed
  failed: $failed
  skipped: $skipped
validation:
  gate_executed: false
  gate_status: "PENDING"
  fix_attempts: 0
issues: []
EOF
    fi

    log "Metrics finalized: $METRICS_FILE"
}

# =============================================================================
# Argument Parsing
# =============================================================================

EPIC_ID=""
DRY_RUN=false
SKIP_REVIEW=false
NO_COMMIT=false
PARALLEL=false
VERBOSE=false
START_FROM=""
SKIP_DONE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-review)
            SKIP_REVIEW=true
            shift
            ;;
        --no-commit)
            NO_COMMIT=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --start-from)
            START_FROM="$2"
            shift 2
            ;;
        --skip-done)
            SKIP_DONE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            EPIC_ID="$1"
            shift
            ;;
    esac
done

if [ -z "$EPIC_ID" ]; then
    echo "Usage: $0 <epic-id> [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would be executed"
    echo "  --skip-review   Skip code review phase"
    echo "  --no-commit     Don't commit after stories"
    echo "  --parallel      Parallel execution (experimental)"
    echo "  --verbose       Detailed output"
    echo "  --start-from ID Start from a specific story (e.g., 31-2)"
    echo "  --skip-done     Skip stories with Status: Done"
    exit 1
fi

# =============================================================================
# Setup
# =============================================================================

log "Starting epic execution for: $EPIC_ID"
log "Project root: $PROJECT_ROOT"

# Ensure directories exist
mkdir -p "$UAT_DIR"
mkdir -p "$SPRINTS_DIR"

# Initialize metrics collection
EPIC_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EPIC_START_SECONDS=$(date +%s)
init_metrics

# Find epic file (supports both epic-39-*.md and epic-039-*.md formats)
EPIC_FILE=""
# Pad epic ID with leading zero for 3-digit format (e.g., 40 -> 040)
EPIC_ID_PADDED=$(printf "%03d" "$EPIC_ID" 2>/dev/null || echo "$EPIC_ID")
for pattern in "epic-${EPIC_ID}.md" "epic-${EPIC_ID}-"*.md "epic-${EPIC_ID_PADDED}-"*.md "epic-0${EPIC_ID}-"*.md "${EPIC_ID}.md"; do
    found=$(find "$EPICS_DIR" -name "$pattern" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        EPIC_FILE="$found"
        break
    fi
done

if [ -z "$EPIC_FILE" ] || [ ! -f "$EPIC_FILE" ]; then
    log_error "Epic file not found for: $EPIC_ID"
    log_error "Searched in: $EPICS_DIR"
    exit 1
fi

log "Found epic file: $EPIC_FILE"

# =============================================================================
# Discover Stories
# =============================================================================

log "Discovering stories..."

# Search multiple locations for story files
STORY_LOCATIONS=("$STORIES_DIR" "$SPRINT_ARTIFACTS_DIR" "$SPRINTS_DIR")
STORIES=()

for search_dir in "${STORY_LOCATIONS[@]}"; do
    if [ ! -d "$search_dir" ]; then
        continue
    fi
    
    # Method 1: Stories that reference this epic in content
    while IFS= read -r -d '' file; do
        if [[ ! " ${STORIES[*]} " =~ " ${file} " ]]; then
            STORIES+=("$file")
        fi
    done < <(grep -l -Z "Epic.*:.*${EPIC_ID}\|epic-${EPIC_ID}\|Epic.*${EPIC_ID}" "$search_dir"/*.md 2>/dev/null || true)
    
    # Method 2: {EpicNumber}-{StoryNumber}-{description}.md (e.g., 1-1-user-registration.md)
    while IFS= read -r -d '' file; do
        if [[ ! " ${STORIES[*]} " =~ " ${file} " ]]; then
            STORIES+=("$file")
        fi
    done < <(find "$search_dir" -name "${EPIC_ID}-*-*.md" -print0 2>/dev/null || true)
    
    # Method 3: story-{epic}.{seq}-*.md (BMAD standard)
    while IFS= read -r -d '' file; do
        if [[ ! " ${STORIES[*]} " =~ " ${file} " ]]; then
            STORIES+=("$file")
        fi
    done < <(find "$search_dir" -name "story-${EPIC_ID}.*-*.md" -print0 2>/dev/null || true)
    
    # Method 4: story-{epic}-*.md (BMAD alternate)
    while IFS= read -r -d '' file; do
        if [[ ! " ${STORIES[*]} " =~ " ${file} " ]]; then
            STORIES+=("$file")
        fi
    done < <(find "$search_dir" -name "story-${EPIC_ID}-*.md" -print0 2>/dev/null || true)
done

if [ ${#STORIES[@]} -eq 0 ]; then
    log_error "No stories found for epic: $EPIC_ID"
    log_error "Searched in: ${STORY_LOCATIONS[*]}"
    log_error "Looking for:"
    log_error "  - Files containing 'Epic: $EPIC_ID'"
    log_error "  - Files named: ${EPIC_ID}-*-*.md (e.g., ${EPIC_ID}-1-description.md)"
    log_error "  - Files named: story-${EPIC_ID}.*.md or story-${EPIC_ID}-*.md"
    exit 1
fi

log "Found ${#STORIES[@]} stories"

# Sort stories for consistent execution order
IFS=$'\n' STORIES=($(sort -V <<<"${STORIES[*]}")); unset IFS

# Show which directories stories came from
if [ "$VERBOSE" = true ]; then
    for story in "${STORIES[@]}"; do
        echo "  - $story"
    done
fi

# =============================================================================
# Execution Functions
# =============================================================================

execute_dev_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)
    
    log ">>> DEV PHASE: $story_id"
    
    local story_contents=$(cat "$story_file")
    
    # Build the dev prompt
    local dev_prompt="You are the Dev agent executing a BMAD story implementation.

## Your Task

Implement story: $story_id

## Story Specification

<story>
$story_contents
</story>

## Implementation Requirements

1. Read the story file completely before writing any code
2. Follow existing patterns in the codebase
3. Implement ALL acceptance criteria
4. Write tests for each criterion
5. Run tests and fix any failures
6. Update documentation as needed

## When Complete

1. Update the story file:
   - Change Status to: In Review
   - Fill in the Dev Agent Record section with:
     - Implementation Summary
     - Files Created/Modified
     - Key Decisions
     - Tests Added
     - Test Results (summary of test run)
     - Notes for Reviewer
     - Acceptance Criteria Status (checklist with file references)

2. Stage changes: git add -A

3. Output exactly: IMPLEMENTATION COMPLETE: $story_id

If blocked, output: IMPLEMENTATION BLOCKED: $story_id - [reason]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute dev phase for $story_id"
        return 0
    fi
    
    # Execute in isolated context
    local result
    result=$(claude --dangerously-skip-permissions -p "$dev_prompt" 2>&1) || true
    
    echo "$result" >> "$LOG_FILE"
    
    if echo "$result" | grep -q "IMPLEMENTATION COMPLETE"; then
        log_success "Dev phase complete: $story_id"
        return 0
    elif echo "$result" | grep -q "IMPLEMENTATION BLOCKED"; then
        log_error "Dev phase blocked: $story_id"
        echo "$result" | grep "IMPLEMENTATION BLOCKED"
        return 1
    else
        log_error "Dev phase did not complete cleanly: $story_id"
        return 1
    fi
}

execute_review_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)
    
    log ">>> REVIEW PHASE: $story_id (fresh context)"
    
    local story_contents=$(cat "$story_file")
    
    # Build the review prompt with severity-based fix logic
    local review_prompt="You are a Senior Code Reviewer performing a BMAD code review.

## Your Task

Review the implementation of story: $story_id

You are seeing this code for the first time. You have no knowledge of the implementation process.

## Story Specification and Dev Context

<story>
$story_contents
</story>

The story file contains:
- Acceptance criteria (what must be verified)
- Dev Agent Record (implementation notes from the developer)
- Notes for Reviewer (areas of concern flagged by dev)

## Review Process

1. Run: git diff --staged
2. Verify each acceptance criterion is implemented and tested
3. Check code quality, security, and patterns
4. Collect and categorize all issues by severity

## Issue Severity Definitions

- **HIGH**: Security vulnerabilities, missing error handling, no tests for new code, N+1 queries, exposed credentials
- **MEDIUM**: Pattern violations, missing edge cases, hardcoded config values, code duplication  
- **LOW**: Naming inconsistencies, minor style issues, missing comments

## Issue Fix Policy (IMPORTANT)

Apply this logic after collecting all issues:

\`\`\`
1. Always fix ALL HIGH severity issues
2. If TOTAL issues > 5, also fix ALL MEDIUM severity issues
3. LOW severity issues: document only, do NOT fix
\`\`\`

## Review Checklist

### Acceptance Criteria
For each criterion: implemented? tested? matches requirement?

### Code Quality  
- Follows existing patterns (MEDIUM)
- No security issues (HIGH)
- Error handling appropriate (HIGH)
- Tests exist and meaningful (HIGH)
- No hardcoded secrets (HIGH)

## After Review

1. Compile issues found with severity
2. Count: HIGH=?, MEDIUM=?, LOW=?, TOTAL=?
3. Apply fix policy: fix HIGH always, fix MEDIUM if total > 5
4. For each fix: make change, run tests, verify
5. Stage any fixes: git add -A

## Update Story File

Add Code Review Record section:

\`\`\`markdown
## Code Review Record

**Reviewer**: Code Review Agent  
**Date**: $(date '+%Y-%m-%d %H:%M')

### Issues Found
| # | Description | Severity | Status |
|---|-------------|----------|--------|

**Totals**: X HIGH, Y MEDIUM, Z LOW

### Fixes Applied
[List what was fixed]

### Remaining Issues
[Low severity items for future cleanup]

### Final Status
Approved / Approved with fixes / Rejected
\`\`\`

## Completion

If PASSED (no unfixed HIGH/MEDIUM issues):
1. Update story Status to: Done
2. Output: REVIEW PASSED: $story_id
   or: REVIEW PASSED WITH FIXES: $story_id - Fixed N issues

If FAILED (unfixable issues or missing acceptance criteria):
1. Update story Status to: Blocked  
2. Output: REVIEW FAILED: $story_id - [reason]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute review phase for $story_id"
        return 0
    fi
    
    # Execute in isolated context
    local result
    result=$(claude --dangerously-skip-permissions -p "$review_prompt" 2>&1) || true
    
    echo "$result" >> "$LOG_FILE"
    
    if echo "$result" | grep -q "REVIEW PASSED"; then
        log_success "Review passed: $story_id"
        return 0
    elif echo "$result" | grep -q "REVIEW FAILED"; then
        log_error "Review failed: $story_id"
        echo "$result" | grep "REVIEW FAILED"
        return 1
    else
        log_warn "Review did not complete cleanly: $story_id"
        return 1
    fi
}

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
    
    git add -A
    git commit -m "feat(epic-$EPIC_ID): complete $story_id" || {
        log_warn "Nothing to commit for $story_id"
    }
    
    log_success "Committed: $story_id"
}

generate_uat() {
    log ">>> GENERATING UAT DOCUMENT (fresh context)"
    
    local epic_contents=$(cat "$EPIC_FILE")
    local all_stories=""
    
    for story_file in "${STORIES[@]}"; do
        local story_id=$(basename "$story_file" .md)
        all_stories+="
<story id=\"$story_id\">
$(cat "$story_file")
</story>
"
    done
    
    local uat_prompt="You are a QA Specialist creating a User Acceptance Testing document.

## Your Task

Generate a UAT document for Epic: $EPIC_ID

## Epic Definition

<epic>
$epic_contents
</epic>

## Completed Stories

$all_stories

## Requirements

Create a UAT document for NON-TECHNICAL users with:

1. **Overview**: What was built (plain language)
2. **Prerequisites**: Test environment, accounts, setup
3. **Test Scenarios**: Step-by-step instructions with expected results
4. **Success Criteria**: Checklist of what must work
5. **Sign-off Section**: For human approval

Write for someone who can use the software but doesn't know how it's built.

## Output

Save to: $UAT_DIR/epic-${EPIC_ID}-uat.md

When complete, output: UAT GENERATED: $UAT_DIR/epic-${EPIC_ID}-uat.md"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would generate UAT document"
        return 0
    fi
    
    local result
    result=$(claude --dangerously-skip-permissions -p "$uat_prompt" 2>&1) || true
    
    echo "$result" >> "$LOG_FILE"
    
    if echo "$result" | grep -q "UAT GENERATED"; then
        log_success "UAT document generated"
    else
        log_warn "UAT generation may not have completed cleanly"
    fi
    
    # Commit UAT document
    if [ "$NO_COMMIT" = false ]; then
        git add "$UAT_DIR/epic-${EPIC_ID}-uat.md" 2>/dev/null || true
        git commit -m "docs(epic-$EPIC_ID): add UAT document" 2>/dev/null || true
    fi
}

# =============================================================================
# Main Execution Loop
# =============================================================================

log "=========================================="
log "Starting execution of ${#STORIES[@]} stories"
log "=========================================="

COMPLETED=0
FAILED=0
SKIPPED=0
START_TIME=$(date +%s)
STARTED=false

for story_file in "${STORIES[@]}"; do
    story_id=$(basename "$story_file" .md)

    # --start-from: Skip stories until we reach the specified one
    if [ -n "$START_FROM" ] && [ "$STARTED" = false ]; then
        if [[ "$story_id" == *"$START_FROM"* ]]; then
            STARTED=true
        else
            log_warn "Skipping $story_id (waiting for $START_FROM)"
            ((SKIPPED++))
            update_story_metrics "skipped"
            continue
        fi
    fi

    # --skip-done: Skip stories with Status: Done
    if [ "$SKIP_DONE" = true ]; then
        if grep -q "^Status:.*Done" "$story_file" 2>/dev/null; then
            log_warn "Skipping $story_id (Status: Done)"
            ((SKIPPED++))
            update_story_metrics "skipped"
            continue
        fi
    fi

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Story: $story_id"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # DEV PHASE (Context 1)
    if ! execute_dev_phase "$story_file"; then
        log_error "Dev phase failed for $story_id"
        ((FAILED++))
        update_story_metrics "failed"
        add_metrics_issue "$story_id" "dev_phase_failed" "Development phase did not complete"
        continue
    fi

    # REVIEW PHASE (Context 2 - Fresh)
    if [ "$SKIP_REVIEW" = false ]; then
        if ! execute_review_phase "$story_file"; then
            log_error "Review phase failed for $story_id"
            ((FAILED++))
            update_story_metrics "failed"
            add_metrics_issue "$story_id" "review_failed" "Code review phase failed"
            continue
        fi
    fi

    # COMMIT
    commit_story "$story_id"

    ((COMPLETED++))
    update_story_metrics "completed"
    log_success "Story complete: $story_id ($COMPLETED/${#STORIES[@]})"
done

# =============================================================================
# UAT Generation (Context 3 - Fresh)
# =============================================================================

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "UAT Document Generation"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

generate_uat

# =============================================================================
# Summary
# =============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Finalize metrics with final counts
finalize_metrics "${#STORIES[@]}" "$COMPLETED" "$FAILED" "$SKIPPED" "$DURATION"

echo ""
log "=========================================="
log "EPIC EXECUTION COMPLETE"
log "=========================================="
echo ""
echo "  Epic:       $EPIC_ID"
echo "  Duration:   ${DURATION}s"
echo "  Stories:    ${#STORIES[@]}"
echo "  Skipped:    $SKIPPED"
echo "  Completed:  $COMPLETED"
echo "  Failed:     $FAILED"
echo ""
echo "  Deliverables:"
echo "    - Stories:  $STORIES_DIR/"
echo "    - UAT:      $UAT_DIR/epic-${EPIC_ID}-uat.md"
echo "    - Metrics:  $METRICS_FILE"
echo "    - Log:      $LOG_FILE"
echo ""

if [ $FAILED -gt 0 ]; then
    log_warn "$FAILED stories failed - check log for details"
    exit 1
fi

log_success "All stories completed successfully"
echo ""
echo "Next step: Run UAT document with a human tester"
echo ""
