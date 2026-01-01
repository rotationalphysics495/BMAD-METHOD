#!/bin/bash
#
# BMAD Epic Chain - Execute Multiple Epics with Analysis and Context Sharing
#
# Usage: ./epic-chain.sh <epic-ids...> [options]
#
# Examples:
#   ./epic-chain.sh 36 37 38
#   ./epic-chain.sh 36 37 38 --dry-run --verbose
#   ./epic-chain.sh 36 37 38 --analyze-only
#   ./epic-chain.sh 36 37 38 --start-from 37
#
# Options:
#   --dry-run        Show what would be executed without running
#   --analyze-only   Run analysis phase only, don't execute
#   --verbose        Show detailed output
#   --start-from ID  Start from a specific epic (skip earlier ones)
#   --skip-done      Skip epics/stories with Status: Done
#   --no-handoff     Don't generate context handoffs between epics
#   --no-combined-uat Skip combined UAT generation at end
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BMAD_DIR="$PROJECT_ROOT/.bmad"

STORIES_DIR="$PROJECT_ROOT/docs/stories"
SPRINT_ARTIFACTS_DIR="$PROJECT_ROOT/docs/sprint-artifacts"
EPICS_DIR="$PROJECT_ROOT/docs/epics"
UAT_DIR="$PROJECT_ROOT/docs/uat"
HANDOFF_DIR="$PROJECT_ROOT/docs/handoffs"

LOG_FILE="/tmp/bmad-epic-chain-$$.log"
CHAIN_PLAN_FILE="$SPRINT_ARTIFACTS_DIR/chain-plan.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "${BLUE}[CHAIN]${NC} $1"
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

log_header() {
    echo ""
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

log_section() {
    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────────────────${NC}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

EPIC_IDS=()
DRY_RUN=false
ANALYZE_ONLY=false
VERBOSE=false
START_FROM=""
SKIP_DONE=false
NO_HANDOFF=false
NO_COMBINED_UAT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --analyze-only)
            ANALYZE_ONLY=true
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
        --no-handoff)
            NO_HANDOFF=true
            shift
            ;;
        --no-combined-uat)
            NO_COMBINED_UAT=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            EPIC_IDS+=("$1")
            shift
            ;;
    esac
done

