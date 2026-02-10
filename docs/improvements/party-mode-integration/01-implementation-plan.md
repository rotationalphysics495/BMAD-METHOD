---
title: "Implementation Plan: Party Mode Integration with Epic Execute"
---

# Implementation Plan: Party Mode Integration with Epic Execute

## Option B: Configurable Party Mode

**Version**: 1.0.0
**Status**: Draft
**Author**: BMad Method
**Date**: 2026-01-03

---

## Related Documents

| Document | Description |
|----------|-------------|
| [README.md](./README.md) | Overview and quick reference |
| [02-context-management.md](./02-context-management.md) | Deep dive into context isolation and data transfer |
| [03-file-modifications.md](./03-file-modifications.md) | Detailed file change specifications |

---

## Executive Summary

This plan integrates Party Mode's multi-agent collaboration capabilities into the Epic Execute workflow through configurable CLI flags. Users can enable party phases at specific workflow points to gain diverse agent perspectives during story implementation.

---

## 1. New CLI Flags

### Shell Script Arguments

Add the following flags to `scripts/epic-execute.sh`:

```bash
# Party Mode Integration Flags
--party-kickoff       Enable Story Kickoff Party before each story's dev phase
--party-review        Replace single-agent review with multi-agent Party Review
--party-failure       Enable Failure Analysis Party when stories fail
--party-retro         Enable Post-Epic Retrospective Party after all stories
--party-all           Enable all party phases (equivalent to all flags above)
--party-agents LIST   Override default agents for party phases (comma-separated)
```

### Usage Examples

```bash
# Enable kickoff discussions only
./epic-execute.sh 42 --party-kickoff

# Full party integration
./epic-execute.sh 42 --party-all

# Custom review with specific agents
./epic-execute.sh 42 --party-review --party-agents "Winston,Murat,Amelia"

# Kickoff + Review (most common)
./epic-execute.sh 42 --party-kickoff --party-review

# With existing flags
./epic-execute.sh 42 --party-all --skip-done --verbose
```

---

## 2. Configuration File Updates

### File: `config/default-config.yaml`

Add new `party` section:

```yaml
# Party Mode Integration
party:
  # Story Kickoff Party - multi-agent discussion before dev phase
  kickoff:
    enabled: false
    agents:
      - Winston    # Architect - architectural implications
      - Amelia     # Developer - implementation concerns
      - Murat      # Test Architect - testing strategy
    timeout: 300   # Max seconds for kickoff discussion
    output: story  # Where to save insights: story | separate | none

  # Party Review - replace single-agent review with multi-agent
  review:
    enabled: false
    agents:
      - Winston    # Architecture alignment
      - Murat      # Test coverage, security
      - Amelia     # Code quality, maintainability
    timeout: 600   # Max seconds for review party
    consensus_required: false  # Require all agents to approve

  # Failure Analysis Party - triggered on story failure
  failure_analysis:
    enabled: false
    agents:
      - Winston    # Architectural blockers
      - Amelia     # Implementation issues
      - Bob        # Process/requirement issues
    auto_trigger: true  # Auto-trigger on any failure

  # Post-Epic Retrospective Party
  retrospective:
    enabled: false
    agents:
      - Mary       # Business Analyst - requirements reflection
      - Bob        # Scrum Master - process reflection
      - Winston    # Architect - technical reflection
      - Amelia     # Developer - implementation reflection
    generate_handoff: true  # Generate rich context handoff document

  # Global party settings
  settings:
    # Communication language for all party discussions
    language: "{{communication_language}}"

    # Enable TTS for party responses
    tts_enabled: false

    # Max agents per party phase
    max_agents: 4

    # Party output format: markdown | yaml | json
    output_format: markdown
```

---

## 3. Workflow Integration Points

