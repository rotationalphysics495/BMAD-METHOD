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

# =============================================================================
# BMAD Workflow Paths
# =============================================================================

# Source workflow files from the BMAD-METHOD repository
BMAD_SRC_DIR="$SCRIPT_DIR/.."
WORKFLOWS_DIR="$BMAD_SRC_DIR/src/modules/bmm/workflows/4-implementation"
CORE_TASKS_DIR="$BMAD_SRC_DIR/src/core/tasks"

# Dev Story Workflow
DEV_WORKFLOW_DIR="$WORKFLOWS_DIR/dev-story"
DEV_WORKFLOW_YAML="$DEV_WORKFLOW_DIR/workflow.yaml"
DEV_WORKFLOW_INSTRUCTIONS="$DEV_WORKFLOW_DIR/instructions.xml"
DEV_WORKFLOW_CHECKLIST="$DEV_WORKFLOW_DIR/checklist.md"

# Code Review Workflow
REVIEW_WORKFLOW_DIR="$WORKFLOWS_DIR/code-review"
REVIEW_WORKFLOW_YAML="$REVIEW_WORKFLOW_DIR/workflow.yaml"
REVIEW_WORKFLOW_INSTRUCTIONS="$REVIEW_WORKFLOW_DIR/instructions.xml"
REVIEW_WORKFLOW_CHECKLIST="$REVIEW_WORKFLOW_DIR/checklist.md"

# Core workflow executor
WORKFLOW_EXECUTOR="$CORE_TASKS_DIR/workflow.xml"

# UAT Generation (from epic-execute workflow)
UAT_STEP_TEMPLATE="$WORKFLOWS_DIR/epic-execute/steps/step-04-generate-uat.md"
UAT_DOC_TEMPLATE="$WORKFLOWS_DIR/epic-execute/templates/uat-template.md"

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
fix_loop:
  total_fix_attempts: 0
  stories_requiring_fixes: 0
  max_retries_hit: 0
validation:
  gate_executed: false
  gate_status: "PENDING"
issues: []
story_details: []
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

record_fix_attempt() {
    local story_id="$1"
    local attempt_num="$2"
    local outcome="$3"  # success|failed|max_retries

    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        return
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v yq >/dev/null 2>&1; then
        # Increment total fix attempts
        yq -i '.fix_loop.total_fix_attempts += 1' "$METRICS_FILE"

        # Track per-story fix details
        yq -i ".story_details += [{\"story\": \"$story_id\", \"fix_attempt\": $attempt_num, \"outcome\": \"$outcome\", \"timestamp\": \"$timestamp\"}]" "$METRICS_FILE"

        if [ "$outcome" = "max_retries" ]; then
            yq -i '.fix_loop.max_retries_hit += 1' "$METRICS_FILE"
        fi
    fi
}

