# Step 3c: Requirements Traceability & Coverage Gate (Per-Epic)

## Context Isolation

**IMPORTANT**: This step executes in a fresh Claude context after ALL stories are complete but before UAT generation. It validates that every acceptance criterion across the epic has appropriate test coverage.

## Objective

Generate a requirements-to-tests traceability matrix for the entire epic. Identify coverage gaps, and if gaps exist, trigger a self-healing loop to generate missing tests before proceeding to UAT.

## Inputs

- `epic_id`: The completed epic
- `epic_file`: Path to epic definition
- `completed_stories`: List of all story files in the epic
- `test_dir`: Project's test directory (auto-discovered)

## Integration with testarch-trace

This step applies the full `testarch-trace` workflow to generate:
- Requirements-to-tests traceability matrix
- Coverage analysis by priority (P0/P1/P2/P3)
- Gap identification with severity
- Quality gate decision (PASS/CONCERNS/FAIL)

## Coverage Thresholds

| Priority | Required Coverage | Gate Impact |
|----------|-------------------|-------------|
| **P0** (Critical) | 100% | FAIL if not met |
| **P1** (High) | ≥90% | CONCERNS if 80-89%, FAIL if <80% |
| **P2** (Medium) | ≥80% | Advisory only |
| **P3** (Low) | No requirement | Advisory only |

## Prompt Template

```
You are a Test Architect (TEA) executing requirements traceability analysis for a BMAD epic.

## Your Task

Generate a traceability matrix for Epic: {epic_id}

Map ALL acceptance criteria from ALL stories to their implementing tests.
Identify coverage gaps and determine if the epic is ready for UAT.

## Epic Definition

<epic>
{epic_file_contents}
</epic>

## Completed Stories

{for each story}
<story id="{story_id}">
{story_file_contents}
</story>
{end for}

## Phase 1: Discover and Catalog Tests

### 1.1 Find Test Files

```bash
# List all test files in the project
find . -type f \( -name "*.spec.ts" -o -name "*.test.ts" -o -name "*.spec.js" -o -name "*.test.js" \) | head -100
```

### 1.2 Extract Test Metadata

For each test file related to this epic:
- Test IDs (e.g., `{epic_id}-{story_seq}-E2E-001`)
- Describe blocks
- It blocks (individual test cases)
- Given-When-Then structure
- Priority markers (P0/P1/P2/P3)

## Phase 2: Map Criteria to Tests

### 2.1 For Each Acceptance Criterion

Search for explicit references:
- Test IDs mentioning the criterion
- Describe blocks referencing the requirement
- Given-When-Then narratives that match

### 2.2 Build Traceability Matrix

```markdown
## Traceability Matrix - Epic {epic_id}

### Coverage Summary

| Priority | Total Criteria | Covered | Coverage % | Status |
|----------|---------------|---------|------------|--------|
| P0       | {count}       | {count} | {%}        | ✅/❌  |
| P1       | {count}       | {count} | {%}        | ✅/⚠️/❌ |
| P2       | {count}       | {count} | {%}        | ✅/⚠️  |
| P3       | {count}       | {count} | {%}        | ✅     |
| **Total**| {count}       | {count} | {%}        | {status} |

### Detailed Mapping

#### Story {story_id}: {story_title}

| AC ID | Description | Priority | Test ID | Test File | Level | Status |
|-------|-------------|----------|---------|-----------|-------|--------|
| AC-1  | User can... | P0       | {id}-E2E-001 | tests/e2e/... | E2E | FULL |
| AC-2  | Error shows...| P1     | {id}-UNIT-001 | tests/unit/... | Unit | PARTIAL |
| AC-3  | Data persists | P1     | - | - | - | NONE |
```

### 2.3 Classify Coverage Status

For each criterion:
- **FULL**: All scenarios tested at appropriate level(s)
- **PARTIAL**: Some coverage but missing edge cases or levels
- **NONE**: No test coverage
- **UNIT-ONLY**: Only unit tests (missing integration/E2E)
- **INTEGRATION-ONLY**: Only integration tests (missing unit confidence)

## Phase 3: Gap Analysis

### 3.1 Identify Critical Gaps

```markdown
### Coverage Gaps

#### Critical Gaps (BLOCKING - P0 without coverage)

| Story | AC | Description | Recommended Test |
|-------|-----|-------------|------------------|
| {id}  | AC-2 | [desc] | {id}-E2E-002: [Given-When-Then] |

#### High Priority Gaps (P1 coverage <90%)

| Story | AC | Description | Current | Missing |
|-------|-----|-------------|---------|---------|
| {id}  | AC-5 | [desc] | UNIT-ONLY | E2E test for integration |

#### Medium Priority Gaps (Advisory)

| Story | AC | Description | Current | Recommendation |
|-------|-----|-------------|---------|----------------|
| {id}  | AC-8 | [desc] | PARTIAL | Add edge case tests |
```

### 3.2 Gate Decision

Apply decision rules:

**PASS** if ALL:
- P0 coverage = 100%
- P1 coverage ≥ 90%
- Overall coverage ≥ 80%
- No critical gaps

**CONCERNS** if ANY:
- P1 coverage 80-89%
- P2 coverage <50%
- Minor gaps in edge case coverage

**FAIL** if ANY:
- P0 coverage < 100%
- P1 coverage < 80%
- Critical acceptance criteria without tests

## Phase 4: Self-Healing (If Gaps Found)

### If FAIL or CONCERNS with P0/P1 gaps:

Generate specific test recommendations:

```markdown
### Tests to Generate

