# Epic Execute Launcher

This workflow requires **shell orchestration** for context isolation between dev and review phases.

## Instructions

When the user invokes `*epic-execute`, follow these steps:

### Step 1: Get Epic ID

Ask the user which epic to execute if not provided as an argument. Valid epic IDs can be found in `docs/epics/`.

### Step 2: Validate Prerequisites

Before running, verify:
1. Epic file exists at `docs/epics/epic-{id}-*.md`
2. Stories exist for the epic (check `docs/stories/` and `docs/sprint-artifacts/`)
3. Git working directory is clean (no uncommitted changes)

### Step 3: Provide the Command

Tell the user to run one of these commands:

**Dry run (recommended first):**
```bash
./.bmad/scripts/epic-execute.sh {epic_id} --dry-run --verbose
```

**Full execution:**
```bash
./.bmad/scripts/epic-execute.sh {epic_id}
```

**With verbose output:**
```bash
./.bmad/scripts/epic-execute.sh {epic_id} --verbose
```

### Step 4: Explain What Happens

The workflow will:
1. Find all stories for the epic
2. For each story:
   - **Dev Phase** (isolated context): Implement the story
   - **Review Phase** (fresh context): Code review the changes
   - **Commit**: Auto-commit if review passes
3. **UAT Generation**: Create human testing document at `docs/uat/epic-{id}-uat.md`

### Why Shell Orchestration?

Context isolation ensures:
- Reviewer sees code "cold" (like a real PR review)
- Each phase has full context window available
- No bias from seeing implementation struggles

State transfers via:
- Code changes → git staging
- Implementation notes → story file's Dev Agent Record
- Review findings → story file's Code Review Record
