# Context Management Deep Dive

**Document**: 02-context-management.md
**Version**: 1.0.0
**Date**: 2026-01-03

---

## Overview

This document explains how context isolation works in the epic-execute workflow and how Party Mode integration maintains this architecture while enabling multi-agent collaboration.

---

## Current Context Architecture

### The Shell as Orchestrator

The epic-execute workflow uses **shell orchestration** to create context isolation between phases. The shell script (`epic-execute.sh`) is the central coordinator that:

1. Reads story files from disk
2. Builds prompt strings with story contents embedded
3. Invokes Claude in isolated sessions
4. Captures output and parses for completion signals
5. Manages git staging between phases

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SHELL ORCHESTRATION MODEL                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  epic-execute.sh (Shell - The "Memory")                                  │
│  │                                                                       │
│  ├── Reads: story files, epic files, config                             │
│  ├── Writes: logs, status updates                                        │
│  ├── Manages: git staging area                                           │
│  │                                                                       │
│  └── For each phase:                                                     │
│      ├── Build prompt string (inject file contents)                     │
│      ├── Invoke: claude --dangerously-skip-permissions -p "$prompt"     │
│      ├── Capture stdout/stderr                                          │
│      ├── Parse for signals (COMPLETE, BLOCKED, PASSED, FAILED)          │
│      └── Decide next action based on result                             │
│                                                                          │
│  Each Claude invocation = FRESH CONTEXT (no conversation history)       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Context Isolation Matters

**Problem it solves**: Reviewer bias

If the reviewer (Context B) could see the developer's (Context A) struggles, dead-ends, and thought process, they would:
- Be biased toward the implementation approach taken
- Miss issues because they "understand" why shortcuts were made
- Not simulate a real code review where reviewers see code "cold"

**Solution**: Each phase runs in a completely fresh Claude session with no shared conversation history.

---

## Context Transfer Mechanisms

Since contexts are isolated, information must flow through **persistent storage**:

| Mechanism | What It Carries | Direction |
|-----------|-----------------|-----------|
| **Git staging** | Actual code changes | Dev → Review |
| **Story file** | Dev Agent Record, Code Review Record, Status | All phases |
| **Prompt injection** | Story contents, context, instructions | Shell → Claude |
| **Output parsing** | Success/failure signals | Claude → Shell |
| **Log file** | Full Claude responses (optional) | Claude → Disk |

### Transfer Flow Diagram

```
┌─────────────┐
│   Shell     │
│ Orchestrator│
└──────┬──────┘
       │
       │ 1. Read story file
       │ 2. Build prompt with contents
       │ 3. Invoke Claude
       ▼
┌─────────────┐
│  Context A  │
│   (Dev)     │
│             │
│ - Reads story from prompt
│ - Writes code
│ - Runs: git add -A
│ - Updates story file (Dev Agent Record)
│ - Outputs: IMPLEMENTATION COMPLETE
│             │
└──────┬──────┘
       │
       │ ┌─────────────────────────────────┐
       │ │ Transfer via:                   │
       │ │ - Git staging (code)            │
       │ │ - Story file (Dev Agent Record) │
       │ └─────────────────────────────────┘
       │
       │ 4. Shell reads story file again
       │ 5. Builds new prompt
       │ 6. Invokes NEW Claude session
       ▼
┌─────────────┐
│  Context B  │
│  (Review)   │
│             │
│ - Reads story from prompt (includes Dev Agent Record)
│ - Runs: git diff --staged (sees code)
│ - Has NO memory of dev phase
│ - Reviews "cold"
│ - Updates story file (Code Review Record)
│ - Outputs: REVIEW PASSED/FAILED
│             │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Shell     │
│  (Commit)   │
│             │
│ git commit -m "..."
└─────────────┘
```

---

## How Party Mode Extends This

Party Mode adds **additional isolated contexts** at specific workflow points without breaking the isolation model.

