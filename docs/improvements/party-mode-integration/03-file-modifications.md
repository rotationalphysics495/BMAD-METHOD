---
title: File Modifications Specification
---

# File Modifications Specification

**Document**: 03-file-modifications.md
**Version**: 1.0.0
**Date**: 2026-01-03

---

## Overview

This document provides the detailed specification for all file modifications required to implement Party Mode integration with Epic Execute.

---

## Summary of Changes

| File | Change Type | Lines Affected | Priority |
|------|-------------|----------------|----------|
| `scripts/epic-execute.sh` | Modify | +150 lines | Phase 1-3 |
| `config/default-config.yaml` | Modify | +50 lines | Phase 1 |
| `steps/step-01b-party-kickoff.md` | Create | ~100 lines | Phase 1 |
| `steps/step-03b-party-review.md` | Create | ~150 lines | Phase 2 |
| `steps/step-02b-party-failure.md` | Create | ~100 lines | Phase 3 |
| `steps/step-05b-party-retro.md` | Create | ~120 lines | Phase 4 |
| `workflow.md` | Modify | +20 lines | Phase 4 |

**Total**: ~690 lines across 7 files

---

## 1. Shell Script Modifications

### File: `scripts/epic-execute.sh`

#### 1.1 New Variables (Insert after line 76)

**Location**: After existing flag variables, before argument parsing

```bash
# =============================================================================
# Party Mode Flags
# =============================================================================

PARTY_KICKOFF=false
PARTY_REVIEW=false
PARTY_FAILURE=false
PARTY_RETRO=false
PARTY_AGENTS=""
```

---

#### 1.2 Argument Parsing (Insert within existing while loop, ~line 79-118)

**Location**: Add new cases to existing `while [[ $# -gt 0 ]]; do` block

```bash
        --party-kickoff)
            PARTY_KICKOFF=true
            shift
            ;;
        --party-review)
            PARTY_REVIEW=true
            shift
            ;;
        --party-failure)
            PARTY_FAILURE=true
            shift
            ;;
        --party-retro)
            PARTY_RETRO=true
            shift
            ;;
        --party-all)
            PARTY_KICKOFF=true
            PARTY_REVIEW=true
            PARTY_FAILURE=true
            PARTY_RETRO=true
            shift
            ;;
        --party-agents)
            PARTY_AGENTS="$2"
            shift 2
            ;;
```

---

#### 1.3 Usage Text Update (Modify existing usage block, ~line 121-132)

**Location**: Update the existing usage/help text

```bash
if [ -z "$EPIC_ID" ]; then
    echo "Usage: $0 <epic-id> [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run         Show what would be executed"
    echo "  --skip-review     Skip code review phase"
    echo "  --no-commit       Don't commit after stories"
    echo "  --parallel        Parallel execution (experimental)"
    echo "  --verbose         Detailed output"
    echo "  --start-from ID   Start from a specific story (e.g., 31-2)"
    echo "  --skip-done       Skip stories with Status: Done"
    echo ""
    echo "Party Mode Options:"
    echo "  --party-kickoff   Enable Story Kickoff Party before dev phase"
    echo "  --party-review    Enable multi-agent Party Review (replaces standard)"
    echo "  --party-failure   Enable Failure Analysis Party on blocked stories"
    echo "  --party-retro     Enable Post-Epic Retrospective Party"
    echo "  --party-all       Enable all party phases"
    echo "  --party-agents    Override agents (comma-separated, e.g., 'Winston,Murat')"
    exit 1
fi
```

---

#### 1.4 New Functions (Insert after line 230, before `execute_dev_phase`)

**Location**: New section for party mode functions