### Enhanced Epic Execute Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   ENHANCED EPIC EXECUTE FLOW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  For each story:                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                   │   │
│  │  ┌──────────────────┐                                            │   │
│  │  │ PARTY: Kickoff   │  ← --party-kickoff                        │   │
│  │  │ (Optional)       │     Winston + Amelia + Murat               │   │
│  │  │                  │     Output: Implementation strategy        │   │
│  │  └────────┬─────────┘     Saved to: Story file or separate doc   │   │
│  │           │                                                       │   │
│  │           ▼                                                       │   │
│  │  ┌──────────────────┐                                            │   │
│  │  │   Phase 1: Dev   │  Context A (Isolated)                      │   │
│  │  │   (Standard)     │  Includes kickoff insights if generated    │   │
│  │  └────────┬─────────┘                                            │   │
│  │           │                                                       │   │
│  │           ▼ success                    ▼ failure                 │   │
│  │  ┌──────────────────┐         ┌──────────────────┐               │   │
│  │  │ Phase 2: Review  │         │ PARTY: Failure   │               │   │
│  │  │                  │         │ Analysis         │ ← --party-fail│   │
│  │  │ --party-review?  │         │ (Optional)       │               │   │
│  │  │ ┌──────────────┐ │         └────────┬─────────┘               │   │
│  │  │ │ YES: Party   │ │                  │                         │   │
│  │  │ │ Review       │ │                  ▼                         │   │
│  │  │ │ Winston +    │ │         ┌──────────────────┐               │   │
│  │  │ │ Murat +      │ │         │ Retry or Skip    │               │   │
│  │  │ │ Amelia       │ │         └──────────────────┘               │   │
│  │  │ └──────────────┘ │                                            │   │
│  │  │ ┌──────────────┐ │                                            │   │
│  │  │ │ NO: Standard │ │                                            │   │
│  │  │ │ Single-agent │ │                                            │   │
│  │  │ │ Review       │ │                                            │   │
│  │  │ └──────────────┘ │                                            │   │
│  │  └────────┬─────────┘                                            │   │
│  │           │                                                       │   │
│  │           ▼                                                       │   │
│  │  ┌──────────────────┐                                            │   │
│  │  │ Phase 3: Commit  │  Shell orchestration                       │   │
│  │  └──────────────────┘                                            │   │
│  │                                                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  After all stories:                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                   │   │
│  │  ┌──────────────────┐    ┌──────────────────┐                   │   │
│  │  │ Phase 4: UAT     │    │ PARTY: Retro     │ ← --party-retro   │   │
│  │  │ Generation       │    │ (Optional)       │                   │   │
│  │  │ (Standard)       │    │ Mary + Bob +     │                   │   │
│  │  │                  │    │ Winston + Amelia │                   │   │
│  │  └──────────────────┘    │                  │                   │   │
│  │                          │ Output:          │                   │   │
│  │                          │ - Retro insights │                   │   │
│  │                          │ - Context handoff│                   │   │
│  │                          │ - Patterns doc   │                   │   │
│  │                          └──────────────────┘                   │   │
│  │                                                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. New Step Files

### 4.1 Story Kickoff Party

**File**: `steps/step-01b-party-kickoff.md`

```markdown
# Step 1b: Story Kickoff Party

## Purpose

Bring together 2-3 agents for a focused discussion before implementation begins.
Surface architectural concerns, implementation challenges, and testing strategies.

## Agents

Default: Winston (Architect), Amelia (Developer), Murat (Test Architect)
Override: Via --party-agents flag or config

## Input Context

- Story specification (acceptance criteria, technical context)
- Architecture document
- Related stories in the epic

## Discussion Topics

1. **Architectural Implications**
   - Winston: How does this fit the overall architecture?
   - What integration points exist?
   - Are there scalability concerns?

2. **Implementation Approach**
   - Amelia: What patterns should we follow?
   - Are there existing utilities to leverage?
   - What are the tricky parts?

3. **Testing Strategy**
   - Murat: What test types are needed?
   - What edge cases should we cover?
   - Are there test fixtures we need?

## Output Format

```yaml
## Story Kickoff Insights

**Discussion Date**: {{date}}
**Participants**: {{agent_list}}