### Enhanced Context Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ENHANCED CONTEXT FLOW                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  epic-execute.sh (Shell - Orchestrator)                                  │
│                                                                          │
│  Per Story:                                                              │
│  ┌─────────────┐                                                        │
│  │ CONTEXT 0   │ ← NEW: Party Kickoff (--party-kickoff)                │
│  │ (Kickoff)   │                                                        │
│  │             │   Input: Story file                                    │
│  │             │   Output: Insights → APPENDED to story file            │
│  │             │   Signal: KICKOFF COMPLETE                             │
│  └──────┬──────┘                                                        │
│         │                                                                │
│         │ Transfer: Story file now contains Kickoff Insights section    │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────┐                                                        │
│  │ CONTEXT A   │ ← EXISTING: Dev phase                                  │
│  │ (Dev)       │                                                        │
│  │             │   Input: Story file (NOW includes kickoff insights)    │
│  │             │   Output: Code staged, Dev Agent Record                │
│  │             │   Signal: IMPLEMENTATION COMPLETE/BLOCKED              │
│  └──────┬──────┘                                                        │
│         │                                                                │
│         │ Transfer: Git staging + Story file updated                    │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────┐                                                        │
│  │ CONTEXT B   │ ← MODIFIED: Standard review OR Party Review           │
│  │ (Review)    │                                                        │
│  │             │   Input: Story file + git diff --staged                │
│  │             │   Output: Code Review Record, fixes staged             │
│  │             │   Signal: REVIEW PASSED/FAILED                         │
│  └──────┬──────┘                                                        │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────┐                                                        │
│  │ Shell       │ ← EXISTING: Commit                                     │
│  │ (Commit)    │   git commit                                           │
│  └─────────────┘                                                        │
│                                                                          │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ FAILURE PATH ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─              │
│                                                                          │
│  If Dev or Review outputs BLOCKED/FAILED:                                │
│  ┌─────────────┐                                                        │
│  │ CONTEXT F   │ ← NEW: Failure Analysis (--party-failure)             │
│  │ (Failure)   │                                                        │
│  │             │   Input: Story file + failure message                  │
│  │             │   Output: Analysis Record → appended to story          │
│  │             │   Signal: ANALYSIS COMPLETE + recommendation           │
│  └─────────────┘                                                        │
│                                                                          │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ POST-EPIC ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─               │
│                                                                          │
│  After all stories:                                                      │
│  ┌─────────────┐                                                        │
│  │ CONTEXT C   │ ← EXISTING: UAT Generation                             │
│  │ (UAT)       │                                                        │
│  └─────────────┘                                                        │
│                                                                          │
│  ┌─────────────┐                                                        │
│  │ CONTEXT R   │ ← NEW: Party Retrospective (--party-retro)            │
│  │ (Retro)     │                                                        │
│  │             │   Input: ALL story files + epic file (read-only)       │
│  │             │   Output: Retro doc + handoff doc (new files)          │
│  │             │   Signal: RETRO COMPLETE                               │
│  └─────────────┘                                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Transfer Specifications

### A. Kickoff → Dev Transfer

**What gets transferred**: Kickoff Insights (architectural notes, implementation strategy, testing approach, identified risks)

**Transfer mechanism**: Kickoff context appends a new section to the story file

```markdown
## Story Kickoff Insights

**Discussion Date**: 2026-01-03
**Participants**: Winston (Architect), Amelia (Developer), Murat (Test Architect)

### Architectural Notes
- Consider using existing auth middleware pattern from lib/auth/
- Integration point: /api/v1/users endpoint
- Watch for rate limiting constraints on external API

### Implementation Strategy
- Extend UserService class rather than creating new
- Reuse validation utilities from lib/validators
- Follow repository pattern established in src/repositories/

### Testing Approach
- Unit tests for service methods (Jest)
- Integration test for full user flow
- Mock external API calls using existing fixtures

### Identified Risks
- Rate limiting not yet implemented for external API
- Database migration needed for new user fields
```

**Dev context sees**: Story file with the above section included. The prompt says "Read the story file completely before writing any code" - so dev agent has access to kickoff insights.

**Why this works**: Dev agent can leverage the multi-agent discussion without those agents being in its context window.

---

### B. Dev → Review Transfer (Unchanged)

**What gets transferred**:
1. Code changes (via git staging)
2. Dev Agent Record (via story file)

**Transfer mechanism**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Dev Context writes:                                                      │
│                                                                          │
│ 1. Code files → git add -A (staged, not committed)                      │
│                                                                          │
│ 2. Story file updated with:                                              │
│    ## Dev Agent Record                                                   │
│                                                                          │
│    ### Implementation Summary                                            │
│    Added user registration endpoint with email verification              │
│                                                                          │
│    ### Files Created                                                     │
│    - src/services/UserService.ts - User registration logic              │
│    - src/routes/users.ts - REST endpoints                                │
│                                                                          │
│    ### Files Modified                                                    │
│    - src/app.ts - Added user routes                                      │
│                                                                          │
│    ### Key Decisions                                                     │
│    - Used bcrypt for password hashing (industry standard)               │
│    - Async email verification (non-blocking)                            │
│                                                                          │
│    ### Tests Added                                                       │
│    - test/services/UserService.test.ts                                   │
│                                                                          │
│    ### Notes for Reviewer                                                │
│    - Email templates need design review                                  │
│    - Rate limiting deferred to next story                                │
│                                                                          │
│ 3. Outputs: IMPLEMENTATION COMPLETE: story-42-1                          │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Review Context receives (via prompt injection):                          │
│                                                                          │
│ 1. Story file contents (includes Dev Agent Record)                       │
│ 2. Instructions to run: git diff --staged                               │
│                                                                          │
│ Review Context has NO knowledge of:                                      │
│ - Dead-ends the dev tried                                               │
│ - Time spent debugging                                                   │
│ - Alternative approaches considered                                      │
│ - Frustrations or workarounds                                           │
│                                                                          │
│ This is intentional - reviewer sees code "cold"                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### C. Party Review vs Standard Review