```bash
# =============================================================================
# Party Mode Functions
# =============================================================================

execute_party_kickoff() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log ">>> PARTY KICKOFF: $story_id"

    local story_contents=$(cat "$story_file")
    local agents="${PARTY_AGENTS:-Winston,Amelia,Murat}"

    local kickoff_prompt="You are orchestrating a Story Kickoff Party for BMAD.

## Participating Agents

You will roleplay as these agents, each contributing their unique perspective:

### Winston (Architect)
- Focus: Architectural implications, integration points, scalability concerns
- Style: Calm, pragmatic, balances 'what could be' with 'what should be'

### Amelia (Developer)
- Focus: Implementation approach, existing patterns to follow, potential gotchas
- Style: Practical, detail-oriented, focuses on what actually ships

### Murat (Test Architect)
- Focus: Testing strategy, edge cases, quality gates
- Style: Data-driven, risk-focused, 'strong opinions weakly held'

## Story to Discuss

<story>
$story_contents
</story>

## Your Task

Facilitate a focused discussion between these agents about this story BEFORE implementation begins. Each agent should contribute from their expertise area.

Generate responses in character for each agent, allowing them to build on each other's points.

## Output Requirements

After the discussion, append a 'Story Kickoff Insights' section to the story file at: $story_file

Use this exact format:

\`\`\`markdown
## Story Kickoff Insights

**Discussion Date**: $(date '+%Y-%m-%d')
**Participants**: Winston (Architect), Amelia (Developer), Murat (Test Architect)

### Architectural Notes
[Winston's key points about architecture, integration, patterns]

### Implementation Strategy
[Amelia's recommendations for implementation approach]

### Testing Approach
[Murat's test strategy and edge cases to consider]

### Identified Risks
- [Risk 1]
- [Risk 2]

### Key Decisions
- [Any decisions made during discussion]
\`\`\`

When complete, output exactly: KICKOFF COMPLETE: $story_id"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party kickoff for $story_id"
        echo "[DRY RUN] Agents: $agents"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$kickoff_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "KICKOFF COMPLETE"; then
        log_success "Party kickoff complete: $story_id"
        return 0
    else
        log_warn "Party kickoff did not complete cleanly (non-blocking)"
        return 0  # Non-blocking - continue to dev phase
    fi
}

execute_party_review() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)

    log ">>> PARTY REVIEW: $story_id (multi-agent)"

    local story_contents=$(cat "$story_file")
    local agents="${PARTY_AGENTS:-Winston,Murat,Amelia}"

    local review_prompt="You are orchestrating a Party Code Review for BMAD.

## Participating Agents

You will roleplay as these agents conducting a collaborative code review:

### Winston (Architect)
- Focus: Pattern adherence, scalability, API design consistency, component boundaries
- Style: Calm, pragmatic

### Murat (Test Architect)
- Focus: Test coverage, security vulnerabilities, edge cases, quality gates
- Style: Data-driven, risk calculations

### Amelia (Developer)
- Focus: Code quality, readability, maintainability, error handling
- Style: Practical, detail-oriented

## Story Being Reviewed

<story>
$story_contents
</story>

## Review Process

1. Run: git diff --staged
2. Each agent reviews from their focus area
3. Generate in-character responses for each agent
4. Allow agents to reference each other's points
5. Build consensus on issues found
6. Categorize by severity (HIGH/MEDIUM/LOW)

## Issue Severity Definitions

- **HIGH**: Security vulnerabilities, missing error handling, no tests, exposed credentials
- **MEDIUM**: Pattern violations, missing edge cases, hardcoded config
- **LOW**: Naming, style, missing comments

## Issue Fix Policy

After collecting all issues:
1. Always fix ALL HIGH severity issues
2. If TOTAL issues > 5, also fix ALL MEDIUM severity issues
3. LOW severity: document only, do NOT fix

## Output Format

Generate the review discussion, then update the story file with a Code Review Record:

\`\`\`markdown
## Code Review Record

**Review Type**: Party Review
**Date**: $(date '+%Y-%m-%d %H:%M')
**Reviewers**: Winston (Architect), Murat (Test Architect), Amelia (Developer)

### Agent Findings

#### Winston (Architecture)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

#### Murat (Quality)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

#### Amelia (Implementation)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

### Cross-Discussion Summary
[Key points where agents agreed/disagreed]

### Consensus Decision
- **Total Issues**: X HIGH, Y MEDIUM, Z LOW
- **Status**: Approved | Approved with Fixes | Rejected
- **Blocking Issues**: [if any]

### Fixes Applied
[List of fixes made]

### Remaining Issues (Low Severity)
[Documented for future cleanup]
\`\`\`

## Completion

If PASSED (no unfixed HIGH/MEDIUM issues):
1. Update story Status to: Done
2. Stage changes: git add -A
3. Output: PARTY REVIEW PASSED: $story_id

If FAILED:
1. Update story Status to: Blocked
2. Output: PARTY REVIEW FAILED: $story_id - [reason]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party review for $story_id"
        echo "[DRY RUN] Agents: $agents"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$review_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "PARTY REVIEW PASSED"; then
        log_success "Party review passed: $story_id"
        return 0
    elif echo "$result" | grep -q "PARTY REVIEW FAILED"; then
        log_error "Party review failed: $story_id"
        echo "$result" | grep "PARTY REVIEW FAILED"
        return 1
    else
        log_warn "Party review did not complete cleanly"
        return 1
    fi
}

execute_party_failure_analysis() {
    local story_file="$1"
    local failure_type="$2"  # "dev" or "review"
    local story_id=$(basename "$story_file" .md)

    log ">>> PARTY FAILURE ANALYSIS: $story_id ($failure_type phase)"

    local story_contents=$(cat "$story_file")
    local agents="${PARTY_AGENTS:-Winston,Amelia,Bob}"

    local failure_prompt="You are orchestrating a Failure Analysis Party for BMAD.

## Context

Story $story_id failed during the $failure_type phase.

## Participating Agents

### Winston (Architect)
- Assess: Is this an architectural issue? Design flaw? Integration problem?

### Amelia (Developer)
- Assess: Is this an implementation issue? Missing dependency? Code problem?

### Bob (Scrum Master)
- Assess: Is this a requirements issue? Unclear acceptance criteria? Process gap?

## Failed Story

<story>
$story_contents
</story>

## Failure Information

- **Phase**: $failure_type
- **Signal**: Story did not complete successfully

## Your Task

1. Each agent analyzes the failure from their perspective
2. Facilitate discussion to identify root cause
3. Build consensus on the actual problem
4. Recommend action: Retry | Skip | Escalate to Human

## Output Requirements

Append a Failure Analysis Record to the story file:

\`\`\`markdown
## Failure Analysis Record

**Analysis Date**: $(date '+%Y-%m-%d %H:%M')
**Failed Phase**: $failure_type
**Analysts**: Winston, Amelia, Bob

### Agent Assessments

#### Winston (Architecture)
[Assessment]

#### Amelia (Implementation)
[Assessment]

#### Bob (Process)
[Assessment]

### Root Cause (Consensus)
[What the team agreed is the actual problem]

### Remediation Plan
1. [Step 1]
2. [Step 2]

### Recommendation
**Action**: Retry | Skip | Escalate
**Rationale**: [Why this action]
\`\`\`

When complete, output: ANALYSIS COMPLETE: $story_id - [Retry|Skip|Escalate]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute failure analysis for $story_id"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$failure_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "ANALYSIS COMPLETE"; then
        log_success "Failure analysis complete: $story_id"
        # Extract recommendation for potential future use
        local recommendation=$(echo "$result" | grep "ANALYSIS COMPLETE" | sed 's/.*- //')
        log "Recommendation: $recommendation"
    else
        log_warn "Failure analysis did not complete cleanly"
    fi

    return 0  # Non-blocking - failure analysis is informational
}

execute_party_retro() {
    log ">>> PARTY RETROSPECTIVE: Epic $EPIC_ID"

    local epic_contents=$(cat "$EPIC_FILE")
    local agents="${PARTY_AGENTS:-Mary,Bob,Winston,Amelia}"

    # Aggregate all story contents
    local all_stories=""
    for story_file in "${STORIES[@]}"; do
        local story_id=$(basename "$story_file" .md)
        all_stories+="
<story id=\"$story_id\">
$(cat "$story_file")
</story>
"
    done

    local retro_prompt="You are orchestrating a Post-Epic Retrospective Party for BMAD.

## Participating Agents

### Mary (Business Analyst)
- Reflect on: Requirements clarity, business value delivered, stakeholder alignment

### Bob (Scrum Master)
- Reflect on: Sprint flow, story sizing, process effectiveness, blockers encountered

### Winston (Architect)
- Reflect on: Technical decisions made, patterns established, architectural debt

### Amelia (Developer)
- Reflect on: Implementation experience, code quality, developer experience

## Epic Completed

<epic>
$epic_contents
</epic>

## Stories Completed

$all_stories

## Execution Summary

- Total Stories: ${#STORIES[@]}
- Completed: $COMPLETED
- Failed: $FAILED

## Your Task

Facilitate a retrospective discussion where each agent reflects from their perspective:

1. What Went Well (each agent's view)
2. What Could Improve (each agent's view)
3. Patterns Established (for future reference)
4. Key Decisions Made (document for posterity)
5. Lessons Learned (gotchas, workarounds)
6. Context Handoff (for next epic)

## Output Requirements

Create TWO files:

### 1. Retrospective Document
Save to: docs/sprints/epic-${EPIC_ID}-retro.md

\`\`\`markdown
# Epic $EPIC_ID Retrospective

**Date**: $(date '+%Y-%m-%d')
**Participants**: Mary, Bob, Winston, Amelia

## What Went Well

### Mary (Requirements)
[Points]

### Bob (Process)
[Points]

### Winston (Architecture)
[Points]

### Amelia (Implementation)
[Points]

## Areas for Improvement

### Mary (Requirements)
[Points]

### Bob (Process)
[Points]

### Winston (Architecture)
[Points]

### Amelia (Implementation)
[Points]

## Action Items
- [ ] [Action 1]
- [ ] [Action 2]
\`\`\`

### 2. Context Handoff Document
Save to: docs/handoffs/epic-${EPIC_ID}-handoff.md

\`\`\`markdown
# Epic $EPIC_ID Context Handoff

**Generated**: $(date '+%Y-%m-%d')
**For**: Next epic in chain

## Patterns Established
| Pattern | Description | Example File |
|---------|-------------|--------------|

## Key Decisions
| Decision | Rationale | Made By |
|----------|-----------|---------|

## Gotchas & Lessons Learned
1. [Gotcha]: [What to watch for]

## Files to Reference
- [Key file 1]: [Why it's important]

## Test Patterns
[Testing conventions established]
\`\`\`

When complete, output: RETRO COMPLETE: Epic $EPIC_ID"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party retrospective for Epic $EPIC_ID"
        return 0
    fi

    # Ensure output directories exist
    mkdir -p "$PROJECT_ROOT/docs/sprints"
    mkdir -p "$PROJECT_ROOT/docs/handoffs"

    local result
    result=$(claude --dangerously-skip-permissions -p "$retro_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "RETRO COMPLETE"; then
        log_success "Party retrospective complete"

        # Commit retro artifacts if auto-commit enabled
        if [ "$NO_COMMIT" = false ]; then
            git add "docs/sprints/epic-${EPIC_ID}-retro.md" 2>/dev/null || true
            git add "docs/handoffs/epic-${EPIC_ID}-handoff.md" 2>/dev/null || true
            git commit -m "docs(epic-$EPIC_ID): add retrospective and handoff" 2>/dev/null || true
        fi
    else
        log_warn "Retrospective may not have completed cleanly"
    fi

    return 0  # Non-blocking
}
```

