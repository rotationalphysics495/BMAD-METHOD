# Epic Execute Workflow

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0.0 |
| Trigger | `epic-execute` |
| Agent | SM (Scrum Master) |
| Category | Implementation |
| Complexity | High |

## Purpose

Automatically execute all stories in an epic sequentially with context isolation between development and review phases, then generate a User Acceptance Testing document for human validation.

## Prerequisites

- Epic file exists with defined stories
- Story files created (at minimum: title, acceptance criteria, technical context)
- Architecture document available for reference
- Git repository initialized

## Workflow Phases

This workflow orchestrates multiple isolated agent sessions:

```
┌─────────────────────────────────────────────────────────────┐
│                     EPIC EXECUTE FLOW                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Phase 1   │    │   Phase 2   │    │   Phase 3   │     │
│  │   Dev       │───►│   Review    │───►│   Commit    │     │
│  │  (Context A)│    │ (Context B) │    │  (Shell)    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                                     │              │
│         └──────────── Per Story Loop ─────────┘              │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    Phase 4                           │    │
│  │              UAT Generation (Context C)              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Steps

| Step | File | Description |
|------|------|-------------|
| 1 | step-01-init.md | Discover epic and validate stories |
| 2 | step-02-dev-story.md | Development phase prompt (isolated context) |
| 3 | step-03-code-review.md | Review phase prompt (isolated context) |
| 4 | step-04-generate-uat.md | UAT document generation (isolated context) |
| 5 | step-05-summary.md | Final execution summary |

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Updated Stories | `docs/stories/` | Stories marked Done with Dev Agent Records and Code Review Records |
| UAT Document | `docs/uat/epic-{id}-uat.md` | Human testing script |
| Execution Log | `docs/sprints/epic-{id}-execution.md` | Run summary |

## Issue Fix Policy

During code review, issues are categorized by severity and fixed based on thresholds:

| Severity | Criteria | Action |
|----------|----------|--------|
| **HIGH** | Security, missing error handling, no tests, exposed secrets | Always fix |
| **MEDIUM** | Pattern violations, missing edge cases, hardcoded config | Fix if total issues > 5 |
| **LOW** | Naming, style, missing comments | Document only |

This ensures critical issues are always resolved while avoiding over-engineering on minor items.

## Orchestration Script

This workflow requires shell orchestration to clear context between phases.
See: `scripts/epic-execute.sh`

## Usage

```bash
# From project root
./bmad/scripts/epic-execute.sh <epic-id>

# Example
./bmad/scripts/epic-execute.sh 1
```

Or invoke steps manually:

```
/sm
*epic-execute 1
```

When invoked via agent, SM will guide through setup then provide the shell command.

## Configuration

Optional settings in `bmad/_cfg/epic-execute.yaml`:

```yaml
# Auto-commit after each story (default: true)
auto_commit: true

# Run tests before review (default: true)  
run_tests_before_review: true

# Generate handoff notes between phases (default: true)
generate_handoffs: true

# Parallel story execution for independent stories (default: false)
parallel_execution: false

# Review strictness: lenient | standard | strict
review_mode: standard
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Dev fails to complete | Log failure, skip to next story, mark blocked |
| Review finds critical issues | Attempt fix, re-review once, then flag for human |
| Tests fail | Attempt fix, re-run, fail after 3 attempts |
| Story dependency not met | Skip story, continue, report in summary |

## Notes

- Each phase runs in isolated Claude context for clean separation
- Git staging passes code between contexts (not context window)
- Story files pass notes between contexts (Dev Agent Record section)
- Human intervention only required at UAT testing phase
