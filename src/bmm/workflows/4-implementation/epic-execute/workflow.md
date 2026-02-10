# Epic Execute Workflow

## Metadata

| Field | Value |
|-------|-------|
| Version | 2.0.0 |
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

This workflow orchestrates multiple isolated agent sessions with comprehensive quality gates:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ENHANCED EPIC EXECUTE FLOW (v2.0)                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────────┐    │
│  │  Dev     │→ │ Arch         │→ │ Code     │→ │ Test Quality │    │
│  │ (impl)   │  │ Compliance   │  │ Review   │  │ Review       │    │
│  └──────────┘  └──────────────┘  └──────────┘  └──────────────┘    │
│       │              │                │               │             │
│       └──────────────┴────────────────┴───────────────┘             │
│                              │                                       │
│               ─── Per Story Loop (with fix loops) ───               │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Traceability Check                         │  │
│  │              (Per-Epic, with self-healing)                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    UAT Generation                             │  │
│  │                    (Fresh Context)                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Steps

### Per-Story Steps

| Step | File | Description |
|------|------|-------------|
| 1 | step-01-init.md | Discover epic and validate stories |
| 2 | step-02-dev-story.md | Development phase (isolated context) |
| 2b | step-02b-arch-compliance.md | Architecture compliance check |
| 3 | step-03-code-review.md | Code review phase (isolated context) |
| 3b | step-03b-test-quality.md | Test quality review |

### Per-Epic Steps

| Step | File | Description |
|------|------|-------------|
| 3c | step-03c-traceability.md | Requirements traceability with self-healing |
| 4 | step-04-generate-uat.md | UAT document generation (isolated context) |
| 5 | step-05-summary.md | Final execution summary |

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Updated Stories | `docs/stories/` | Stories with Dev Agent Records, Code Review Records, Test Quality summaries |
| Traceability Matrix | `docs/sprint-artifacts/traceability/epic-{id}-traceability.md` | Requirements-to-tests mapping |
| UAT Document | `docs/uat/epic-{id}-uat.md` | Human testing script |
| Execution Metrics | `docs/sprint-artifacts/metrics/epic-{id}-metrics.yaml` | Run metrics including fix loop data |
| Execution Log | `docs/sprints/epic-{id}-execution.md` | Run summary |

## Quality Gates

### Architecture Compliance (Per-Story)

Validates implementation against `architecture.md`:

| Category | What It Catches | Severity |
|----------|-----------------|----------|
| Layer violations | Business logic in UI, DB calls from controllers | HIGH |
| Dependency direction | Circular deps, wrong import directions | HIGH |
| Pattern conformance | Deviating from established patterns | MEDIUM |
| Module boundaries | Features leaking across modules | MEDIUM |

### Code Review Issue Fix Policy

| Severity | Criteria | Action |
|----------|----------|--------|
| **HIGH** | Security, missing error handling, no tests, exposed secrets | Always fix |
| **MEDIUM** | Pattern violations, missing edge cases, hardcoded config | Fix if total issues > 5 |
| **LOW** | Naming, style, missing comments | Document only |

### Test Quality Review (Per-Story)

Validates tests against testarch best practices:

| Criterion | What It Catches |
|-----------|-----------------|
| Hard waits | Flaky `sleep()`, `waitForTimeout()` calls |
| Missing assertions | Tests that pass without checking anything |
| Shared state | Tests that depend on execution order |
| Hardcoded data | Magic strings instead of factories |
| Network races | Route interception after navigation |

Quality score 0-100 with grade. Issues fixed automatically when critical/high.

### Requirements Traceability (Per-Epic)

Maps acceptance criteria to tests with coverage thresholds:

| Priority | Required Coverage | Gate Impact |
|----------|-------------------|-------------|
| P0 (Critical) | 100% | FAIL if not met |
| P1 (High) | ≥90% | CONCERNS if 80-89% |
| P2 (Medium) | ≥80% | Advisory |
| P3 (Low) | None | Advisory |

Self-healing: Automatically generates missing tests (up to 3 attempts).

## Orchestration Script

This workflow requires shell orchestration to clear context between phases.
See: `scripts/epic-execute.sh`

## Usage

```bash
# From project root
./bmad/scripts/epic-execute.sh <epic-id>

# Example
./bmad/scripts/epic-execute.sh 1

# Skip optional quality gates (not recommended)
./bmad/scripts/epic-execute.sh 1 --skip-arch
./bmad/scripts/epic-execute.sh 1 --skip-test-quality
./bmad/scripts/epic-execute.sh 1 --skip-traceability
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
| Arch violations found | Attempt fix (2 max), proceed with documented violations |
| Review finds critical issues | Attempt fix (3 max), re-review, then fail story |
| Test quality issues | Attempt fix (2 max), proceed with CONCERNS status |
| Traceability gaps | Generate missing tests (3 max), proceed with gaps documented |
| Story dependency not met | Skip story, continue, report in summary |

## Notes

- Each phase runs in isolated Claude context for clean separation
- Git staging passes code between contexts (not context window)
- Story files pass notes between contexts (Dev Agent Record section)
- Human intervention only required at UAT testing phase
- Quality gates are non-blocking by default (issues documented, not fatal)
- Self-healing loops automatically fix issues when possible
- Traceability matrix provides audit trail for compliance requirements