---

#### 1.5 Main Loop Modifications (Modify existing loop, ~line 547-596)

**Location**: Replace the existing main execution loop

```bash
# =============================================================================
# Main Execution Loop
# =============================================================================

log "=========================================="
log "Starting execution of ${#STORIES[@]} stories"
if [ "$PARTY_KICKOFF" = true ]; then log "  Party Kickoff: ENABLED"; fi
if [ "$PARTY_REVIEW" = true ]; then log "  Party Review: ENABLED"; fi
if [ "$PARTY_FAILURE" = true ]; then log "  Party Failure Analysis: ENABLED"; fi
if [ "$PARTY_RETRO" = true ]; then log "  Party Retrospective: ENABLED"; fi
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
            continue
        fi
    fi

    # --skip-done: Skip stories with Status: Done
    if [ "$SKIP_DONE" = true ]; then
        if grep -q "^Status:.*Done" "$story_file" 2>/dev/null; then
            log_warn "Skipping $story_id (Status: Done)"
            ((SKIPPED++))
            continue
        fi
    fi

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Story: $story_id"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # PARTY KICKOFF (Optional - Context 0)
    if [ "$PARTY_KICKOFF" = true ]; then
        execute_party_kickoff "$story_file"
        # Non-blocking - continues even if kickoff has issues
    fi

    # DEV PHASE (Context A)
    if ! execute_dev_phase "$story_file"; then
        log_error "Dev phase failed for $story_id"

        # PARTY FAILURE ANALYSIS (Optional)
        if [ "$PARTY_FAILURE" = true ]; then
            execute_party_failure_analysis "$story_file" "dev"
        fi

        ((FAILED++))
        continue
    fi

    # REVIEW PHASE (Context B)
    if [ "$SKIP_REVIEW" = false ]; then
        if [ "$PARTY_REVIEW" = true ]; then
            # Multi-agent party review
            if ! execute_party_review "$story_file"; then
                log_error "Party review failed for $story_id"

                # PARTY FAILURE ANALYSIS (Optional)
                if [ "$PARTY_FAILURE" = true ]; then
                    execute_party_failure_analysis "$story_file" "review"
                fi

                ((FAILED++))
                continue
            fi
        else
            # Standard single-agent review (existing behavior)
            if ! execute_review_phase "$story_file"; then
                log_error "Review phase failed for $story_id"
                ((FAILED++))
                continue
            fi
        fi
    fi

    # COMMIT
    commit_story "$story_id"

    ((COMPLETED++))
    log_success "Story complete: $story_id ($COMPLETED/${#STORIES[@]})"
done

# =============================================================================
# Post-Epic Activities
# =============================================================================

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Post-Epic Activities"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# UAT Generation (Standard - Context C)
generate_uat

# PARTY RETROSPECTIVE (Optional - Context R)
if [ "$PARTY_RETRO" = true ]; then
    execute_party_retro
fi
```

