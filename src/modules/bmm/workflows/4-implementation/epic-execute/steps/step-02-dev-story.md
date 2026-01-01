# Step 2: Development Phase (Isolated Context)

## Context Isolation

**IMPORTANT**: This step executes in a fresh Claude context, separate from initialization and review phases. This ensures the dev agent has full context window for implementation without pollution from other phases.

## Objective

Implement a single story completely: code, tests, and documentation updates.

## Inputs

- `story_id`: The story to implement
- `story_file`: Path to story markdown file

## Prompt Template

This prompt is passed to an isolated Claude session:

```
You are the Dev agent executing a BMAD story implementation.

## Your Task

Implement story: {story_id}

## Story Specification

<story>
{story_file_contents}
</story>

## Reference Documents

Read these for context (do not load unless needed):
- Architecture: docs/architecture.md (or shards in docs/architecture/)
- PRD: docs/prd.md (or shards in docs/prd/)
- Related stories: {dependency_story_files}

## Implementation Requirements

1. **Read the story file completely** before writing any code

2. **Follow existing patterns**:
   - Check existing code in the directories you'll modify
   - Match naming conventions, file structure, code style
   - Use established patterns for similar functionality

3. **Implement all acceptance criteria**:
   - Each criterion must have corresponding code
   - Each criterion must have at least one test

4. **Write tests**:
   - Unit tests for new functions/methods
   - Integration tests for API endpoints
   - Follow existing test patterns in the codebase

5. **Run tests**:
   - Execute: `npm test` or appropriate test command
   - All tests must pass before completion
   - Fix any failures before proceeding

6. **Update documentation**:
   - Add JSDoc/docstrings to new code
   - Update README if adding new features/commands

## Completion Checklist

Before marking complete, verify:

- [ ] All acceptance criteria implemented
- [ ] Tests written and passing
- [ ] No linting errors
- [ ] Code follows existing patterns
- [ ] No hardcoded secrets or test data

## Update Story File

When implementation is complete, update the story file:

1. Change Status to: `In Review`

2. Fill in the Dev Agent Record section:

```markdown
## Dev Agent Record

### Implementation Summary
[Brief description of what was implemented]

### Files Created
- path/to/new/file.ts - [purpose]
- path/to/another/file.ts - [purpose]

### Files Modified  
- path/to/existing/file.ts - [what changed]

### Key Decisions
- [Any architectural or implementation decisions made]
- [Deviations from the story spec and why]

### Tests Added
- path/to/test.spec.ts - [what it tests]

### Notes for Reviewer
- [Anything the reviewer should pay attention to]
- [Areas of uncertainty]

### Test Results
[Summary of test run output]

### Acceptance Criteria Status
- [x] Criterion 1 - implemented in {file}
- [x] Criterion 2 - implemented in {file}
```

## Git Operations

Stage your changes (do NOT commit):

```bash
git add -A
```

## Completion Signal

When finished, output exactly:

```
IMPLEMENTATION COMPLETE: {story_id}
```

This signals the orchestration script to proceed to review phase.

## Error Handling

If you encounter a blocker you cannot resolve:

1. Document the blocker in the story file's Dev Agent Record
2. Stage any partial work
3. Output: `IMPLEMENTATION BLOCKED: {story_id} - {reason}`
```

## Orchestration Integration

The shell script captures this prompt and passes it to Claude:

```bash
claude -p "$(cat step-02-dev-story.md | envsubst)"
```

The `envsubst` replaces `{story_id}`, `{story_file_contents}`, etc. with actual values.

## Success Criteria

Phase complete when:

- All acceptance criteria have code
- All tests pass
- Changes are staged in git
- Story file updated with Dev Agent Record
- IMPLEMENTATION COMPLETE signal output
