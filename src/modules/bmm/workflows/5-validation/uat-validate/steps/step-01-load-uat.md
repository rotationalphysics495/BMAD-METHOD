# Step 1: Load UAT Document

## Purpose

Load and validate the UAT document for the specified epic, extracting all test scenarios for classification and execution.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| epic_id | CLI argument | Yes |
| uat_dir | Configuration | Yes (default: `docs/uat`) |

## Process

### 1.1 Locate UAT Document

Search for UAT document using these patterns in order:
1. `{uat_dir}/epic-{epic_id}-uat.md`
2. `{uat_dir}/epic-0{epic_id}-uat.md` (zero-padded)
3. `{uat_dir}/{epic_id}-uat.md`

**If not found:** Exit with error code 1 and message:
```
UAT document not found for Epic {epic_id}
Searched in: {uat_dir}
Expected: epic-{epic_id}-uat.md
```

### 1.2 Validate Document Structure

Confirm document contains at least one of these sections:
- `## Test Scenarios`
- `## Acceptance Criteria`
- `## Scenarios`
- `## Success Criteria`

**Warning if missing:** Log warning but continue (scenarios may be inline)

### 1.3 Parse Scenarios

Extract scenario blocks by detecting:
- Headers starting with `###` (individual scenario titles)
- Numbered items `1.`, `2.`, etc. under scenario sections
- Checkbox items `- [ ]` in criteria sections

For each scenario, extract:
- **Scenario ID**: Numeric index or explicit ID
- **Scenario Name**: Title text
- **Steps**: Given/When/Then or numbered steps
- **Verification Command**: Code block or CLI reference (if present)
- **Expected Result**: Success criteria text

### 1.4 Build Scenario List

Create structured list of scenarios:

```yaml
scenarios:
  - id: 1
    name: "Project Initialization"
    steps:
      - "Run npx heimdall init"
      - "Verify config file created"
    verification_command: "npx heimdall --version"
    expected_result: "displays a version number"
    raw_content: |
      ### 1. Project Initialization
      ...
```

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| scenario_list | Memory/State | Array of parsed scenario objects |
| scenario_count | Console | Total number of scenarios found |
| uat_file_path | State | Path to loaded UAT document |

## Completion Signal

```
UAT_LOADED: {scenario_count} scenarios from {uat_file_path}
```

## Error Handling

| Error | Action |
|-------|--------|
| File not found | Exit 1 with clear error message |
| Empty file | Exit 1 with "UAT document is empty" |
| No scenarios detected | Log warning, return empty list (gate passes by default) |
| Parse error | Log warning for specific section, continue with partial results |

## Example Output

```
[UAT] Loading UAT document for Epic 1
[UAT] Found: docs/uat/epic-1-uat.md
[UAT] Parsed 9 scenarios
UAT_LOADED: 9 scenarios from docs/uat/epic-1-uat.md
```
