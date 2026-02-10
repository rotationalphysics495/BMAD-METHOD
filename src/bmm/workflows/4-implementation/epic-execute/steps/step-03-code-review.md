# Step 3: Code Review Phase (Isolated Context)

## Context Isolation

**IMPORTANT**: This step executes in a completely fresh Claude context. The reviewer has no knowledge of the implementation journey—only the final diff, story spec, and Dev Agent Record. This simulates a real code review where the reviewer sees the PR cold.

## Objective

Review the staged changes with fresh eyes, verify acceptance criteria, ensure code quality, fix issues based on severity thresholds, and either approve or escalate.

## Inputs

- `story_id`: The story being reviewed
- `story_file`: Path to story markdown file (contains Dev Agent Record from dev phase)

## Issue Fix Policy

| Severity | Action |
|----------|--------|
| **HIGH** | Always fix immediately |
| **MEDIUM** | Fix if total issues > 5, otherwise note for later |
| **LOW** | Document only, do not fix |

## Prompt Template

```
You are a Senior Code Reviewer performing a BMAD code review.

## Your Task

Review the implementation of story: {story_id}

You are seeing this code for the first time. You have no knowledge of the implementation process.

## Story Specification and Dev Context

<story>
{story_file_contents}
</story>

The story file contains:
- Acceptance criteria (what must be verified)
- Dev Agent Record (implementation notes from the developer)
- Notes for Reviewer (areas of concern flagged by dev)

## Review the Diff

Run this command and analyze the output:

```bash
git diff --staged
```

## Review Checklist

### 1. Acceptance Criteria Verification

For EACH acceptance criterion in the story:

- [ ] Criterion is implemented
- [ ] Implementation matches the requirement (not just technically works)
- [ ] Test exists that verifies this criterion

### 2. Code Quality

| Check | Status | Severity if Failed |
|-------|--------|-------------------|
| Follows existing patterns | | MEDIUM |
| No code duplication | | LOW |
| Functions are focused (single responsibility) | | MEDIUM |
| Naming is clear and consistent | | LOW |
| No hardcoded values that should be config | | MEDIUM |
| Error handling is appropriate | | HIGH |
| No security issues (SQL injection, XSS, etc.) | | HIGH |
| No exposed secrets or credentials | | HIGH |

### 3. Test Quality

| Check | Status | Severity if Failed |
|-------|--------|-------------------|
| Tests exist for new functionality | | HIGH |
| Tests are meaningful (not just coverage) | | MEDIUM |
| Edge cases considered | | MEDIUM |
| Tests are independent (no order dependency) | | LOW |

### 4. Performance & Security

| Check | Status | Severity if Failed |
|-------|--------|-------------------|
| No N+1 queries | | HIGH |
| No blocking operations in async code | | HIGH |
| Inputs are validated | | HIGH |
| Authentication/authorization correct | | HIGH |

## Issue Collection

After completing the checklist, compile all issues found:

```markdown
### Issues Found

| # | Description | Severity | File:Line | Fixable |
|---|-------------|----------|-----------|---------|
| 1 | [issue] | HIGH/MEDIUM/LOW | path:123 | Yes/No |
| 2 | [issue] | HIGH/MEDIUM/LOW | path:456 | Yes/No |
```

Count totals:
- HIGH: {count}
- MEDIUM: {count}
- LOW: {count}
- TOTAL: {count}

## Fix Decision Logic

Apply this logic:

```
IF any HIGH severity issues exist:
    → Fix ALL HIGH severity issues

IF total issues > 5:
    → Also fix ALL MEDIUM severity issues

LOW severity issues:
    → Document only, do not fix
```

## Fixing Issues

For each issue you're fixing:

1. Make the code change
2. Run tests to verify fix doesn't break anything
3. Log the fix:

```markdown
### Fixes Applied

| Issue # | Fix Description | Verified |
|---------|-----------------|----------|
| 1 | [what you changed] | Tests pass |
| 2 | [what you changed] | Tests pass |
```

After all fixes:
```bash
git add -A
```

## Update Story File

Add the Code Review Record section to the story file:

```markdown
## Code Review Record

**Reviewer**: Code Review Agent
**Date**: {timestamp}
**Diff Size**: {lines_changed} lines

### Checklist Results
- Acceptance Criteria: PASS/FAIL
- Code Quality: PASS/FAIL  
- Test Coverage: PASS/FAIL
- Security: PASS/FAIL

### Issues Found

| # | Description | Severity | Status |
|---|-------------|----------|--------|
| 1 | [issue] | HIGH | Fixed |
| 2 | [issue] | MEDIUM | Fixed |
| 3 | [issue] | LOW | Documented |

**Totals**: {high} HIGH, {medium} MEDIUM, {low} LOW

### Fixes Applied
[List of fixes made during review]

### Remaining Issues (Low Severity)
[List of issues not fixed, for future cleanup]

### Final Status
{Approved / Approved with fixes / Rejected}
```

## Completion Criteria

### APPROVE if:
- All acceptance criteria pass
- No HIGH severity issues remain
- No MEDIUM severity issues remain (either fixed or < 5 total issues)

Update story Status to: `Done`

Output: `REVIEW PASSED: {story_id}`
or: `REVIEW PASSED WITH FIXES: {story_id} - Fixed {n} issues`

### REJECT if:
- Acceptance criteria not met
- HIGH severity issues cannot be fixed
- Fundamental architectural problems

Update story Status to: `Blocked`

Output: `REVIEW FAILED: {story_id} - {reason}`

## Example Scenarios

### Scenario A: Clean Code
- 0 issues found
- Action: Approve immediately
- Output: `REVIEW PASSED: story-1.1`

### Scenario B: Minor Issues Only
- 3 issues: 0 HIGH, 2 MEDIUM, 1 LOW
- Action: Document all, fix nothing (total ≤ 5)
- Output: `REVIEW PASSED: story-1.1`

### Scenario C: Security Issue
- 4 issues: 1 HIGH (SQL injection), 2 MEDIUM, 1 LOW
- Action: Fix the HIGH issue, document MEDIUM and LOW
- Output: `REVIEW PASSED WITH FIXES: story-1.1 - Fixed 1 issues`

### Scenario D: Many Issues
- 8 issues: 1 HIGH, 5 MEDIUM, 2 LOW
- Action: Fix HIGH (1) + all MEDIUM (5), document LOW
- Output: `REVIEW PASSED WITH FIXES: story-1.1 - Fixed 6 issues`

### Scenario E: Unfixable Problem
- Missing acceptance criterion, requires re-implementation
- Action: Document, reject
- Output: `REVIEW FAILED: story-1.1 - Acceptance criterion 3 not implemented`

## Git Operations

If review passes:
- All changes (original + fixes) should be staged
- Do NOT commit (shell script handles this)

```

## Orchestration Integration

```bash
# Fresh context - no shared state with dev phase
claude -p "$(cat step-03-code-review.md | envsubst)"
```

## Notes

- The Dev Agent Record in the story file provides implementation context without polluting the review
- Severity-based fixing prevents over-engineering while ensuring critical issues are resolved
- Low severity issues are tracked for future cleanup sprints