---

## 2. Configuration File Modifications

### File: `src/modules/bmm/workflows/4-implementation/epic-execute/config/default-config.yaml`

**Location**: Append to end of existing file (after line 125)

```yaml
# =============================================================================
# Party Mode Integration
# =============================================================================

party:
  # Story Kickoff Party - multi-agent discussion before dev phase
  kickoff:
    # Enable kickoff party (overridden by --party-kickoff flag)
    enabled: false

    # Default agents for kickoff discussions
    agents:
      - Winston    # Architect - architectural implications
      - Amelia     # Developer - implementation concerns
      - Murat      # Test Architect - testing strategy

    # Maximum time for kickoff discussion (seconds)
    timeout: 300

    # Where to save kickoff insights: story | separate | none
    output: story

  # Party Review - replace single-agent review with multi-agent
  review:
    # Enable party review (overridden by --party-review flag)
    enabled: false

    # Default agents for review
    agents:
      - Winston    # Architecture alignment, patterns
      - Murat      # Test coverage, security
      - Amelia     # Code quality, maintainability

    # Maximum time for review discussion (seconds)
    timeout: 600

    # Require all agents to approve (vs majority)
    consensus_required: false

  # Failure Analysis Party - triggered on story failure
  failure_analysis:
    # Enable failure analysis (overridden by --party-failure flag)
    enabled: false

    # Default agents for failure analysis
    agents:
      - Winston    # Architectural blockers
      - Amelia     # Implementation issues
      - Bob        # Process/requirement issues

    # Automatically trigger on any failure
    auto_trigger: true

  # Post-Epic Retrospective Party
  retrospective:
    # Enable retrospective (overridden by --party-retro flag)
    enabled: false

    # Default agents for retrospective
    agents:
      - Mary       # Business Analyst - requirements reflection
      - Bob        # Scrum Master - process reflection
      - Winston    # Architect - technical reflection
      - Amelia     # Developer - implementation reflection

    # Generate context handoff document for epic-chain
    generate_handoff: true

    # Output locations (relative to project root)
    retro_output: docs/sprints
    handoff_output: docs/handoffs

  # Global party settings
  settings:
    # Maximum agents per party phase (to limit context usage)
    max_agents: 4

    # Enable TTS for party responses (requires bmad-speak hook)
    tts_enabled: false

    # Party output format: markdown | yaml | json
    output_format: markdown

    # Log full party discussions (verbose)
    log_discussions: false
```

