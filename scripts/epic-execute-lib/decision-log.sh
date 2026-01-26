#!/bin/bash
#
# BMAD Epic Execute - Decision Log Module
#
# Provides functions to maintain a cumulative decision log across phases
# for context preservation during epic execution.
#
# Usage: Sourced by epic-execute.sh
#

# =============================================================================
# Decision Log Functions
# =============================================================================

DECISION_LOG=""

# Initialize the decision log for an epic
# Creates a new decision log file or appends to existing one
init_decision_log() {
    if [ -z "$SPRINT_ARTIFACTS_DIR" ] || [ -z "$EPIC_ID" ]; then
        log_warn "Cannot initialize decision log: SPRINT_ARTIFACTS_DIR or EPIC_ID not set"
        return 1
    fi

    DECISION_LOG="$SPRINT_ARTIFACTS_DIR/epic-${EPIC_ID}-decisions.md"
    mkdir -p "$(dirname "$DECISION_LOG")"

    # Create new decision log if it doesn't exist
    if [ ! -f "$DECISION_LOG" ]; then
        cat > "$DECISION_LOG" << EOF
# Epic $EPIC_ID Decision Log

This file tracks implementation decisions for context continuity across phases.

**Epic:** $EPIC_ID
**Started:** $(date '+%Y-%m-%d %H:%M:%S')

---

EOF
        log "Decision log initialized: $DECISION_LOG"
    else
        log "Using existing decision log: $DECISION_LOG"
    fi

    return 0
}

# Append a decision to the log
# Arguments:
#   $1 - phase name (e.g., "DEV", "DESIGN", "FIX")
#   $2 - story_id
#   $3 - content (the decision details)
append_to_decision_log() {
    local phase="$1"
    local story_id="$2"
    local content="$3"

    if [ -z "$DECISION_LOG" ] || [ ! -f "$DECISION_LOG" ]; then
        [ "$VERBOSE" = true ] && log_warn "Decision log not initialized"
        return 1
    fi

    cat >> "$DECISION_LOG" << EOF

## $phase: $story_id
**Timestamp:** $(date '+%Y-%m-%d %H:%M:%S')

$content

---
EOF

    [ "$VERBOSE" = true ] && log "Appended $phase decision for $story_id to decision log"
    return 0
}

# Get the decision log contents for inclusion in prompts
# Returns the full contents of the decision log, or empty string if not available
get_decision_log_context() {
    if [ -z "$DECISION_LOG" ] || [ ! -f "$DECISION_LOG" ]; then
        echo ""
        return
    fi

    cat "$DECISION_LOG"
}

# Get a summary of decisions for a specific story
# Arguments:
#   $1 - story_id
get_story_decisions() {
    local story_id="$1"

    if [ -z "$DECISION_LOG" ] || [ ! -f "$DECISION_LOG" ]; then
        echo ""
        return
    fi

    # Extract sections related to this story
    grep -A 50 "## .*: $story_id" "$DECISION_LOG" | head -60 || true
}