The difference is in **prompt content**, not transfer mechanism.

**Standard Review Prompt** (current):
```
You are a Senior Code Reviewer performing a BMAD code review.

## Your Task
Review the implementation of story: {story_id}
You are seeing this code for the first time...
```

**Party Review Prompt** (new):
```
You are orchestrating a Party Code Review with multiple BMAD agents.

## Participating Agents

### Winston (Architect)
- Focus: Pattern adherence, scalability, API design consistency
- Communication style: Calm, pragmatic, balances "what could be" with "what should be"

### Murat (Test Architect)
- Focus: Test coverage, security vulnerabilities, edge cases
- Communication style: Data-driven, "strong opinions weakly held", risk calculations

### Amelia (Developer)
- Focus: Code quality, readability, maintainability, error handling
- Communication style: [from agent definition]

## Your Task

1. Run: git diff --staged
2. For each agent, generate their review perspective in character
3. Facilitate cross-discussion where agents reference each other
4. Build consensus on issues and fixes
5. Apply the same severity-based fix policy
6. Generate unified Party Review Record

## Output Format

Each agent reviews, then they discuss:

🏗️ **Winston**: "Looking at the architecture, I see..."

🧪 **Murat**: "From a testing perspective, Winston raises a good point about..."

💻 **Amelia**: "I agree with Murat on test coverage. Additionally..."

### Consensus
[Unified findings after discussion]
```

**Same inputs**: Story file + git diff
**Same outputs**: Code Review Record in story file, PASSED/FAILED signal
**Different process**: Multi-perspective analysis within the prompt

---

### D. Failure Analysis Context

**Trigger**: Dev or Review outputs BLOCKED/FAILED signal

**What gets transferred**:
1. Story file (current state, may have partial Dev Agent Record)
2. Failure type ("dev" or "review")
3. Failure message extracted from output

```bash
# In shell script
if echo "$result" | grep -q "IMPLEMENTATION BLOCKED"; then
    # Extract failure reason
    failure_msg=$(echo "$result" | grep "IMPLEMENTATION BLOCKED" | sed 's/.*BLOCKED: [^ ]* - //')

    if [ "$PARTY_FAILURE" = true ]; then
        execute_party_failure_analysis "$story_file" "dev" "$failure_msg"
    fi
fi
```

**Failure Analysis Context receives**:
```
## Failed Story
<story>
{story_file_contents}
</story>

## Failure Information
- **Type**: dev phase
- **Signal**: IMPLEMENTATION BLOCKED
- **Message**: "Cannot resolve circular dependency between UserService and AuthService"

## Participating Agents
- Winston (Architect): Assess if this is an architectural issue
- Amelia (Developer): Assess if this is an implementation issue
- Bob (Scrum Master): Assess if this is a requirements/process issue
```

**Output**: Failure Analysis Record appended to story + recommendation (Retry | Skip | Escalate)

---

### E. Retrospective Context (Post-Epic)

**Trigger**: All stories completed (or `--party-retro` flag with completed epic)

**What gets transferred** (read-only, aggregated):

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Retro Context receives:                                                  │
│                                                                          │
│ 1. Epic file                                                             │
│    - Epic description, goals, scope                                     │
│                                                                          │
│ 2. ALL story files, each containing:                                     │
│    - Original specification                                              │
│    - Kickoff Insights (if --party-kickoff was used)                     │
│    - Dev Agent Record                                                    │
│    - Code Review Record (standard or party)                              │
│    - Failure Analysis Record (if any failures occurred)                 │
│                                                                          │
│ 3. Execution summary                                                     │
│    - Stories completed: 8                                                │
│    - Stories failed: 1                                                   │
│    - Total duration: 45 minutes                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Output** (creates new files):

```
docs/sprints/epic-42-retro.md      # Retrospective insights
docs/handoffs/epic-42-handoff.md   # Context for next epic (used by epic-chain)
```

---

## Context Window Considerations