---

## 3. New Step Files

### File: `steps/step-01b-party-kickoff.md`

**Location**: `src/modules/bmm/workflows/4-implementation/epic-execute/steps/`

This file serves as documentation. The actual prompt is embedded in the shell script function.

```markdown
# Step 1b: Story Kickoff Party (Optional)

## Context Isolation

This step executes in a fresh Claude context BEFORE the dev phase. It does not pollute the dev context with discussion history - only the resulting insights are transferred via the story file.

## Objective

Bring together 2-3 agents for a focused pre-implementation discussion to surface architectural concerns, implementation strategies, and testing approaches before code is written.

## Trigger

Enabled via `--party-kickoff` flag or `party.kickoff.enabled: true` in config.

## Default Agents

| Agent | Focus Area |
|-------|------------|
| Winston (Architect) | Architectural implications, integration points, patterns |
| Amelia (Developer) | Implementation approach, existing code to leverage |
| Murat (Test Architect) | Testing strategy, edge cases, quality gates |

## Input

- Story file contents (original specification)
- Agent personas from configuration

## Output

Appends "Story Kickoff Insights" section to the story file with:
- Architectural Notes
- Implementation Strategy
- Testing Approach
- Identified Risks
- Key Decisions

## Transfer to Dev Phase

The dev phase prompt instructs: "Read the story file completely before writing any code"

This means the dev agent sees the kickoff insights and can leverage them, without the kickoff discussion consuming dev context window.

## Completion Signal

```
KICKOFF COMPLETE: {story_id}
```

## Error Handling

Kickoff is **non-blocking**. If it fails or times out:
- Log warning
- Continue to dev phase
- Dev phase proceeds without kickoff insights

This design ensures kickoff adds value without becoming a critical path blocker.

## Example Output

```markdown
## Story Kickoff Insights