For each gap, provide:

#### Gap 1: {story_id} AC-{n} - {description}

**Priority**: P0/P1
**Recommended Test ID**: {story_id}-E2E-{seq}
**Test Level**: E2E/Integration/Unit
**File Location**: tests/{level}/{feature}.spec.ts

**Test Specification**:
```gherkin
Feature: {feature name}

Scenario: {scenario name}
  Given {precondition}
  When {action}
  Then {expected result}
```

**Implementation Guidance**:
- Setup: {what data/state to prepare}
- Action: {what to test}
- Assertions: {what to verify}
- Cleanup: {what to clean up}
```

### 4.1 Output for Fix Loop

If gaps need fixing, output:

```
TRACEABILITY GAPS START
GAP: {story_id}|AC-{n}|{priority}|{description}|{recommended_test_id}|{test_level}
SPEC:
  Given: {precondition}
  When: {action}
  Then: {expected result}
GAP: {next gap...}
TRACEABILITY GAPS END
```

## Deliverables

### 1. Traceability Matrix Document

Save to: `docs/sprint-artifacts/traceability/epic-{epic_id}-traceability.md`

### 2. Gate Decision Summary

```markdown
## Quality Gate Decision

**Epic**: {epic_id}
**Decision**: PASS / CONCERNS / FAIL
**Date**: {date}

### Evidence Summary

| Metric | Threshold | Actual | Status |
|--------|-----------|--------|--------|
| P0 Coverage | 100% | {%} | ✅/❌ |
| P1 Coverage | ≥90% | {%} | ✅/⚠️/❌ |
| Overall Coverage | ≥80% | {%} | ✅/⚠️/❌ |
| Critical Gaps | 0 | {count} | ✅/❌ |

### Recommendation

{PASS: Proceed to UAT generation}
{CONCERNS: Proceed with noted gaps, create follow-up stories}
{FAIL: Generate missing tests before UAT}
```

### 3. Gate YAML Snippet

```yaml
traceability:
  epic_id: "{epic_id}"
  coverage:
    overall: {%}
    p0: {%}
    p1: {%}
    p2: {%}
  gaps:
    critical: {count}
    high: {count}
    medium: {count}
  status: "PASS|CONCERNS|FAIL"
  timestamp: "{timestamp}"
```

## Completion Signals

### TRACEABILITY PASS if:
- P0 coverage = 100%
- P1 coverage ≥ 90%
- No critical gaps

Output: `TRACEABILITY PASS: {epic_id} - P0: 100%, P1: {p1}%, Overall: {overall}%`

### TRACEABILITY CONCERNS if:
- P0 coverage = 100%
- P1 coverage 80-89%

Output: `TRACEABILITY CONCERNS: {epic_id} - P1 at {p1}% (below 90%)`

### TRACEABILITY FAIL if:
- P0 coverage < 100%
- P1 coverage < 80%

First output gaps block (for self-healing):
```
TRACEABILITY GAPS START
GAP: ...
TRACEABILITY GAPS END
```
Then: `TRACEABILITY FAIL: {epic_id} - P0: {p0}%, P1: {p1}%, {n} critical gaps`
```

## Self-Healing Fix Loop

When TRACEABILITY FAIL is signaled with gaps:

1. **Gap Extraction**: Shell script extracts gaps from output
2. **Test Generation Phase**: New Claude context generates missing tests
3. **Re-run Traceability**: Verify gaps are closed
4. **Max Attempts**: 3 attempts before proceeding with CONCERNS and follow-up stories

### Test Generation Prompt (for fix loop)

```
You are a Test Architect generating tests to close coverage gaps.

## Gaps to Address

{gaps_from_traceability}

## Instructions

For each gap:
1. Create the test file if it doesn't exist
2. Implement the test following the Given-When-Then specification
3. Use existing test patterns from the codebase
4. Run the test to verify it passes
5. Stage changes: git add -A

## Completion

Output: TEST GENERATION COMPLETE: Generated {n} tests
Or: TEST GENERATION PARTIAL: Generated {n} of {m} tests - {reason for gaps}
```

## Notes

- This step runs ONCE per epic, not per story
- It catches acceptance criteria that slipped through without tests
- Self-healing generates tests automatically rather than just reporting gaps
- The traceability matrix becomes documentation for UAT and compliance
- Follow-up stories are created for gaps that can't be auto-generated
```

## Orchestration Integration

```bash
# Fresh context - comprehensive traceability analysis
claude -p "$(cat step-03c-traceability.md | envsubst)"
```

## Success Criteria

Phase complete when:
- Traceability matrix generated
- Gate decision made (PASS/CONCERNS/FAIL)
- If FAIL: Self-healing loop attempted (max 3 times)
- TRACEABILITY PASS or CONCERNS signal output
- Ready for UAT generation
