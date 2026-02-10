# Step 4: Generate User Acceptance Testing Document (Isolated Context)

## Context Isolation

**IMPORTANT**: This step executes in a completely fresh context after all stories are complete. The UAT generator sees only the finished epic and story specifications—not implementation details. This produces a user-focused testing document, not a technical test plan.

## Objective

Generate a comprehensive User Acceptance Testing document that a non-technical stakeholder can use to verify the epic delivers its intended value.

## Inputs

- `epic_id`: The completed epic
- `epic_file`: Path to epic definition
- `completed_stories`: List of all story files in the epic

## Prompt Template

```
You are a QA Specialist creating a User Acceptance Testing document.

## Your Task

Generate a UAT document for Epic: {epic_id}

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

## Your Goal

Create a testing document that:

1. **Is written for humans, not developers**
   - No technical jargon
   - Step-by-step instructions anyone can follow
   - Clear expected outcomes

2. **Covers the user journey, not implementation**
   - Focus on what users can DO, not how code works
   - Scenarios flow like real usage patterns
   - Test the experience, not the functions

3. **Provides clear success criteria**
   - Binary pass/fail for each scenario
   - Obvious what "working" looks like
   - No ambiguity in expected results

## Output Format

Generate the document following this structure:

```markdown
# {Epic Title} - User Acceptance Testing

**Epic**: {epic_id}  
**Version**: 1.0  
**Generated**: {date}  
**Stories Covered**: {story_count}

---

## Overview

### What Was Built
[2-3 sentences describing what this epic delivers in plain language. 
Focus on user value, not technical implementation.]

### Who Should Test
[Who is the right person to test this? What role/knowledge do they need?]

### Time Estimate
[How long should testing take? e.g., "30-45 minutes"]

---

## Prerequisites

### Before You Begin

1. **Environment**
   - URL: {test_environment_url}
   - Browser: {recommended_browser}
   
2. **Test Account**
   - Username: {test_username}
   - Password: {test_password}
   - Or: [How to create a test account]

3. **Test Data Setup**
   [Any data that needs to exist before testing]
   ```bash
   # If setup script needed
   npm run seed:test
   ```

4. **Clean State**
   [How to reset to clean state between test runs]

---

## Test Scenarios

{Generate 3-8 scenarios that cover the epic's functionality}

### Scenario 1: {Descriptive Name}

**Purpose**: {What this scenario validates}

**Starting Point**: {Where/what state to begin}

**Steps**:

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | {Do this} | {See this} |
| 2 | {Do this} | {See this} |
| 3 | {Do this} | {See this} |

**Success Criteria**: {One sentence summary of pass condition}

**Result**: ☐ Pass  ☐ Fail

**Notes**: _________________________________

---

### Scenario 2: {Descriptive Name}

[Same structure...]

---

### Scenario N: {Edge Case or Error Handling}

**Purpose**: Verify system handles errors gracefully

**Steps**:

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | {Attempt invalid action} | {Appropriate error message} |
| 2 | {Verify no data corruption} | {System state unchanged} |

---

## Success Criteria Summary

This epic is **successful** when a user can:

- [ ] {High-level capability 1}
- [ ] {High-level capability 2}
- [ ] {High-level capability 3}
- [ ] {Error handling works gracefully}

**Minimum passing**: All checkboxes marked

---

## Issues Log

| # | Scenario | Issue Description | Severity | Screenshot |
|---|----------|-------------------|----------|------------|
| 1 | | | Critical/Major/Minor | |
| 2 | | | | |

### Severity Definitions

- **Critical**: Blocks core functionality, cannot proceed
- **Major**: Significant issue but workaround exists
- **Minor**: Cosmetic or minor inconvenience

---

## Sign-off

### Testing Summary

| Metric | Value |
|--------|-------|
| Scenarios Tested | /__ |
| Scenarios Passed | /__ |
| Critical Issues | |
| Major Issues | |
| Minor Issues | |

### Recommendation

☐ **Accept** - All criteria met, ready for production  
☐ **Accept with conditions** - Minor issues noted, can proceed  
☐ **Reject** - Critical/major issues must be resolved  

### Signatures

**Tested By**: _______________________  
**Date**: _______________________  

**Approved By**: _______________________  
**Date**: _______________________

---

## Appendix

### Test Data Reference
[Any reference data used in testing]

### Environment Details
[Technical details if needed for troubleshooting]
```

## Document Location

Save to: `docs/uat/epic-{epic_id}-uat.md`

## Completion Signal

Output: `UAT GENERATED: docs/uat/epic-{epic_id}-uat.md`
```

## Scenario Generation Guidelines

### Good Scenarios
- Follow realistic user workflows
- Build on each other (Scenario 2 assumes Scenario 1 completed)
- Include at least one "happy path" and one "error path"
- Test the boundaries (empty inputs, maximum values, etc.)

### Avoid
- Testing implementation details
- Requiring technical knowledge to execute
- Ambiguous expected results
- Overlapping scenarios that test the same thing

## Synthesis from Stories

Map story acceptance criteria to UAT scenarios:

| Story Criterion | UAT Scenario |
|----------------|--------------|
| "User can register with email" | Scenario 1: New User Registration |
| "Invalid email shows error" | Scenario 5: Registration Validation |
| "Session persists across browser restart" | Scenario 4: Session Persistence |

Not every criterion needs its own scenario—group related criteria into coherent user journeys.

## Orchestration Integration

```bash
# Completely fresh context - knows nothing about dev or review
claude -p "$(cat step-04-generate-uat.md | envsubst)"
```