### Current Approach: Prompt Injection

Each context receives its input via prompt injection - the shell script reads files and embeds their contents in the prompt string:

```bash
local story_contents=$(cat "$story_file")

local dev_prompt="You are the Dev agent...

## Story Specification

<story>
$story_contents
</story>

## Implementation Requirements
..."
```

**Advantage**: Full control over what each context sees
**Limitation**: Large stories or many files can consume significant context window

### Party Mode Implications

Party phases add context window usage:

| Phase | Additional Context Load |
|-------|------------------------|
| Kickoff | Agent personas (~500 tokens) + discussion instructions |
| Party Review | 3x agent personas + cross-talk instructions |
| Failure Analysis | Agent personas + failure context |
| Retrospective | ALL story files aggregated (potentially large) |

**Mitigation strategies**:

1. **Selective loading**: Only include relevant agent personas, not full manifests
2. **Summary injection**: For retro, summarize stories rather than full contents
3. **Timeout configuration**: Allow configuration of max tokens per phase

---

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA FLOW SUMMARY                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  PERSISTENT STORAGE (survives across contexts)                          │
│  ├── Story files (.md)                                                   │
│  │   ├── Original spec                                                   │
│  │   ├── Kickoff Insights (written by Context 0)                        │
│  │   ├── Dev Agent Record (written by Context A)                        │
│  │   ├── Code Review Record (written by Context B)                      │
│  │   └── Failure Analysis Record (written by Context F)                 │
│  │                                                                       │
│  ├── Git staging area                                                    │
│  │   └── Code changes (written by Context A, read by Context B)         │
│  │                                                                       │
│  ├── Git commits                                                         │
│  │   └── Committed code (written by Shell after Context B passes)       │
│  │                                                                       │
│  └── Output files                                                        │
│      ├── docs/uat/epic-{id}-uat.md (written by Context C)               │
│      ├── docs/sprints/epic-{id}-retro.md (written by Context R)         │
│      └── docs/handoffs/epic-{id}-handoff.md (written by Context R)      │
│                                                                          │
│  EPHEMERAL (exists only during context execution)                       │
│  ├── Conversation history (per context, not shared)                     │
│  ├── Tool call results (per context)                                    │
│  └── Working memory (per context)                                       │
│                                                                          │
│  SHELL VARIABLES (orchestrator state)                                    │
│  ├── STORIES array                                                       │
│  ├── COMPLETED/FAILED counters                                          │
│  ├── Flag states (PARTY_KICKOFF, etc.)                                  │
│  └── Current story pointer                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Design Principles

### 1. File System as the Bridge

All context transfer happens via the file system. This is intentional:
- Git staging for code
- Markdown files for documentation/records
- No shared memory or conversation history

### 2. Append-Only Story Files

Each phase appends to the story file rather than replacing. This creates an audit trail:
```
Story File
├── Original Spec (created during planning)
├── Kickoff Insights (appended by kickoff party)
├── Dev Agent Record (appended by dev phase)
├── Code Review Record (appended by review phase)
└── Failure Analysis (appended if failure occurred)
```

### 3. Signals for Flow Control

Each context outputs a specific signal that the shell parses:
- `KICKOFF COMPLETE: story-id`
- `IMPLEMENTATION COMPLETE: story-id`
- `IMPLEMENTATION BLOCKED: story-id - reason`
- `REVIEW PASSED: story-id`
- `REVIEW PASSED WITH FIXES: story-id - Fixed N issues`
- `REVIEW FAILED: story-id - reason`
- `ANALYSIS COMPLETE: story-id - Retry|Skip|Escalate`
- `RETRO COMPLETE: Epic epic-id`

### 4. Non-Blocking Optional Phases

Party phases are designed to be non-blocking:
- Kickoff failure → Continue to dev (insights are helpful but not required)
- Failure analysis → Informational (doesn't change retry/skip decision)
- Retro failure → Log warning, epic still considered complete

---

## Testing Context Isolation

To verify context isolation is maintained:

```bash
# Test 1: Verify dev context doesn't see review instructions
./epic-execute.sh test-epic --dry-run --verbose 2>&1 | grep -A 50 "DEV PHASE"
# Should NOT contain "Code Review" or "severity" language

# Test 2: Verify review context doesn't see dev struggles
./epic-execute.sh test-epic --dry-run --verbose 2>&1 | grep -A 50 "REVIEW PHASE"
# Should contain "You are seeing this code for the first time"

# Test 3: Verify party kickoff writes to story file
./epic-execute.sh test-epic --party-kickoff --dry-run
cat docs/stories/test-story.md | grep "Story Kickoff Insights"
# Should find the section
```