record_story_required_fixes() {
    local story_id="$1"

    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        return
    fi

    if command -v yq >/dev/null 2>&1; then
        yq -i '.fix_loop.stories_requiring_fixes += 1' "$METRICS_FILE"
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
# Status Update Functions
# =============================================================================

update_story_status() {
    local story_file="$1"
    local new_status="$2"
    local story_id=$(basename "$story_file" .md)

    if [ ! -f "$story_file" ]; then
        log_warn "Story file not found for status update: $story_file"
        return 1
    fi

    # Update Status field in story file using sed
    # Matches "Status: <anything>" and replaces with "Status: <new_status>"
    if grep -q "^Status:" "$story_file"; then
        sed -i.bak "s/^Status:.*$/Status: $new_status/" "$story_file" && rm -f "${story_file}.bak"
        log_success "Updated story file status: $story_id → $new_status"
    else
        log_warn "No Status field found in story file: $story_id"
        return 1
    fi

    return 0
}

update_sprint_status() {
    local story_id="$1"
    local new_status="$2"

    # Find sprint-status.yaml file
    local sprint_file=""
    for search_dir in "$SPRINT_ARTIFACTS_DIR" "$SPRINTS_DIR" "$PROJECT_ROOT/docs"; do
        if [ -f "$search_dir/sprint-status.yaml" ]; then
            sprint_file="$search_dir/sprint-status.yaml"
            break
        fi
    done

    if [ -z "$sprint_file" ] || [ ! -f "$sprint_file" ]; then
        [ "$VERBOSE" = true ] && log_warn "No sprint-status.yaml found - skipping sprint status update"
        return 0
    fi

    # Extract story key from story_id (e.g., "1-2-user-auth" from various naming formats)
    # Story files can be named: 1-2-user-auth.md, story-1.2-user-auth.md, etc.
    local story_key=""

    # Try to extract the key pattern: {epic}-{seq}-{name}
    if [[ "$story_id" =~ ^([0-9]+)-([0-9]+)-(.+)$ ]]; then
        story_key="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    elif [[ "$story_id" =~ ^story-([0-9]+)\.([0-9]+)-(.+)$ ]]; then
        story_key="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    elif [[ "$story_id" =~ ^story-([0-9]+)-([0-9]+)-(.+)$ ]]; then
        story_key="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    else
        # Use story_id as-is if no pattern matches
        story_key="$story_id"
    fi

    # Check if yq is available for YAML manipulation
    if command -v yq >/dev/null 2>&1; then
        # Check if story key exists in development_status
        if yq -e ".development_status[\"$story_key\"]" "$sprint_file" >/dev/null 2>&1; then
            yq -i ".development_status[\"$story_key\"] = \"$new_status\"" "$sprint_file"
            log_success "Updated sprint status: $story_key → $new_status"
        else
            [ "$VERBOSE" = true ] && log_warn "Story key '$story_key' not found in sprint-status.yaml"
        fi
    else
        # Fallback: use sed for simple replacement
        # This handles the format: "  1-2-user-auth: in-progress"
        if grep -q "^[[:space:]]*${story_key}:" "$sprint_file"; then
            sed -i.bak "s/^\([[:space:]]*${story_key}:\).*/\1 $new_status/" "$sprint_file" && rm -f "${sprint_file}.bak"
            log_success "Updated sprint status: $story_key → $new_status (via sed)"
        else
            [ "$VERBOSE" = true ] && log_warn "Story key '$story_key' not found in sprint-status.yaml (sed fallback)"
        fi
    fi

    return 0
}

mark_story_done() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log "Marking story as done: $story_id"

    # Update story file Status to done
    update_story_status "$story_file" "done"

    # Update sprint-status.yaml if it exists
    update_sprint_status "$story_id" "done"
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

# =============================================================================
# Validate BMAD Workflow Files
# =============================================================================

validate_workflows() {
    local missing=0

    log "Validating BMAD workflow files..."

    # Core workflow executor
    if [ ! -f "$WORKFLOW_EXECUTOR" ]; then
        log_error "Missing: Core workflow executor at $WORKFLOW_EXECUTOR"
        ((missing++))
    fi

    # Dev-story workflow
    if [ ! -f "$DEV_WORKFLOW_YAML" ]; then
        log_error "Missing: Dev workflow.yaml at $DEV_WORKFLOW_YAML"
        ((missing++))
    fi
    if [ ! -f "$DEV_WORKFLOW_INSTRUCTIONS" ]; then
        log_error "Missing: Dev instructions.xml at $DEV_WORKFLOW_INSTRUCTIONS"
        ((missing++))
    fi

    # Code-review workflow
    if [ ! -f "$REVIEW_WORKFLOW_YAML" ]; then
        log_error "Missing: Review workflow.yaml at $REVIEW_WORKFLOW_YAML"
        ((missing++))
    fi
    if [ ! -f "$REVIEW_WORKFLOW_INSTRUCTIONS" ]; then
        log_error "Missing: Review instructions.xml at $REVIEW_WORKFLOW_INSTRUCTIONS"
        ((missing++))
    fi

    if [ $missing -gt 0 ]; then
        log_error "Missing $missing required BMAD workflow files"
        log_error "Ensure you are running from the BMAD-METHOD repository"
        log_error "Workflows expected at: $WORKFLOWS_DIR"
        exit 1
    fi

    log_success "All BMAD workflow files validated"

    if [ "$VERBOSE" = true ]; then
        echo "  Dev workflow:    $DEV_WORKFLOW_DIR"
        echo "  Review workflow: $REVIEW_WORKFLOW_DIR"
        echo "  Executor:        $WORKFLOW_EXECUTOR"
    fi
}

validate_workflows

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

    log ">>> DEV PHASE: $story_id (using BMAD dev-story workflow)"

    # Verify workflow files exist
    if [ ! -f "$DEV_WORKFLOW_YAML" ] || [ ! -f "$DEV_WORKFLOW_INSTRUCTIONS" ]; then
        log_error "BMAD dev-story workflow files not found"
        log_error "Expected: $DEV_WORKFLOW_YAML"
        log_error "Expected: $DEV_WORKFLOW_INSTRUCTIONS"
        return 1
    fi

    # Read workflow components
    local workflow_yaml=$(cat "$DEV_WORKFLOW_YAML")
    local workflow_instructions=$(cat "$DEV_WORKFLOW_INSTRUCTIONS")
    local workflow_checklist=""
    if [ -f "$DEV_WORKFLOW_CHECKLIST" ]; then
        workflow_checklist=$(cat "$DEV_WORKFLOW_CHECKLIST")
    fi
    local workflow_executor=$(cat "$WORKFLOW_EXECUTOR")
    local story_contents=$(cat "$story_file")

    # Build the dev prompt using BMAD workflow
    local dev_prompt="You are executing a BMAD dev-story workflow in automated mode.

## Workflow Execution Context

You are running the BMAD dev-story workflow to implement a story. This is an AUTOMATED execution
as part of an epic chain - execute the workflow completely without user interaction prompts.

### CRITICAL AUTOMATION RULES
- Do NOT pause for user confirmation at any step
- Do NOT ask questions - make reasonable decisions and proceed
- Execute ALL workflow steps in exact order until completion or HALT condition
- When workflow says 'ask user', make a reasonable autonomous decision instead
- Complete the ENTIRE workflow in a single execution

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

## Definition of Done Checklist

<validation-checklist>
$workflow_checklist
</validation-checklist>

## Story to Implement

**Story Path:** $story_file
**Story ID:** $story_id

<story-contents>
$story_contents
</story-contents>

## Execution Variables (Pre-resolved)

- story_path: $story_file
- story_key: $story_id
- project_root: $PROJECT_ROOT
- implementation_artifacts: $STORIES_DIR
- sprint_status: $SPRINT_ARTIFACTS_DIR/sprint-status.yaml
- date: $(date '+%Y-%m-%d')
- user_name: Epic Executor
- communication_language: English
- user_skill_level: expert
- document_output_language: English

## Completion Signals

When the workflow completes successfully (all tasks done, tests pass, status set to 'review'):
Output exactly: IMPLEMENTATION COMPLETE: $story_id

If a HALT condition is triggered or implementation is blocked:
Output exactly: IMPLEMENTATION BLOCKED: $story_id - [specific reason]

## Begin Execution

Execute the dev-story workflow now. Follow all steps in exact order.
Stage all changes with: git add -A (after implementation is complete)"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute BMAD dev-story workflow for $story_id"
        echo "[DRY RUN] Workflow: $DEV_WORKFLOW_DIR"
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

# Global variable to store review findings for fix loop
LAST_REVIEW_FINDINGS=""

execute_review_phase() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    # Reset findings
    LAST_REVIEW_FINDINGS=""

    log ">>> REVIEW PHASE: $story_id (using BMAD code-review workflow, fresh context)"

    # Verify workflow files exist
    if [ ! -f "$REVIEW_WORKFLOW_YAML" ] || [ ! -f "$REVIEW_WORKFLOW_INSTRUCTIONS" ]; then
        log_error "BMAD code-review workflow files not found"
        log_error "Expected: $REVIEW_WORKFLOW_YAML"
        log_error "Expected: $REVIEW_WORKFLOW_INSTRUCTIONS"
        return 1
    fi

    # Read workflow components
    local workflow_yaml=$(cat "$REVIEW_WORKFLOW_YAML")
    local workflow_instructions=$(cat "$REVIEW_WORKFLOW_INSTRUCTIONS")
    local workflow_checklist=""
    if [ -f "$REVIEW_WORKFLOW_CHECKLIST" ]; then
        workflow_checklist=$(cat "$REVIEW_WORKFLOW_CHECKLIST")
    fi
    local workflow_executor=$(cat "$WORKFLOW_EXECUTOR")
    local story_contents=$(cat "$story_file")

    # Build the review prompt using BMAD workflow
    local review_prompt="You are executing a BMAD code-review workflow in automated mode.

## Workflow Execution Context

You are running the BMAD code-review workflow to perform an ADVERSARIAL code review.
This is an AUTOMATED execution as part of an epic chain.

### CRITICAL AUTOMATION RULES
- Do NOT pause for user confirmation at any step
- When workflow offers options (fix automatically, create action items, show details), ALWAYS choose option 1: Fix them automatically
- Execute ALL workflow steps in exact order until completion
- When workflow says 'ask user', automatically choose the option that fixes issues
- You ARE an adversarial reviewer - find 3-10 specific issues minimum
- Auto-fix all HIGH and MEDIUM severity issues
- Complete the ENTIRE workflow in a single execution

## Workflow Executor Engine

<workflow-executor>
$workflow_executor
</workflow-executor>

## Code-Review Workflow Configuration

<workflow-yaml>
$workflow_yaml
</workflow-yaml>

## Code-Review Workflow Instructions

<workflow-instructions>
$workflow_instructions
</workflow-instructions>

## Review Validation Checklist

<validation-checklist>
$workflow_checklist
</validation-checklist>

## Story to Review

**Story Path:** $story_file
**Story ID:** $story_id

<story-contents>
$story_contents
</story-contents>

## Execution Variables (Pre-resolved)

- story_path: $story_file
- story_key: $story_id
- project_root: $PROJECT_ROOT
- implementation_artifacts: $STORIES_DIR
- planning_artifacts: $PROJECT_ROOT/docs
- sprint_status: $SPRINT_ARTIFACTS_DIR/sprint-status.yaml
- date: $(date '+%Y-%m-%d')
- user_name: Epic Executor
- communication_language: English
- user_skill_level: expert
- document_output_language: English

## Automated Decision Policy

When the workflow presents options:
- Step 4 asks what to do with issues → Choose option 1 (Fix them automatically)
- Always auto-fix HIGH and MEDIUM severity issues
- LOW severity issues: document only, do not fix

## Completion Signals

When review passes (all HIGH/MEDIUM issues fixed, all ACs implemented, status set to 'done'):
Output exactly: REVIEW PASSED: $story_id

When review passes but required fixes:
Output exactly: REVIEW PASSED WITH FIXES: $story_id - Fixed N issues

If review fails (unfixable issues, missing acceptance criteria that YOU cannot fix):
1. First output a structured findings block:
\`\`\`
REVIEW FINDINGS START
- [HIGH] Description of issue 1 (file:line if applicable)
- [HIGH] Description of issue 2
- [MEDIUM] Description of issue 3
... all HIGH and MEDIUM issues that need dev attention ...
REVIEW FINDINGS END
\`\`\`
2. Then output exactly: REVIEW FAILED: $story_id - [summary reason]

## Begin Execution

Execute the code-review workflow now. Follow all steps in exact order.
You are seeing this code for the FIRST TIME - review adversarially.
Stage any fixes with: git add -A"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute BMAD code-review workflow for $story_id"
        echo "[DRY RUN] Workflow: $REVIEW_WORKFLOW_DIR"
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

        # Extract findings for fix loop
        LAST_REVIEW_FINDINGS=$(echo "$result" | sed -n '/REVIEW FINDINGS START/,/REVIEW FINDINGS END/p' | grep -E '^\s*-\s*\[(HIGH|MEDIUM)\]' || true)

        if [ -n "$LAST_REVIEW_FINDINGS" ]; then
            log "Captured ${#LAST_REVIEW_FINDINGS} bytes of review findings for fix loop"
        fi

        return 1
    else
        log_warn "Review did not complete cleanly: $story_id"
        return 1
    fi
}

execute_fix_phase() {
    local story_file="$1"
    local review_findings="$2"
    local attempt_num="$3"
    local story_id=$(basename "$story_file" .md)

    log ">>> FIX PHASE: $story_id (attempt $attempt_num, using BMAD dev-story workflow)"

    # Verify workflow files exist
    if [ ! -f "$DEV_WORKFLOW_YAML" ] || [ ! -f "$DEV_WORKFLOW_INSTRUCTIONS" ]; then
        log_error "BMAD dev-story workflow files not found for fix phase"
        return 1
    fi

    # Read workflow components
    local workflow_yaml=$(cat "$DEV_WORKFLOW_YAML")
    local workflow_instructions=$(cat "$DEV_WORKFLOW_INSTRUCTIONS")
    local workflow_checklist=""
    if [ -f "$DEV_WORKFLOW_CHECKLIST" ]; then
        workflow_checklist=$(cat "$DEV_WORKFLOW_CHECKLIST")
    fi
    local workflow_executor=$(cat "$WORKFLOW_EXECUTOR")
    local story_contents=$(cat "$story_file")

    # Build the fix prompt using BMAD dev-story workflow with review context
    local fix_prompt="You are executing a BMAD dev-story workflow in FIX MODE to address code review findings.

## Fix Phase Context

This is attempt $attempt_num of 3 to fix issues identified during code review.
You MUST address ALL HIGH and MEDIUM severity issues listed below.

### CRITICAL FIX RULES
- This is a TARGETED FIX session - only fix the issues listed below
- Do NOT refactor unrelated code
- Do NOT add new features
- Fix each issue, run tests to verify, then move to the next
- After fixing all issues, update the story file and stage changes

## Review Findings to Address

The following issues were identified during code review and MUST be fixed:

<review-findings>
$review_findings
</review-findings>

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

## Definition of Done Checklist

<validation-checklist>
$workflow_checklist
</validation-checklist>

## Story Being Fixed

**Story Path:** $story_file
**Story ID:** $story_id
**Fix Attempt:** $attempt_num of 3

<story-contents>
$story_contents
</story-contents>

## Execution Variables (Pre-resolved)

- story_path: $story_file
- story_key: $story_id
- project_root: $PROJECT_ROOT
- implementation_artifacts: $STORIES_DIR
- sprint_status: $SPRINT_ARTIFACTS_DIR/sprint-status.yaml
- date: $(date '+%Y-%m-%d')
- user_name: Epic Executor (Fix Phase)
- communication_language: English
- user_skill_level: expert
- document_output_language: English

## Fix Process

1. For each issue in the review findings:
   a. Locate the problematic code
   b. Implement the fix
   c. Run relevant tests to verify
   d. Move to next issue

2. After all issues are fixed:
   a. Run full test suite
   b. Update story file Dev Agent Record with fix notes
   c. Stage all changes: git add -A

## Completion Signals

When ALL review issues are successfully fixed:
Output exactly: FIX COMPLETE: $story_id - Fixed [N] issues

If unable to fix one or more issues:
Output exactly: FIX INCOMPLETE: $story_id - [reason and which issues remain]

## Begin Execution

Address all review findings now. This is attempt $attempt_num of 3."

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute BMAD fix phase for $story_id (attempt $attempt_num)"
        return 0
    fi

    # Execute in isolated context
    local result
    result=$(claude --dangerously-skip-permissions -p "$fix_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "FIX COMPLETE"; then
        log_success "Fix phase complete: $story_id (attempt $attempt_num)"
        record_fix_attempt "$story_id" "$attempt_num" "success"
        return 0
    elif echo "$result" | grep -q "FIX INCOMPLETE"; then
        log_error "Fix phase incomplete: $story_id (attempt $attempt_num)"
        echo "$result" | grep "FIX INCOMPLETE"
        record_fix_attempt "$story_id" "$attempt_num" "failed"
        return 1
    else
        log_warn "Fix phase did not complete cleanly: $story_id (attempt $attempt_num)"
        record_fix_attempt "$story_id" "$attempt_num" "failed"
        return 1
    fi
}

# Maximum number of fix attempts before giving up
MAX_FIX_ATTEMPTS=3

execute_story_with_fix_loop() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)
    local fix_attempt=0
    local needs_fixes=false

    # DEV PHASE (Context 1)
    if ! execute_dev_phase "$story_file"; then
        log_error "Dev phase failed for $story_id"
        return 1
    fi

    # REVIEW + FIX LOOP
    while true; do
        # REVIEW PHASE (Fresh Context)
        if execute_review_phase "$story_file"; then
            # Review passed - we're done
            log_success "Story passed review: $story_id"
            return 0
        fi

        # Review failed - check if we have findings to fix
        if [ -z "$LAST_REVIEW_FINDINGS" ]; then
            log_error "Review failed but no findings captured for $story_id"
            return 1
        fi

        # First failure - record that this story required fixes
        if [ "$needs_fixes" = false ]; then
            needs_fixes=true
            record_story_required_fixes "$story_id"
        fi

        # Check if we've exhausted fix attempts
        ((fix_attempt++))
        if [ $fix_attempt -gt $MAX_FIX_ATTEMPTS ]; then
            log_error "Max fix attempts ($MAX_FIX_ATTEMPTS) reached for $story_id"
            record_fix_attempt "$story_id" "$fix_attempt" "max_retries"
            add_metrics_issue "$story_id" "max_retries_exhausted" "Failed after $MAX_FIX_ATTEMPTS fix attempts"
            return 1
        fi

        log_warn "Review failed, attempting fix $fix_attempt of $MAX_FIX_ATTEMPTS for $story_id"

        # FIX PHASE (New Context)
        if ! execute_fix_phase "$story_file" "$LAST_REVIEW_FINDINGS" "$fix_attempt"; then
            log_error "Fix phase failed for $story_id (attempt $fix_attempt)"
            # Continue to next attempt - the review will catch remaining issues
        fi

        # Loop back to review phase to verify fixes
        log "Re-running review after fix attempt $fix_attempt..."
    done
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
    log ">>> GENERATING UAT DOCUMENT (using BMAD UAT template, fresh context)"

    # Load UAT step template if available
    local uat_step_template=""
    if [ -f "$UAT_STEP_TEMPLATE" ]; then
        uat_step_template=$(cat "$UAT_STEP_TEMPLATE")
    fi

    # Load UAT document template if available
    local uat_doc_template=""
    if [ -f "$UAT_DOC_TEMPLATE" ]; then
        uat_doc_template=$(cat "$UAT_DOC_TEMPLATE")
    fi

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

    # Count stories
    local story_count=${#STORIES[@]}

    # Build the UAT generation prompt using BMAD workflow step
    local uat_prompt="You are executing BMAD UAT generation step in automated mode.

## Context

This is Step 4 of the BMAD epic-execute workflow: Generate User Acceptance Testing Document.
You are running in a completely fresh context - you see only the finished epic and story specifications.

### CRITICAL RULES
- Write for NON-TECHNICAL users who can use software but don't know how it's built
- Focus on user journeys, not implementation details
- Generate clear, actionable test scenarios with binary pass/fail criteria
- Complete the entire document in a single execution

## BMAD UAT Generation Step Instructions

<uat-step-template>
$uat_step_template
</uat-step-template>

## BMAD UAT Document Template

<uat-doc-template>
$uat_doc_template
</uat-doc-template>

## Epic Definition

**Epic ID:** $EPIC_ID
**Epic File:** $EPIC_FILE

<epic>
$epic_contents
</epic>

## Completed Stories (${story_count} total)

$all_stories

## Pre-resolved Variables

- epic_id: $EPIC_ID
- story_count: $story_count
- date: $(date '+%Y-%m-%d')
- output_path: $UAT_DIR/epic-${EPIC_ID}-uat.md

## Scenario Generation Guidelines

### Good Scenarios
- Follow realistic user workflows
- Build on each other (Scenario 2 assumes Scenario 1 completed)
- Include at least one 'happy path' and one 'error path'
- Test the boundaries (empty inputs, maximum values, etc.)

### Avoid
- Testing implementation details
- Requiring technical knowledge to execute
- Ambiguous expected results
- Overlapping scenarios that test the same thing

## Output

1. Generate the complete UAT document following the template structure
2. Save to: $UAT_DIR/epic-${EPIC_ID}-uat.md
3. Output exactly: UAT GENERATED: $UAT_DIR/epic-${EPIC_ID}-uat.md

## Begin Execution

Generate the UAT document now."

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would generate UAT document using BMAD template"
        echo "[DRY RUN] Template: $UAT_STEP_TEMPLATE"
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

    # Execute story with fix loop (dev → review → fix loop if needed)
    if [ "$SKIP_REVIEW" = false ]; then
        # Full flow: dev → review (with fix loop if issues found)
        if ! execute_story_with_fix_loop "$story_file"; then
            log_error "Story execution failed for $story_id"
            ((FAILED++))
            update_story_metrics "failed"
            continue
        fi
    else
        # Skip review: just run dev phase
        if ! execute_dev_phase "$story_file"; then
            log_error "Dev phase failed for $story_id"
            ((FAILED++))
            update_story_metrics "failed"
            add_metrics_issue "$story_id" "dev_phase_failed" "Development phase did not complete"
            continue
        fi
    fi

    # MARK STORY AS DONE
    # Update both story file and sprint-status.yaml after successful review
    if [ "$DRY_RUN" = false ]; then
        mark_story_done "$story_file"
    else
        echo "[DRY RUN] Would mark story as done: $story_id"
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
