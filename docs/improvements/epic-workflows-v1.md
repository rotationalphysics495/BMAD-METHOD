# Epic Workflows Improvement Plan v1

**Date:** 2026-01-02
**Workflows Reviewed:** epic-execute, epic-chain
**Status:** Active

---

## Overview

This document captures the review findings and improvement roadmap for the epic-execute and epic-chain workflows. These workflows automate story execution with context isolation between development and review phases.

---

## What's Working Well

### 1. Context Isolation Architecture
The decision to run dev and review in separate Claude contexts is the key innovation:
- Prevents reviewer bias from seeing implementation struggles
- Maximizes context window for each phase
- Simulates real code review where reviewers see code "cold"
- Uses git staging as the communication medium between phases

### 2. Severity-Based Fix Policy
The issue severity system (HIGH/MEDIUM/LOW) with threshold-based fixing is pragmatic:
- Prevents over-engineering on minor issues
- Ensures critical issues always get fixed
- Documents low-severity for future cleanup sprints

**Location:** `step-03-code-review.md:17-27`

### 3. Structured Documentation Trail
The Dev Agent Record and Code Review Record sections create an auditable history:
- Understanding why decisions were made
- Debugging issues later
- Training/improving the workflow

### 4. Chain Dependency Analysis
Epic-chain's analysis phase detecting both explicit and implicit dependencies shows good foresight.

**Location:** `instructions.md:57-88`

### 5. Shell Scripts Quality
- Clean argument parsing
- Proper error handling with `set -e`
- Good logging with timestamps
- Flexible story discovery (multiple naming conventions)
- Resume capability with `--start-from`

---

## Improvement Areas

### HIGH Priority

#### 1. Security: `--dangerously-skip-permissions` Flag

**Location:** `epic-execute.sh:291-292`

```bash
result=$(claude --dangerously-skip-permissions -p "$dev_prompt" 2>&1) || true
```

**Problem:** This bypasses safety checks and is concerning for production use.

**Proposed Fix:**
- Document the security implications clearly in README
- Add a `--require-approval` mode that doesn't use this flag
- Have the script detect and prompt for dangerous operations
- Consider environment variable to explicitly opt-in: `BMAD_ALLOW_DANGEROUS=true`

---

#### 2. Missing Test Execution Validation

**Location:** `epic-execute.sh` (dev phase)

**Problem:** The dev prompt says "Run tests and fix any failures" but the shell script doesn't verify tests actually passed. The completion signal (`IMPLEMENTATION COMPLETE`) is trusted without validation.

**Proposed Fix:**
```bash
# After dev phase, before review
execute_test_verification() {
    local test_cmd="${TEST_COMMAND:-npm test}"

    log ">>> VERIFYING TESTS"

    if ! $test_cmd 2>&1; then
        log_error "Tests failing after dev phase"
        return 1
    fi

    log_success "Tests passing"
    return 0
}
```

---

#### 3. Add Pre-flight Confirmation

**Location:** `epic-execute.sh` (after story discovery)

**Problem:** No validation step shows the user which stories will be executed before starting.

**Proposed Fix:**
```bash
# After discovering stories, before execution
display_execution_plan() {
    echo ""
    log "Execution Plan:"
    for story in "${STORIES[@]}"; do
        echo "  - $(basename "$story")"
    done
    echo ""

    if [ "$AUTO_APPROVE" != true ]; then
        read -p "Proceed with execution? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Execution cancelled by user"
            exit 0
        fi
    fi
}
```

---

### MEDIUM Priority

#### 4. Context Handoff is Placeholder

**Location:** `epic-chain.sh:411-432`

**Problem:** Current handoff only lists files changed:
```bash
$(git diff --name-only HEAD~${story_count} HEAD 2>/dev/null | head -20)
```

The documented template in `instructions.md:288-312` describes rich context (patterns, decisions, gotchas) but this isn't generated.

**Proposed Fix:**
```bash
generate_rich_handoff() {
    local epic_id="$1"
    local next_epic="$2"
    local handoff_file="$3"

    local handoff_prompt="You are generating a context handoff document.

## Task
Create a handoff from Epic $epic_id to Epic $next_epic.

## Recently Modified Files
$(git diff --name-only HEAD~${story_count} HEAD 2>/dev/null)

## Epic Content
$(cat "${EPIC_FILES_LIST[$current_idx]}")

## Generate a handoff document with:
1. Patterns Established - coding conventions, architectural decisions
2. Key Decisions - major technical choices with rationale
3. Gotchas & Lessons Learned - issues encountered, workarounds
4. Files to Reference - key files that establish patterns
5. Test Patterns - testing conventions used

Output as markdown."

    claude -p "$handoff_prompt" > "$handoff_file"
}
```

---

#### 5. No Rollback Mechanism

**Problem:** If review fails or execution gets interrupted mid-story, there's no easy way to rollback.