**Discussion Date**: 2026-01-03
**Participants**: Winston (Architect), Amelia (Developer), Murat (Test Architect)

### Architectural Notes
- This story adds a new API endpoint; follow existing REST patterns in src/routes/
- Consider rate limiting (deferred to Epic 43)
- Integration point with AuthService requires careful error handling

### Implementation Strategy
- Extend existing UserService rather than creating new class
- Reuse validation utilities from lib/validators
- Follow repository pattern established in src/repositories/

### Testing Approach
- Unit tests for service methods using Jest
- Integration test for full request/response cycle
- Mock external API calls using fixtures in test/fixtures/

### Identified Risks
- External API rate limit may cause flaky tests
- Database migration required for new fields

### Key Decisions
- Use bcrypt for password hashing (industry standard, already a dependency)
- Async email verification (non-blocking user registration flow)
```
```

---

### File: `steps/step-03b-party-review.md`

**Location**: `src/modules/bmm/workflows/4-implementation/epic-execute/steps/`

```markdown
# Step 3b: Party Review (Multi-Agent Code Review)

## Context Isolation

This step executes in a fresh Claude context, separate from dev phase. Reviewers have no knowledge of implementation struggles - they see code "cold" via git diff.

## Objective

Replace single-agent code review with multi-agent collaborative review where each agent focuses on their domain expertise for more thorough coverage.

## Trigger

Enabled via `--party-review` flag or `party.review.enabled: true` in config.

When enabled, this REPLACES the standard review (step-03-code-review.md).

## Default Agents

| Agent | Focus Area |
|-------|------------|
| Winston (Architect) | Pattern adherence, scalability, API design, component boundaries |
| Murat (Test Architect) | Test coverage, security, edge cases, quality gates |
| Amelia (Developer) | Code quality, readability, error handling, maintainability |

## Input

- Story file contents (includes Dev Agent Record from dev phase)
- Git staged changes (`git diff --staged`)

## Review Protocol

1. **Independent Analysis**: Each agent reviews from their perspective
2. **Cross-Discussion**: Agents discuss findings, reference each other
3. **Consensus Building**: Agree on blocking issues and fix priorities
4. **Issue Categorization**: HIGH / MEDIUM / LOW severity
5. **Fix Policy**: Same as standard review
   - Always fix HIGH
   - Fix MEDIUM if total > 5
   - Document LOW only

## Output

Updates story file with "Code Review Record" section containing:
- Agent-specific findings tables
- Cross-discussion summary
- Consensus decision
- Fixes applied
- Remaining issues

## Completion Signals

```
PARTY REVIEW PASSED: {story_id}
PARTY REVIEW PASSED WITH FIXES: {story_id} - Fixed N issues
PARTY REVIEW FAILED: {story_id} - {reason}
```

## Advantages Over Single-Agent Review

| Aspect | Single-Agent | Party Review |
|--------|--------------|--------------|
| Perspectives | 1 | 3 |
| Blind spots | More | Fewer |
| Architecture focus | General | Dedicated (Winston) |
| Security focus | General | Dedicated (Murat) |
| Code quality focus | General | Dedicated (Amelia) |
| Discussion | None | Cross-talk, debate |
```

