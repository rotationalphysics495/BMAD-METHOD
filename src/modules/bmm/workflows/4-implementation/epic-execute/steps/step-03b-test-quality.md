# Step 3b: Test Quality Review (Per-Story)

## Context Isolation

**IMPORTANT**: This step executes in a fresh Claude context after code review passes. It validates that the tests written for this story meet quality standards before moving to the next story.

## Objective

Review the tests created during the dev phase using TEA's test quality criteria. Ensure tests are maintainable, deterministic, isolated, and not flaky. This prevents accumulation of low-quality tests across the epic.

## Inputs

- `story_id`: The story being validated
- `story_file`: Path to story markdown file (contains Dev Agent Record with test list)

## Integration with testarch-test-review

This step applies the full `testarch-test-review` workflow to the tests created for this story. It uses TEA's knowledge base of best practices for:

- Fixture architecture
- Network-first safeguards
- Data factories
- Determinism and isolation
- Flakiness prevention

## Prompt Template

```
You are a Test Architect (TEA) executing a test quality review for a BMAD story.

## Your Task

Review the tests created for story: {story_id}

You are validating test quality AFTER code review has passed. Focus on test maintainability,
determinism, isolation, and flakiness prevention.

## Story Context

<story>
{story_file_contents}
</story>

The Dev Agent Record in the story lists tests added:
- Locate these test files
- Review each against quality criteria

## Test Files to Review

Based on the Dev Agent Record, find and review these test files:

```bash
# List test files that were added/modified in this story
git diff --staged --name-only | grep -E '\.(spec|test)\.(ts|js|tsx|jsx)$'
```

## Quality Criteria (from testarch-test-review)

### 1. BDD Format (Given-When-Then)
- ✅ PASS: Tests use clear Given-When-Then structure
- ⚠️ WARN: Some structure but not explicit
- ❌ FAIL: No clear structure, intent hard to understand

### 2. Test ID Conventions
- ✅ PASS: Test IDs present (e.g., `{story_id}-E2E-001`, `{story_id}-UNIT-001`)
- ⚠️ WARN: Some IDs missing
- ❌ FAIL: No test IDs, can't trace to requirements

### 3. Hard Waits Detection
- ✅ PASS: No hard waits (no `sleep()`, `waitForTimeout()`, hardcoded delays)
- ⚠️ WARN: Hard waits with justification comments
- ❌ FAIL: Hard waits without justification (flakiness risk)

**Patterns to detect:**
- `sleep(1000)`, `setTimeout()`, `delay()`
- `page.waitForTimeout(5000)` without reason
- `await new Promise(resolve => setTimeout(resolve, X))`

### 4. Determinism
- ✅ PASS: Tests are deterministic (no conditionals controlling flow, no random values)
- ⚠️ WARN: Some conditionals with justification
- ❌ FAIL: Tests use if/else, try/catch abuse, Math.random()

### 5. Isolation & Cleanup
- ✅ PASS: Tests clean up resources, no shared state, can run in any order
- ⚠️ WARN: Some cleanup gaps but isolated enough
- ❌ FAIL: Tests share state, depend on execution order

**Check for:**
- afterEach/afterAll cleanup hooks
- No global variable mutation
- Database/API state cleanup
- Test data deletion

### 6. Explicit Assertions
- ✅ PASS: Every test has explicit assertions (expect, assert, toHaveText)
- ⚠️ WARN: Some tests rely on implicit waits
- ❌ FAIL: Missing assertions, tests don't verify behavior

### 7. Test Length
- ✅ PASS: Test file ≤200 lines (ideal), ≤300 lines (acceptable)
- ⚠️ WARN: 301-500 lines (consider splitting)
- ❌ FAIL: >500 lines (too large, maintainability risk)

### 8. Test Duration (estimated)
- ✅ PASS: Individual tests estimated ≤90 seconds
- ⚠️ WARN: Some tests 90-180 seconds
- ❌ FAIL: Tests >180 seconds (too slow)

### 9. Fixture Patterns
- ✅ PASS: Uses fixtures for common setup
- ⚠️ WARN: Some fixtures, some repetition
- ❌ FAIL: No fixtures, tests repeat setup code

### 10. Data Factories
- ✅ PASS: Uses factory functions with overrides
- ⚠️ WARN: Some factories, some hardcoded data
- ❌ FAIL: Hardcoded test data, magic strings/numbers

### 11. Network-First Pattern (for E2E/Integration)
- ✅ PASS: Route interception BEFORE navigation
- ⚠️ WARN: Some routes correct, others after navigation
- ❌ FAIL: Route interception after navigation (race conditions)

### 12. Flakiness Patterns
- ✅ PASS: No known flaky patterns
- ⚠️ WARN: Some potential flaky patterns
- ❌ FAIL: Multiple flaky patterns detected

**Detect:**
- Tight timeouts (e.g., `{ timeout: 1000 }`)
- Race conditions
- Timing-dependent assertions
- Retry logic hiding flakiness

## Quality Score Calculation

```
Starting Score: 100

