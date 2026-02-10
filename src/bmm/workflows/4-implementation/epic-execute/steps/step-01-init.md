# Step 1: Initialize Epic Execution

## Objective

Validate the epic exists, discover all associated stories, verify prerequisites, and prepare the execution plan.

## Inputs

- `epic_id`: The epic identifier (e.g., "1", "auth", "epic-1")

## Actions

### 1.1 Locate Epic File

Search for the epic definition:

```
docs/epics/epic-{epic_id}.md
docs/epics/{epic_id}.md
docs/epics/epic-{epic_id}*.md
```

**If not found**: Stop and report. Cannot proceed without epic definition.

### 1.2 Parse Epic Metadata

Extract from epic file:

- Epic title/name
- Epic goal/description
- Success criteria (if defined)
- Story references

### 1.3 Discover Stories

Find all stories belonging to this epic:

```bash
# Stories reference epic in frontmatter or body
grep -l "Epic: {epic_id}\|epic-{epic_id}" docs/stories/*.md
```

Or parse story naming convention:
```
docs/stories/story-{epic_id}.1-*.md
docs/stories/story-{epic_id}.2-*.md
```

### 1.4 Validate Story Readiness

For each discovered story, verify:

| Check | Required |
|-------|----------|
| Status is `Ready` or `Draft` | Yes |
| Acceptance criteria defined | Yes |
| Technical context present | Recommended |
| File paths identified | Recommended |
| Dependencies listed | If applicable |

### 1.5 Resolve Dependencies

Build execution order:

1. Parse `Dependencies` section of each story
2. Topological sort to determine order
3. Flag circular dependencies as blockers

### 1.6 Generate Execution Plan

Create `docs/handoff/epic-{epic_id}-plan.md`:

```markdown
# Epic {epic_id} Execution Plan

**Generated**: {timestamp}
**Stories**: {count}
**Estimated Phases**: {count * 2} (dev + review per story)

## Execution Order

| Order | Story | Dependencies | Status |
|-------|-------|--------------|--------|
| 1 | story-1.1 | None | Ready |
| 2 | story-1.2 | story-1.1 | Ready |
| 3 | story-1.3 | story-1.1 | Ready |
| 4 | story-1.4 | story-1.2, story-1.3 | Ready |

## Prerequisites Check

- [ ] Architecture doc available
- [ ] Test framework configured
- [ ] Git working tree clean

## Ready to Execute

Run: `./bmad/scripts/epic-execute.sh {epic_id}`
```

## Outputs

- Execution plan document
- Ordered list of story IDs for shell script
- Any blockers identified

## Next Step

If all validations pass, provide user with shell command to begin execution.

**Transition**: User runs `./bmad/scripts/epic-execute.sh {epic_id}`

## Error States

| Error | Resolution |
|-------|------------|
| Epic not found | Ask user for correct epic ID or path |
| No stories found | Verify story naming convention, check epic references |
| Stories not Ready | List stories needing prep, offer to run story creation |
| Circular dependency | Display cycle, ask user to resolve |