---

### File: `steps/step-02b-party-failure.md`

**Location**: `src/modules/bmm/workflows/4-implementation/epic-execute/steps/`

```markdown
# Step 2b: Failure Analysis Party

## Context

Triggered when a story fails during dev or review phase.

## Objective

Convene agents to diagnose root cause, propose remediation, and recommend next action.

## Trigger

- Dev phase outputs: `IMPLEMENTATION BLOCKED`
- Review phase outputs: `REVIEW FAILED`
- Enabled via `--party-failure` flag

## Default Agents

| Agent | Assessment Focus |
|-------|------------------|
| Winston (Architect) | Is this an architectural issue? Design flaw? |
| Amelia (Developer) | Is this an implementation issue? Missing dependency? |
| Bob (Scrum Master) | Is this a requirements issue? Process gap? |

## Input

- Story file (current state, may have partial records)
- Failure type: "dev" or "review"
- Failure message (if available)

## Output

Appends "Failure Analysis Record" to story file with:
- Agent assessments
- Root cause (consensus)
- Remediation plan
- Recommendation (Retry | Skip | Escalate)

## Completion Signal

```
ANALYSIS COMPLETE: {story_id} - Retry
ANALYSIS COMPLETE: {story_id} - Skip
ANALYSIS COMPLETE: {story_id} - Escalate
```

## Non-Blocking

Failure analysis is informational. The current implementation logs the recommendation but does not automatically act on it. Future enhancement could wire Retry/Skip/Escalate into the loop.
```

---

### File: `steps/step-05b-party-retro.md`

**Location**: `src/modules/bmm/workflows/4-implementation/epic-execute/steps/`

```markdown
# Step 5b: Post-Epic Retrospective Party

## Context

Executed after all stories complete (regardless of success/failure).

## Objective

Conduct multi-agent retrospective to:
- Reflect on what worked and what didn't
- Capture patterns and decisions for future reference
- Generate rich context handoff for epic-chain workflows

## Trigger

Enabled via `--party-retro` flag or `party.retrospective.enabled: true` in config.

## Default Agents

| Agent | Reflection Focus |
|-------|------------------|
| Mary (Business Analyst) | Requirements clarity, business value delivered |
| Bob (Scrum Master) | Sprint flow, process effectiveness, blockers |
| Winston (Architect) | Technical decisions, patterns, architectural debt |
| Amelia (Developer) | Implementation experience, code quality, DX |

## Input

- Epic file
- ALL completed story files (aggregated)
- Execution summary (completed/failed counts)

## Output

Creates TWO new files:

### 1. Retrospective Document
`docs/sprints/epic-{id}-retro.md`

Contains:
- What Went Well (per agent)
- Areas for Improvement (per agent)
- Action Items

### 2. Context Handoff Document
`docs/handoffs/epic-{id}-handoff.md`

Contains:
- Patterns Established
- Key Decisions
- Gotchas & Lessons Learned
- Files to Reference
- Test Patterns

## Integration with Epic-Chain

The handoff document is automatically loaded by epic-chain when executing the next epic, providing rich context that the "placeholder" handoff currently lacks.

## Completion Signal

```
RETRO COMPLETE: Epic {epic_id}
```
```