**Proposed Fix:**
```bash
# At start of epic execution
create_checkpoint() {
    CHECKPOINT=$(git rev-parse HEAD)
    echo "$CHECKPOINT" > "/tmp/bmad-checkpoint-$EPIC_ID"
    log "Checkpoint created: $CHECKPOINT"
}

# On failure or user abort
rollback_to_checkpoint() {
    if [ -f "/tmp/bmad-checkpoint-$EPIC_ID" ]; then
        local checkpoint=$(cat "/tmp/bmad-checkpoint-$EPIC_ID")
        read -p "Rollback to checkpoint $checkpoint? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git reset --hard "$checkpoint"
            log_success "Rolled back to checkpoint"
        fi
    fi
}
```

---

#### 6. Wire Up Configuration File

**Location:** `config/default-config.yaml` exists but isn't used

**Problem:** The configuration documented in `workflow.md:104-122` isn't actually loaded by the shell script.

**Proposed Fix:**
```bash
# Load configuration
load_config() {
    local config_file="$BMAD_DIR/_cfg/epic-execute.yaml"

    if [ -f "$config_file" ]; then
        # Parse YAML (requires yq or similar)
        AUTO_COMMIT=$(yq '.auto_commit // true' "$config_file")
        RUN_TESTS_BEFORE_REVIEW=$(yq '.run_tests_before_review // true' "$config_file")
        REVIEW_MODE=$(yq '.review_mode // "standard"' "$config_file")
        log "Loaded config from $config_file"
    else
        # Defaults
        AUTO_COMMIT=true
        RUN_TESTS_BEFORE_REVIEW=true
        REVIEW_MODE="standard"
    fi
}
```

---

#### 7. Remove or Implement `--parallel` Flag

**Location:** `epic-execute.sh:11, 93-96`

**Problem:** The `--parallel` flag exists in argument parsing but isn't implemented.

**Proposed Fix:** Either:
- Remove the flag entirely until implemented
- Add a clear error: `log_error "--parallel not yet implemented"`
- Implement parallel execution for independent stories

---

### LOW Priority

#### 8. Prompt Duplication

**Problem:** Prompts are duplicated between step files (documentation) and shell script (execution).

**Proposed Fix:** Source prompts from step files:
```bash
build_dev_prompt() {
    local story_file="$1"
    local template="$WORKFLOW_DIR/steps/step-02-dev-story.md"

    # Extract prompt template section
    # Substitute variables
    export story_id=$(basename "$story_file" .md)
    export story_file_contents=$(cat "$story_file")

    cat "$template" | envsubst
}
```

---

#### 9. Missing sprint-status.yaml Update

**Location:** `workflow.md:73` mentions this but it's not implemented

**Proposed Fix:** Add after successful completion:
```bash
update_sprint_status() {
    local status_file="$PROJECT_ROOT/docs/sprints/sprint-status.yaml"

    if [ -f "$status_file" ]; then
        # Update epic status to completed
        # This requires yq or similar YAML tool
        yq -i ".epics.\"$EPIC_ID\".status = \"done\"" "$status_file"
        yq -i ".epics.\"$EPIC_ID\".completed_at = \"$(date -Iseconds)\"" "$status_file"
    fi
}
```

---

#### 10. Story Discovery Edge Cases

**Location:** `epic-execute.sh:181-206`

**Problem:**
- Relies on consistent naming conventions
- Content grep could false-positive
- No warning when stories found in unexpected locations

**Proposed Fix:** Add source tracking and validation:
```bash
# Track where each story was found
declare -A STORY_SOURCES

for story in "${STORIES[@]}"; do
    source_dir=$(dirname "$story")
    STORY_SOURCES["$story"]="$source_dir"
done

# Warn about unexpected locations
for story in "${STORIES[@]}"; do
    if [[ "${STORY_SOURCES[$story]}" != "$STORIES_DIR" ]]; then
        log_warn "Story found in non-standard location: $story"
    fi
done
```

---

## Implementation Roadmap

### Phase 1: Critical Fixes
- [ ] Add test verification step
- [ ] Add pre-flight confirmation
- [ ] Document `--dangerously-skip-permissions` risks

### Phase 2: Reliability
- [ ] Implement rollback mechanism
- [ ] Wire up configuration file
- [ ] Fix or remove `--parallel` flag

### Phase 3: Quality of Life
- [ ] Generate rich context handoffs
- [ ] Source prompts from step files
- [ ] Add sprint-status.yaml updates

### Phase 4: Advanced Features
- [ ] Implement parallel story execution
- [ ] Add `--interactive` mode for step-by-step approval
- [ ] Track execution metrics (time per story, fix rate)

---

## Ratings Summary

| Aspect | Rating | Notes |
|--------|--------|-------|
| Architecture | Excellent | Context isolation is the right approach |
| Documentation | Very Good | Clear workflow diagrams, step files |
| Shell Scripts | Good | Well-structured, needs hardening |
| Error Handling | Fair | Basic coverage, needs rollback |
| Security | Needs Work | `--dangerously-skip-permissions` |
| Completeness | Good | Some features documented but not implemented |

---

## References

- `src/modules/bmm/workflows/4-implementation/epic-execute/`
- `src/modules/bmm/workflows/4-implementation/epic-chain/`
- `scripts/epic-execute.sh`
- `scripts/epic-chain.sh`