Critical Violations (each): -10 points
  - Hard waits without justification
  - Missing assertions
  - Race conditions
  - Shared state

High Violations (each): -5 points
  - Missing test IDs
  - No BDD structure
  - Hardcoded data
  - Missing fixtures

Medium Violations (each): -2 points
  - Long test files (>300 lines)
  - Missing priority markers
  - Some conditionals

Low Violations (each): -1 point
  - Minor style issues
  - Incomplete cleanup

Bonus Points:
  - Excellent BDD structure: +5
  - Comprehensive fixtures: +5
  - Network-first pattern: +5
  - Perfect isolation: +5
  - All test IDs present: +5

Quality Score: max(0, min(100, Starting Score - Violations + Bonus))
```

## Issue Collection

```markdown
### Test Quality Issues

| # | Criterion | Description | Severity | File:Line | Fixable |
|---|-----------|-------------|----------|-----------|---------|
| 1 | Hard Wait | [description] | HIGH | path:123 | Yes |
| 2 | Isolation | [description] | MEDIUM | path:456 | Yes |

**Quality Score**: {score}/100 ({grade})
```

## Fix Policy

| Severity | Action |
|----------|--------|
| **Critical (P0)** | Must fix - these cause flakiness |
| **High (P1)** | Fix if total issues > 3 |
| **Medium (P2)** | Document for future improvement |
| **Low (P3)** | Document only |

## Fixing Issues

For Critical and High issues:

1. Make the test improvement
2. Run the test to verify it still passes
3. Stage the changes: `git add -A`
4. Document the fix

Example fixes:

### Hard Wait → Explicit Wait
```typescript
// ❌ BAD
await page.waitForTimeout(2000);
await expect(locator).toBeVisible();

// ✅ GOOD
await expect(locator).toBeVisible({ timeout: 10000 });
```

### Missing Assertion
```typescript
// ❌ BAD
await page.click('button');
// test ends without checking result

// ✅ GOOD
await page.click('button');
await expect(page.locator('.success-message')).toBeVisible();
```

### Hardcoded Data → Factory
```typescript
// ❌ BAD
const user = { email: 'test@example.com', name: 'John' };

// ✅ GOOD
import { createTestUser } from './factories/user';
const user = createTestUser({ role: 'admin' });
```

## Update Story File

Add test quality summary to story:

```markdown
## Test Quality Review

**Quality Score**: {score}/100 ({grade})
**Tests Reviewed**: {count}

### Issues Found
- {count} Critical: [list]
- {count} High: [list]
- {count} Medium: [list]

### Fixes Applied
- [Fix 1 description]
- [Fix 2 description]
```

## Completion Signals

### QUALITY APPROVED if:
- Quality score ≥ 70 (B or better)
- No critical issues remaining
- No high issues remaining (or all fixed)

Output: `TEST QUALITY APPROVED: {story_id} - Score: {score}/100`
or: `TEST QUALITY APPROVED WITH FIXES: {story_id} - Score: {score}/100, Fixed {n} issues`

### QUALITY CONCERNS if:
- Quality score 60-69 (C)
- Some medium issues but no blockers

Output: `TEST QUALITY CONCERNS: {story_id} - Score: {score}/100`

### QUALITY FAILED if:
- Quality score < 60 (F)
- Critical issues that cannot be fixed
- Systemic quality problems

Output the issues block:
```
TEST QUALITY ISSUES START
- [CRITICAL] Description (file:line)
- [HIGH] Description (file:line)
TEST QUALITY ISSUES END
```
Then: `TEST QUALITY FAILED: {story_id} - Score: {score}/100`

## Notes

- This step catches test quality issues BEFORE they accumulate across stories
- Flaky tests caught here are much cheaper to fix than after they cause CI failures
- The quality score is a guide, not an absolute - context matters
- When in doubt, prioritize determinism and isolation over other concerns
```

## Orchestration Integration

```bash
# Fresh context - focused only on test quality
claude -p "$(cat step-03b-test-quality.md | envsubst)"
```

## Integration with Fix Loop

If critical/high issues are found:
1. Issues are passed to a fix phase
2. Fix phase addresses quality issues
3. Re-run quality check
4. Max 2 attempts before proceeding with CONCERNS status

## Success Criteria

Phase complete when:
- Quality score ≥ 70 OR all critical/high issues fixed
- Changes are staged in git
- TEST QUALITY APPROVED signal output (or CONCERNS for borderline)