### Architectural Notes
[Winston's key points]

### Implementation Strategy
[Amelia's recommendations]

### Testing Approach
[Murat's test strategy]

### Identified Risks
- [Risk 1]
- [Risk 2]

### Decisions Made
- [Decision 1 with rationale]
```

## Success Criteria (Analysis Party)

- All agents contributed perspective
- Clear implementation direction established
- Risks identified and documented
- Ready for dev phase to proceed
```

---

### 4.2 Party Review

**File**: `steps/step-03b-party-review.md`

```markdown
# Step 3b: Party Review (Multi-Agent Code Review)

## Purpose

Replace single-agent code review with multi-agent collaborative review.
Each agent focuses on their domain expertise for thorough coverage.

## Agents

Default: Winston (Architect), Murat (Test Architect), Amelia (Developer)
Override: Via --party-agents flag or config

## Agent Focus Areas

### Winston (Architecture)
- Pattern adherence
- Scalability implications
- API design consistency
- Component boundaries
- Integration concerns

### Murat (Quality)
- Test coverage completeness
- Test quality and meaningfulness
- Security vulnerabilities
- Edge case handling
- CI/CD implications

### Amelia (Implementation)
- Code quality and readability
- Error handling
- Performance considerations
- Documentation quality
- Maintainability

## Review Protocol

1. **Independent Analysis** (per agent)
   - Each agent reviews from their perspective
   - Categorizes findings by severity (HIGH/MEDIUM/LOW)

2. **Cross-Discussion**
   - Agents discuss findings
   - Resolve conflicting opinions
   - Prioritize issues collectively

3. **Consensus Building**
   - Agree on which issues block approval
   - Agree on fix priorities
   - Generate unified review record

## Output Format

```yaml
## Party Review Record

**Review Date**: {{date}}
**Reviewers**: {{agent_list}}

### Agent Findings

#### 🏗️ Winston (Architecture)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

#### 🧪 Murat (Quality)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

#### 💻 Amelia (Implementation)
| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|

### Cross-Discussion Notes
[Key discussion points and resolutions]

### Consensus Decision
- **Status**: Approved | Approved with Fixes | Rejected
- **Blocking Issues**: [List if any]
- **Required Fixes**: [Prioritized list]

### Fixes Applied
[List of changes made during review]
```

## Issue Fix Policy

Same as standard review:
- HIGH: Always fix
- MEDIUM: Fix if total > 5
- LOW: Document only

## Success Criteria (Review Party)

- All agents completed their review focus
- Issues categorized and prioritized
- Consensus reached on approval status
- Required fixes applied and verified
```

---

### 4.3 Failure Analysis Party

**File**: `steps/step-02b-party-failure.md`

```markdown
# Step 2b: Failure Analysis Party

## Purpose

When a story fails (dev blocked or review failed), convene agents to:
- Diagnose root cause
- Propose remediation
- Identify process improvements

## Trigger Conditions

- Dev phase outputs: `IMPLEMENTATION BLOCKED`
- Review phase outputs: `REVIEW FAILED`
- Test failures after max retries

## Agents

Default: Winston (Architect), Amelia (Developer), Bob (Scrum Master)
Override: Via --party-agents flag

## Discussion Protocol

1. **Failure Context Sharing**
   - Present the failure message/log
   - Share relevant code context
   - Show what was attempted

2. **Root Cause Analysis**
   - Winston: Is this an architectural issue?
   - Amelia: Is this a technical implementation issue?
   - Bob: Is this a requirements/process issue?

3. **Remediation Planning**
   - What needs to change?
   - Who/what is best positioned to fix it?
   - Are there blocking dependencies?

4. **Process Improvement**
   - Could this have been caught earlier?
   - What should we do differently next time?

## Output Format

```yaml
## Failure Analysis Record

**Analysis Date**: {{date}}
**Story**: {{story_id}}
**Failure Type**: Dev Blocked | Review Failed | Test Failure
**Analysts**: {{agent_list}}

### Failure Summary
[What happened]

### Root Cause Analysis

#### Winston's Assessment
[Architectural perspective]

#### Amelia's Assessment
[Implementation perspective]

#### Bob's Assessment
[Process/requirements perspective]

### Agreed Root Cause
[Consensus diagnosis]

### Remediation Plan
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Blocking Dependencies
- [Dependency 1]

### Process Improvements
- [Improvement for future]

### Recommendation
- **Action**: Retry | Skip | Escalate to Human
- **Rationale**: [Why this action]
```

## Success Criteria (Failure Analysis)

- Root cause identified
- Remediation path clear
- Actionable next step determined
```

---

### 4.4 Post-Epic Retrospective Party

**File**: `steps/step-05b-party-retro.md`

```markdown
# Step 5b: Post-Epic Retrospective Party

## Purpose

After all stories complete, conduct a multi-agent retrospective to:
- Reflect on what worked and what didn't
- Capture patterns and decisions for future reference
- Generate rich context handoff for epic-chain workflows

## Agents

Default: Mary (Analyst), Bob (Scrum Master), Winston (Architect), Amelia (Developer)
Override: Via --party-agents flag

## Input Context

- All completed story files (with Dev Agent Records and Code Review Records)
- Epic specification
- Execution log/summary

## Discussion Topics

### 1. What Went Well
- Mary: Were requirements clear? Did implementation match intent?
- Bob: How was the sprint flow? Were stories well-sized?
- Winston: Did architecture hold up? Good technical decisions?
- Amelia: Code quality? Patterns established? Developer experience?

### 2. What Could Improve
- Mary: Requirement gaps or ambiguities discovered?
- Bob: Process bottlenecks or inefficiencies?
- Winston: Architectural debt introduced? Future concerns?
- Amelia: Implementation struggles? Missing tooling?

### 3. Patterns Established
- What coding patterns emerged?
- What testing patterns were effective?
- What documentation patterns helped?

### 4. Knowledge Transfer
- What should the next epic's team know?
- What gotchas did we discover?
- What shortcuts are now available?

## Output Format

```yaml
## Epic {{epic_id}} Retrospective

**Date**: {{date}}
**Participants**: {{agent_list}}

### What Went Well
#### Requirements & Business (Mary)
[Points]

#### Process & Flow (Bob)
[Points]

#### Architecture & Design (Winston)
[Points]

#### Implementation & Code (Amelia)
[Points]

### Areas for Improvement
#### Requirements & Business (Mary)
[Points]

#### Process & Flow (Bob)
[Points]

#### Architecture & Design (Winston)
[Points]

#### Implementation & Code (Amelia)
[Points]

### Patterns Established
| Pattern | Description | Files |
|---------|-------------|-------|
| [Name]  | [What]      | [Where] |

### Key Decisions Log
| Decision | Rationale | Impact |
|----------|-----------|--------|
| [What]   | [Why]     | [Effect] |

### Gotchas & Lessons Learned
1. [Gotcha]: [What to watch for]
2. [Lesson]: [What we learned]

### Context Handoff for Next Epic
[Rich summary for epic-chain context transfer]
```

## Integration with Epic-Chain

When `generate_handoff: true`, output is also saved to:
`docs/handoffs/epic-{{epic_id}}-handoff.md`

This file is automatically loaded by epic-chain for the next epic.

## Success Criteria (Retrospective)

- All agents contributed reflections
- Actionable improvements identified
- Patterns documented for reuse
- Context handoff generated (if configured)
```

---

## 5. Shell Script Modifications

### File: `scripts/epic-execute.sh`

#### 5.1 New Variables

```bash
# Party Mode Flags
PARTY_KICKOFF=false
PARTY_REVIEW=false
PARTY_FAILURE=false
PARTY_RETRO=false
PARTY_AGENTS=""

# Party Mode Step Files
PARTY_KICKOFF_STEP="$BMAD_DIR/workflows/4-implementation/epic-execute/steps/step-01b-party-kickoff.md"
PARTY_REVIEW_STEP="$BMAD_DIR/workflows/4-implementation/epic-execute/steps/step-03b-party-review.md"
PARTY_FAILURE_STEP="$BMAD_DIR/workflows/4-implementation/epic-execute/steps/step-02b-party-failure.md"
PARTY_RETRO_STEP="$BMAD_DIR/workflows/4-implementation/epic-execute/steps/step-05b-party-retro.md"
```

### 5.2 Argument Parsing Additions

```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        # ... existing flags ...

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
        # ... rest of cases ...
    esac
done
```

#### 5.3 New Functions

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
$agents

## Story to Discuss
<story>
$story_contents
</story>

## Your Task
Facilitate a focused discussion between the agents about this story.
Each agent should contribute from their expertise:
- Winston (Architect): Architectural implications, integration points
- Amelia (Developer): Implementation approach, patterns to follow
- Murat (Test Architect): Testing strategy, edge cases

## Output
Generate a Story Kickoff Insights section to append to the story file.
Format as markdown with clear sections for each agent's input.

When complete, output: KICKOFF COMPLETE: $story_id"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party kickoff for $story_id"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$kickoff_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "KICKOFF COMPLETE"; then
        log_success "Party kickoff complete: $story_id"
        return 0
    else
        log_warn "Party kickoff may not have completed cleanly"
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
$agents

## Story Being Reviewed
<story>
$story_contents
</story>

## Review Focus Areas
- Winston (Architecture): Pattern adherence, scalability, API design
- Murat (Quality): Test coverage, security, edge cases
- Amelia (Implementation): Code quality, readability, maintainability

## Your Task
1. Run: git diff --staged
2. Each agent reviews from their perspective
3. Categorize issues by severity (HIGH/MEDIUM/LOW)
4. Facilitate cross-discussion to reach consensus
5. Apply fix policy: HIGH always, MEDIUM if >5 total, LOW document only
6. Generate Party Review Record

## Completion
If PASSED: Update story Status to Done, output: PARTY REVIEW PASSED: $story_id
If FAILED: Update story Status to Blocked, output: PARTY REVIEW FAILED: $story_id - [reason]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party review for $story_id"
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
        return 1
    else
        log_warn "Party review did not complete cleanly"
        return 1
    fi
}

execute_party_failure_analysis() {
    local story_file="$1"
    local story_id=$(basename "$story_file" .md)
    local failure_type="$2"  # "dev" or "review"

    log ">>> PARTY FAILURE ANALYSIS: $story_id"

    local story_contents=$(cat "$story_file")
    local agents="${PARTY_AGENTS:-Winston,Amelia,Bob}"

    local failure_prompt="You are orchestrating a Failure Analysis Party for BMAD.

## Participating Agents
$agents

## Failed Story
<story>
$story_contents
</story>

## Failure Type
$failure_type phase failed

## Your Task
1. Present failure context to agents
2. Facilitate root cause analysis:
   - Winston: Architectural issues?
   - Amelia: Implementation issues?
   - Bob: Requirements/process issues?
3. Build remediation plan
4. Recommend action: Retry | Skip | Escalate

## Output
Generate Failure Analysis Record.
Output: ANALYSIS COMPLETE: $story_id - [Retry|Skip|Escalate]"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute failure analysis for $story_id"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$failure_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"
    log_success "Failure analysis complete: $story_id"
}

execute_party_retro() {
    log ">>> PARTY RETROSPECTIVE: Epic $EPIC_ID"

    local epic_contents=$(cat "$EPIC_FILE")
    local agents="${PARTY_AGENTS:-Mary,Bob,Winston,Amelia}"

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
$agents

## Epic Completed
<epic>
$epic_contents
</epic>

## Completed Stories
$all_stories

## Your Task
Facilitate retrospective discussion:

1. What Went Well (each agent's perspective)
2. Areas for Improvement (each agent's perspective)
3. Patterns Established (document for reuse)
4. Key Decisions Log
5. Gotchas & Lessons Learned
6. Context Handoff for Next Epic

## Output
Generate retrospective document at: docs/sprints/epic-${EPIC_ID}-retro.md
Generate handoff document at: docs/handoffs/epic-${EPIC_ID}-handoff.md

When complete, output: RETRO COMPLETE: Epic $EPIC_ID"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute party retrospective"
        return 0
    fi

    local result
    result=$(claude --dangerously-skip-permissions -p "$retro_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "RETRO COMPLETE"; then
        log_success "Party retrospective complete"
    else
        log_warn "Retrospective may not have completed cleanly"
    fi
}
```

#### 5.4 Main Loop Modifications

```bash
# =============================================================================
# Main Execution Loop (Modified)
# =============================================================================

for story_file in "${STORIES[@]}"; do
    story_id=$(basename "$story_file" .md)

    # ... existing skip logic ...

    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Story: $story_id"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # PARTY KICKOFF (Optional - Context 0)
    if [ "$PARTY_KICKOFF" = true ]; then
        execute_party_kickoff "$story_file"
    fi

    # DEV PHASE (Context 1)
    if ! execute_dev_phase "$story_file"; then
        log_error "Dev phase failed for $story_id"

        # PARTY FAILURE ANALYSIS (Optional)
        if [ "$PARTY_FAILURE" = true ]; then
            execute_party_failure_analysis "$story_file" "dev"
        fi

        ((FAILED++))
        continue
    fi

    # REVIEW PHASE (Context 2 - Fresh)
    if [ "$SKIP_REVIEW" = false ]; then
        if [ "$PARTY_REVIEW" = true ]; then
            # Multi-agent party review
            if ! execute_party_review "$story_file"; then
                log_error "Party review failed for $story_id"

                if [ "$PARTY_FAILURE" = true ]; then
                    execute_party_failure_analysis "$story_file" "review"
                fi

                ((FAILED++))
                continue
            fi
        else
            # Standard single-agent review
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

# UAT Generation (Standard)
generate_uat

# PARTY RETROSPECTIVE (Optional)
if [ "$PARTY_RETRO" = true ]; then
    execute_party_retro
fi
```

---

## 6. File Structure After Implementation

```
src/modules/bmm/workflows/4-implementation/epic-execute/
├── workflow.md                          # Updated with party mode references
├── config/
│   └── default-config.yaml              # Updated with party section
├── steps/
│   ├── step-01-init.md                  # Existing
│   ├── step-01b-party-kickoff.md        # NEW: Story Kickoff Party
│   ├── step-02-dev-story.md             # Existing
│   ├── step-02b-party-failure.md        # NEW: Failure Analysis Party
│   ├── step-03-code-review.md           # Existing (used when party-review disabled)
│   ├── step-03b-party-review.md         # NEW: Multi-Agent Party Review
│   ├── step-04-generate-uat.md          # Existing
│   ├── step-05-summary.md               # Existing
│   └── step-05b-party-retro.md          # NEW: Post-Epic Retrospective Party
└── prompts/
    ├── kickoff-party.md                 # Full prompt template
    ├── review-party.md                  # Full prompt template
    ├── failure-party.md                 # Full prompt template
    └── retro-party.md                   # Full prompt template

scripts/
└── epic-execute.sh                      # Updated with party functions
```

---

## 7. Implementation Phases

### Phase 1: Foundation (Priority: High)
1. Add CLI flag parsing to `epic-execute.sh`
2. Add party section to `default-config.yaml`
3. Create `step-01b-party-kickoff.md`
4. Implement `execute_party_kickoff()` function
5. Wire kickoff into main loop

### Phase 2: Core Integration (Priority: High)
1. Create `step-03b-party-review.md`
2. Implement `execute_party_review()` function
3. Add conditional logic for party vs standard review
4. Test party review with sample epic

### Phase 3: Error Handling (Priority: Medium)
1. Create `step-02b-party-failure.md`
2. Implement `execute_party_failure_analysis()` function
3. Wire failure analysis into dev/review failure paths

### Phase 4: Retrospective & Handoff (Priority: Medium)
1. Create `step-05b-party-retro.md`
2. Implement `execute_party_retro()` function
3. Integrate with epic-chain context handoff system
4. Create handoff document templates

### Phase 5: Polish (Priority: Low)
1. Add `--party-agents` override support
2. Add TTS integration for party phases
3. Create comprehensive documentation
4. Add metrics tracking for party phases

---

## 8. Testing Strategy

### Unit Tests
- Flag parsing works correctly
- Config loading includes party section
- Agent list parsing handles various formats

### Integration Tests
```bash
# Test kickoff only
./epic-execute.sh test-epic --party-kickoff --dry-run

# Test full party mode
./epic-execute.sh test-epic --party-all --dry-run

# Test custom agents
./epic-execute.sh test-epic --party-review --party-agents "Winston,Murat" --dry-run
```

### Manual Validation
- Run with real epic to validate agent interactions
- Verify output document quality
- Confirm context isolation still works with party phases

---

## 9. Rollback Plan

Party mode is additive and opt-in:
- All flags default to `false`
- Standard workflow unchanged when flags not used
- Can disable individual party phases independently
- No changes to existing step files

---

## 10. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Issue detection rate | +25% | Compare issues found in party review vs standard |
| Architectural issues caught early | +40% | Track issues surfaced in kickoff |
| Context handoff quality | Subjective | Developer satisfaction with handoff docs |
| Failure remediation time | -30% | Time from failure to successful retry |

---

## 11. Future Enhancements

1. **Complexity-Based Auto-Trigger**: Automatically enable party phases for high-complexity stories
2. **Agent Recommendation Engine**: Suggest optimal agents based on story content
3. **Party Analytics**: Track which agent combinations produce best results
4. **Async Party Mode**: Run party phases in background while other work continues
5. **Human-in-Party**: Allow human to join party discussions at key decision points
