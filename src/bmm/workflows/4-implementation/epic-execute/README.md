# BMAD Epic Execute Workflow

Automated story execution with context isolation and UAT generation.

## What It Does

```
┌─────────────────────────────────────────────────────────────┐
│                         Epic                                 │
│                           │                                  │
│     ┌─────────────────────┼─────────────────────┐           │
│     │                     │                     │           │
│     ▼                     ▼                     ▼           │
│ ┌───────┐           ┌───────┐            ┌───────┐         │
│ │Story 1│           │Story 2│            │Story N│         │
│ └───┬───┘           └───┬───┘            └───┬───┘         │
│     │                   │                    │              │
│     ▼                   ▼                    ▼              │
│ ┌───────────┐      ┌───────────┐       ┌───────────┐       │
│ │  Dev      │      │  Dev      │       │  Dev      │       │
│ │ Context A │      │ Context C │       │ Context E │       │
│ └─────┬─────┘      └─────┬─────┘       └─────┬─────┘       │
│       │ git staged       │ git staged       │ git staged   │
│       ▼                  ▼                  ▼              │
│ ┌───────────┐      ┌───────────┐       ┌───────────┐       │
│ │  Review   │      │  Review   │       │  Review   │       │
│ │ Context B │      │ Context D │       │ Context F │       │
│ └─────┬─────┘      └─────┬─────┘       └─────┬─────┘       │
│       │ commit           │ commit           │ commit       │
│       ▼                  ▼                  ▼              │
│     ┌─────────────────────────────────────────┐            │
│     │          UAT Generation                  │            │
│     │           (Context G)                    │            │
│     └──────────────────┬──────────────────────┘            │
│                        │                                    │
│                        ▼                                    │
│              ┌─────────────────┐                           │
│              │  UAT Document   │                           │
│              │  (For Humans)   │                           │
│              └─────────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## Key Features

- **Context Isolation**: Dev and Review phases run in separate Claude sessions
- **Clean Reviews**: Reviewer sees only the diff and story file, not the implementation journey
- **Severity-Based Fixes**: HIGH always fixed, MEDIUM fixed if >5 total issues, LOW documented only
- **Automated Commits**: Each story committed after passing review
- **UAT Generation**: Human-readable test script produced automatically
- **Story File as Single Source**: Dev Agent Record and Code Review Record live in the story file

## Quick Start

```bash
# Execute all stories in epic 1
./bmad/scripts/epic-execute.sh 1
```

## Files

```
epic-execute/
├── workflow.md              # Main workflow definition
├── INSTALLATION.md          # Setup guide
├── config/
│   └── default-config.yaml  # Configuration options
├── steps/
│   ├── step-01-init.md      # Discover epic and stories
│   ├── step-02-dev-story.md # Development phase prompt
│   ├── step-03-code-review.md # Review phase prompt
│   ├── step-04-generate-uat.md # UAT generation prompt
│   └── step-05-summary.md   # Execution report
└── templates/
    └── uat-template.md      # UAT document template
```

## Why Context Isolation?

Without isolation:
- Review phase "knows" about implementation struggles
- Reviewer is biased by seeing the journey
- Context window fills with debugging noise

With isolation:
- Reviewer sees the code cold (like a real PR review)
- Each phase has full context window available
- State passes via git staging and story file updates

**How state transfers:**
- Code changes → git staging
- Implementation notes → story file's Dev Agent Record
- Review findings → story file's Code Review Record
- Story status → Status field in story file

## Output

| Artifact | Location |
|----------|----------|
| Completed Stories | `docs/stories/*.md` (with Dev Agent Record + Code Review Record) |
| UAT Document | `docs/uat/epic-{id}-uat.md` |
| Execution Log | `docs/sprints/epic-{id}-execution.md` |

## Issue Fix Policy

| Severity | Examples | Action |
|----------|----------|--------|
| HIGH | Security issues, no tests, missing error handling | Always fix |
| MEDIUM | Pattern violations, missing edge cases | Fix if total issues > 5 |
| LOW | Naming, style, comments | Document only |

## Requirements

- BMAD v6
- Claude Code CLI
- Git

## See Also

- [Installation Guide](./INSTALLATION.md)
- [Workflow Definition](./workflow.md)
- [Configuration Options](./config/default-config.yaml)