---

## 4. Workflow Documentation Update

### File: `workflow.md`

**Location**: `src/modules/bmm/workflows/4-implementation/epic-execute/workflow.md`

**Modification**: Add Party Mode section after existing content (~line 100)

```markdown
## Party Mode Integration (Optional)

Epic Execute supports optional Party Mode phases for multi-agent collaboration:

| Flag | Phase | Purpose |
|------|-------|---------|
| `--party-kickoff` | Pre-Dev | Multi-agent discussion before implementation |
| `--party-review` | Review | Replaces single-agent review with multi-agent |
| `--party-failure` | On Failure | Root cause analysis when stories fail |
| `--party-retro` | Post-Epic | Team retrospective with context handoff |
| `--party-all` | All | Enables all party phases |

### Enhanced Flow with Party Mode

```
┌──────────────┐
│ Party:       │ ← --party-kickoff
│ Kickoff      │
└──────┬───────┘
       ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Dev Phase    │───►│ Review Phase │───►│ Commit       │
│              │    │ (Standard OR │    │              │
│              │    │  Party)      │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
       │
       ▼ (on failure)
┌──────────────┐
│ Party:       │ ← --party-failure
│ Failure      │
│ Analysis     │
└──────────────┘

Post-Epic:
┌──────────────┐
│ Party:       │ ← --party-retro
│ Retrospective│
└──────────────┘
```

### Documentation

See `docs/improvements/party-mode-integration/` for detailed implementation documentation.
```

---

## 5. Directory Structure After Implementation

```
src/modules/bmm/workflows/4-implementation/epic-execute/
├── workflow.md                          # Updated with party mode references
├── config/
│   └── default-config.yaml              # Updated with party section
├── steps/
│   ├── step-01-init.md                  # Existing (unchanged)
│   ├── step-01b-party-kickoff.md        # NEW
│   ├── step-02-dev-story.md             # Existing (unchanged)
│   ├── step-02b-party-failure.md        # NEW
│   ├── step-03-code-review.md           # Existing (unchanged, used when party-review disabled)
│   ├── step-03b-party-review.md         # NEW
│   ├── step-04-generate-uat.md          # Existing (unchanged)
│   ├── step-05-summary.md               # Existing (unchanged)
│   └── step-05b-party-retro.md          # NEW
└── ...

scripts/
└── epic-execute.sh                      # Updated with party functions

docs/improvements/party-mode-integration/
├── README.md                            # Index document
├── 01-implementation-plan.md            # High-level plan
├── 02-context-management.md             # Context architecture
└── 03-file-modifications.md             # This document
```

---

## 6. Implementation Checklist

### Phase 1: Foundation
- [ ] Add party flag variables to `epic-execute.sh`
- [ ] Add argument parsing for party flags
- [ ] Update usage/help text
- [ ] Add party section to `default-config.yaml`
- [ ] Implement `execute_party_kickoff()` function
- [ ] Create `step-01b-party-kickoff.md`
- [ ] Test kickoff with sample story

### Phase 2: Party Review
- [ ] Implement `execute_party_review()` function
- [ ] Create `step-03b-party-review.md`
- [ ] Add conditional in main loop for party vs standard review
- [ ] Test party review with sample story

### Phase 3: Failure Analysis
- [ ] Implement `execute_party_failure_analysis()` function
- [ ] Create `step-02b-party-failure.md`
- [ ] Wire into dev/review failure paths
- [ ] Test with intentionally failing story

### Phase 4: Retrospective
- [ ] Implement `execute_party_retro()` function
- [ ] Create `step-05b-party-retro.md`
- [ ] Add to post-epic section of main loop
- [ ] Test with completed epic
- [ ] Verify handoff document integrates with epic-chain

### Phase 5: Polish
- [ ] Update `workflow.md` with party mode documentation
- [ ] Add `--party-agents` override support
- [ ] Test all combinations of flags
- [ ] Update main README if needed