if [ ${#EPIC_IDS[@]} -eq 0 ]; then
    echo "Usage: $0 <epic-id> [epic-id...] [options]"
    echo ""
    echo "Examples:"
    echo "  $0 36 37 38                    # Execute epics 36, 37, 38 in order"
    echo "  $0 36 37 38 --dry-run          # Show what would happen"
    echo "  $0 36 37 38 --analyze-only     # Just analyze, don't execute"
    echo "  $0 36 37 38 --start-from 37    # Resume from epic 37"
    echo ""
    echo "Options:"
    echo "  --dry-run        Show execution plan without running"
    echo "  --analyze-only   Analyze dependencies only"
    echo "  --verbose        Detailed output"
    echo "  --start-from ID  Start from specific epic"
    echo "  --skip-done      Skip completed stories"
    echo "  --no-handoff     Skip context handoffs between epics"
    echo "  --no-combined-uat Skip combined UAT at end"
    exit 1
fi

# =============================================================================
# Setup
# =============================================================================

log_header "EPIC CHAIN EXECUTION"
log "Epics to chain: ${EPIC_IDS[*]}"
log "Project root: $PROJECT_ROOT"

# Ensure directories exist
mkdir -p "$UAT_DIR"
mkdir -p "$HANDOFF_DIR"
mkdir -p "$SPRINT_ARTIFACTS_DIR"

# =============================================================================
# Phase 1: Validate Epics
# =============================================================================

log_section "Phase 1: Validating Epics"

# Bash 3.2 compatible: use indexed arrays with matching indices
EPIC_FILES_LIST=()
EPIC_STORIES_LIST=()
EPIC_DEPS_LIST=()

for i in "${!EPIC_IDS[@]}"; do
    epic_id="${EPIC_IDS[$i]}"

    # Find epic file
    epic_file=""
    for pattern in "epic-${epic_id}.md" "epic-${epic_id}-"*.md "epic-0${epic_id}-"*.md "${epic_id}.md"; do
        found=$(find "$EPICS_DIR" -name "$pattern" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            epic_file="$found"
            break
        fi
    done

    if [ -z "$epic_file" ] || [ ! -f "$epic_file" ]; then
        log_error "Epic $epic_id: File not found in $EPICS_DIR"
        exit 1
    fi

    EPIC_FILES_LIST[$i]="$epic_file"
    log_success "Epic $epic_id: Found $(basename "$epic_file")"

    # Find stories for this epic
    story_count=0
    for search_dir in "$STORIES_DIR" "$SPRINT_ARTIFACTS_DIR"; do
        if [ -d "$search_dir" ]; then
            count=$(find "$search_dir" -name "${epic_id}-*-*.md" 2>/dev/null | wc -l)
            story_count=$((story_count + count))
        fi
    done

    if [ "$story_count" -eq 0 ]; then
        log_warn "Epic $epic_id: No story files found (will check epic file for story definitions)"
    else
        log "Epic $epic_id: Found $story_count story files"
    fi

    EPIC_STORIES_LIST[$i]=$story_count
done

log_success "All ${#EPIC_IDS[@]} epics validated"

# =============================================================================
# Phase 2: Analyze Dependencies
# =============================================================================

log_section "Phase 2: Analyzing Dependencies"

# Simple dependency detection: check for ## Dependencies section in epic files
for i in "${!EPIC_IDS[@]}"; do
    epic_id="${EPIC_IDS[$i]}"
    epic_file="${EPIC_FILES_LIST[$i]}"

    # Look for Dependencies section
    deps=$(grep -A 10 "^## Dependencies" "$epic_file" 2>/dev/null | grep -oE "Epic [0-9]+" | grep -oE "[0-9]+" || true)

    if [ -n "$deps" ]; then
        EPIC_DEPS_LIST[$i]="$deps"
        log "Epic $epic_id depends on: $deps"
    else
        EPIC_DEPS_LIST[$i]=""
        log "Epic $epic_id: No explicit dependencies"
    fi
done

# =============================================================================
# Phase 3: Determine Execution Order
# =============================================================================

log_section "Phase 3: Determining Execution Order"

# For now, use order as provided (user presumably knows the right order)
# Future enhancement: topological sort based on dependencies

EXECUTION_ORDER=("${EPIC_IDS[@]}")

log "Execution order: ${EXECUTION_ORDER[*]}"

# =============================================================================
# Phase 4: Generate Chain Plan
# =============================================================================

log_section "Phase 4: Generating Chain Plan"

cat > "$CHAIN_PLAN_FILE" << EOF
# Epic Chain Execution Plan
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

epics: [${EPIC_IDS[*]}]
total_epics: ${#EPIC_IDS[@]}

execution_order:
EOF

total_stories=0
for i in "${!EXECUTION_ORDER[@]}"; do
    epic_id="${EXECUTION_ORDER[$i]}"
    story_count=${EPIC_STORIES_LIST[$i]}
    total_stories=$((total_stories + story_count))
    deps="${EPIC_DEPS_LIST[$i]}"

    cat >> "$CHAIN_PLAN_FILE" << EOF
  - epic: $epic_id
    file: $(basename "${EPIC_FILES_LIST[$i]}")
    stories: $story_count
    dependencies: [$deps]
EOF
done

cat >> "$CHAIN_PLAN_FILE" << EOF

total_stories: $total_stories

options:
  dry_run: $DRY_RUN
  skip_done: $SKIP_DONE
  context_handoff: $([ "$NO_HANDOFF" = true ] && echo "false" || echo "true")
  combined_uat: $([ "$NO_COMBINED_UAT" = true ] && echo "false" || echo "true")
EOF

log_success "Chain plan saved to: $CHAIN_PLAN_FILE"

# =============================================================================
# Display Summary
# =============================================================================

log_header "CHAIN EXECUTION PLAN"

echo "  Epics:          ${EPIC_IDS[*]}"
echo "  Total Stories:  $total_stories"
echo "  Dry Run:        $DRY_RUN"
echo "  Skip Done:      $SKIP_DONE"
echo ""
echo "  Execution Order:"
for i in "${!EXECUTION_ORDER[@]}"; do
    epic_id="${EXECUTION_ORDER[$i]}"
    deps="${EPIC_DEPS_LIST[$i]}"
    echo "    $((i+1)). Epic $epic_id (${EPIC_STORIES_LIST[$i]} stories) ${deps:+← depends on: $deps}"
done
echo ""

if [ "$ANALYZE_ONLY" = true ]; then
    log_success "Analysis complete (--analyze-only specified)"
    echo ""
    echo "To execute this chain, run:"
    echo "  $0 ${EPIC_IDS[*]}"
    echo ""
    exit 0
fi

# =============================================================================
# Phase 5: Execute Chain
# =============================================================================

log_header "EXECUTING EPIC CHAIN"

COMPLETED_EPICS=0
FAILED_EPICS=0
SKIPPED_EPICS=0
START_TIME=$(date +%s)
STARTED=false
PREVIOUS_EPIC=""
PREVIOUS_IDX=-1

for current_idx in "${!EXECUTION_ORDER[@]}"; do
    epic_id="${EXECUTION_ORDER[$current_idx]}"
    # Handle --start-from
    if [ -n "$START_FROM" ] && [ "$STARTED" = false ]; then
        if [ "$epic_id" = "$START_FROM" ]; then
            STARTED=true
        else
            log_warn "Skipping Epic $epic_id (waiting for --start-from $START_FROM)"
            ((SKIPPED_EPICS++))
            continue
        fi
    fi

    log_section "Executing Epic $epic_id"

    # Generate context handoff from previous epic
    if [ -n "$PREVIOUS_EPIC" ] && [ "$NO_HANDOFF" = false ]; then
        handoff_file="$HANDOFF_DIR/epic-${PREVIOUS_EPIC}-to-${epic_id}-handoff.md"
        if [ -f "$handoff_file" ]; then
            log "Loading context handoff from Epic $PREVIOUS_EPIC"
        fi
    fi

    # Build epic-execute command
    exec_cmd="$SCRIPT_DIR/epic-execute.sh $epic_id"

    if [ "$DRY_RUN" = true ]; then
        exec_cmd="$exec_cmd --dry-run"
    fi

    if [ "$SKIP_DONE" = true ]; then
        exec_cmd="$exec_cmd --skip-done"
    fi

    if [ "$VERBOSE" = true ]; then
        exec_cmd="$exec_cmd --verbose"
    fi

    log "Running: $exec_cmd"

    # Execute epic
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute: $exec_cmd"
        ((COMPLETED_EPICS++))
    else
        if $exec_cmd; then
            log_success "Epic $epic_id completed"
            ((COMPLETED_EPICS++))

            # Generate handoff for next epic
            if [ "$NO_HANDOFF" = false ]; then
                next_idx=$((current_idx + 1))

                if [ $next_idx -lt ${#EXECUTION_ORDER[@]} ]; then
                    next_epic="${EXECUTION_ORDER[$next_idx]}"
                    handoff_file="$HANDOFF_DIR/epic-${epic_id}-to-${next_epic}-handoff.md"

                    log "Generating context handoff: Epic $epic_id → Epic $next_epic"

                    story_count=${EPIC_STORIES_LIST[$current_idx]}
                    cat > "$handoff_file" << EOF
# Epic $epic_id → Epic $next_epic Handoff

## Generated
$(date '+%Y-%m-%d %H:%M:%S')

## Epic $epic_id Completion Summary

Epic $epic_id has been completed. Key context for Epic $next_epic:

### Patterns Established
- Review code changes in Epic $epic_id for established patterns
- Check \`docs/stories/${epic_id}-*\` for implementation details

### Files Modified
$(git diff --name-only HEAD~${story_count} HEAD 2>/dev/null | head -20 || echo "Unable to determine - check git log")

### Notes for Next Epic
- Continue following patterns established in this epic
- Reference UAT document at \`docs/uat/epic-${epic_id}-uat.md\` for context

EOF
                    log_success "Handoff saved to: $handoff_file"
                fi
            fi
        else
            log_error "Epic $epic_id failed"
            ((FAILED_EPICS++))

            # Ask whether to continue or abort
            echo ""
            echo "Epic $epic_id failed. Continue with remaining epics? (y/n)"
            read -r continue_choice
            if [ "$continue_choice" != "y" ]; then
                log_error "Chain execution aborted by user"
                break
            fi
        fi
    fi

    PREVIOUS_EPIC="$epic_id"
    PREVIOUS_IDX=$current_idx
done

# =============================================================================
# Phase 6: Generate Combined UAT
# =============================================================================

if [ "$NO_COMBINED_UAT" = false ] && [ "$DRY_RUN" = false ] && [ $COMPLETED_EPICS -gt 1 ]; then
    log_section "Generating Combined UAT Document"

    combined_uat_file="$UAT_DIR/chain-${EPIC_IDS[*]// /-}-uat.md"

    cat > "$combined_uat_file" << EOF
# Combined UAT: Epics ${EPIC_IDS[*]}

## Generated
$(date '+%Y-%m-%d %H:%M:%S')

## Overview

This document combines User Acceptance Testing for epics: ${EPIC_IDS[*]}

## Individual Epic UATs

EOF

    for epic_id in "${EPIC_IDS[@]}"; do
        uat_file="$UAT_DIR/epic-${epic_id}-uat.md"
        if [ -f "$uat_file" ]; then
            echo "### Epic $epic_id" >> "$combined_uat_file"
            echo "" >> "$combined_uat_file"
            echo "See: [epic-${epic_id}-uat.md](epic-${epic_id}-uat.md)" >> "$combined_uat_file"
            echo "" >> "$combined_uat_file"
        fi
    done

    cat >> "$combined_uat_file" << EOF

## Cross-Epic Integration Testing

After individual epic testing, verify these cross-epic scenarios:

1. [ ] Features from earlier epics still work after later epic changes
2. [ ] Data flows correctly between features from different epics
3. [ ] No regression in previously tested functionality

## Sign-off

| Epic | Tester | Date | Status |
|------|--------|------|--------|
EOF

    for epic_id in "${EPIC_IDS[@]}"; do
        echo "| $epic_id | | | Pending |" >> "$combined_uat_file"
    done

    log_success "Combined UAT saved to: $combined_uat_file"
fi

# =============================================================================
# Summary
# =============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_header "EPIC CHAIN COMPLETE"

echo "  Epics in Chain: ${#EPIC_IDS[@]}"
echo "  Completed:      $COMPLETED_EPICS"
echo "  Failed:         $FAILED_EPICS"
echo "  Skipped:        $SKIPPED_EPICS"
echo "  Duration:       ${DURATION}s"
echo ""
echo "  Artifacts:"
echo "    - Chain Plan:    $CHAIN_PLAN_FILE"
echo "    - Handoffs:      $HANDOFF_DIR/"
echo "    - UAT Documents: $UAT_DIR/"
echo "    - Log:           $LOG_FILE"
echo ""

if [ $FAILED_EPICS -gt 0 ]; then
    log_warn "$FAILED_EPICS epic(s) failed - check log for details"
    exit 1
fi

log_success "All epics completed successfully"
echo ""
echo "Next step: Review UAT documents and run manual testing"
echo ""
