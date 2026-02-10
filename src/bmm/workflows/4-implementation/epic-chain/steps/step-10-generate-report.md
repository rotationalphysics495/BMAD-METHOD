# Step 10: Generate Chain Execution Report

## Purpose

Generate a comprehensive execution report after the epic chain completes, aggregating metrics from all epics into a single document.

## Prerequisites

- All epics in the chain have completed (success or failure)
- Metrics files exist at `{metrics_folder}/epic-{id}-metrics.yaml` for each epic
- Chain plan file exists at `{chain_plan_file}`

## Inputs

| Input | Location | Required |
|-------|----------|----------|
| Chain Plan | `{chain_plan_file}` | Yes |
| Epic Metrics | `{metrics_folder}/epic-{id}-metrics.yaml` | Yes (per epic) |
| Story Files | `{stories_location}/*.md` | For story counts |
| UAT Documents | `{uat_location}/epic-{id}-uat.md` | For UAT summary |

## Process

### 10.1 Load All Metrics Files

For each epic in the chain plan:

```yaml
# Load from {metrics_folder}/epic-{id}-metrics.yaml
epic_id: "1"
epic_name: "Foundation, CLI & Deployment"

execution:
  start_time: "2026-01-02T13:40:00Z"
  end_time: "2026-01-02T15:10:00Z"
  duration_seconds: 5400

stories:
  total: 7
  completed: 7
  failed: 0
  skipped: 0

validation:
  gate_status: "PASS"
  fix_attempts: 0

issues: []
```

### 10.2 Calculate Aggregate Metrics

**Timing:**
- `start_time` = earliest epic start time
- `end_time` = latest epic end time
- `duration` = end_time - start_time (formatted as "Xh Ym")
- `avg_story_time` = total_duration / total_stories (formatted as "X minutes")

**Counts:**
- `epic_count` = number of epics in chain
- `story_count` = sum of all stories across epics
- `completed_count` = sum of completed stories
- `failed_count` = sum of failed stories
- `completion_pct` = (completed_count / story_count) * 100

**Status:**
- `chain_status` = "COMPLETE" if all epics passed, otherwise "PARTIAL" or "FAILED"

### 10.3 Build Timeline Table

For each epic, create a row:

```markdown
| {epic_id} | {epic_name} | {story_count} | {duration} | {status} |
```

Duration format: "X.X hours (Xs)" or "~X.X hours"

### 10.4 Build Dependency Graph

**ASCII Format:**
```
Epic 1 (Foundation)
    ├── Epic 2 (Event Ingestion) ──┐
    │       └── Epic 3 (Workflow) ─┼── Epic 7 (Observability)
    └── Epic 5 (AI Copilot) ───────┘
```

**Table Format:**
For each epic with dependencies:
```markdown
| {epic_id} | {depends_on_ids} | {reason} |
```

### 10.5 Generate Per-Epic Summary

For each epic, generate a section:

```markdown
### Epic {id}: {name} ({story_count} stories)

{brief_description_from_epic_file}

**Stories:**
{list_story_ids_and_titles}
```

### 10.6 Compile Issues Section

Aggregate all issues from metrics files:

```markdown
### {issue_type}

**Issue:** {description}
**Impact:** {affected_stories}
**Resolution:** {how_resolved}

**Affected Stories:**
{list_of_story_ids}
```

If no issues: "No significant issues encountered during execution."

### 10.7 Generate UAT Summary

For each epic:

```markdown
| {epic_id} | {uat_doc_path} | {scenario_count} | {auto_passed}/{automatable} | {fix_attempts} | {gate_status} |
```

**Fix History Section:**
If any epic required self-healing fixes:

```markdown
### Epic {id} Fix History

- **Attempt 1:** Fixed {scenario_ids}, committed {commit_hash}
- **Attempt 2:** Fixed remaining issues, all scenarios passing
```

### 10.8 Calculate Token Estimates

Per epic (based on story count):

```
calls_per_story = 2 (dev + review)
input_per_call = 8000 tokens
output_per_call = 4000 tokens

epic_calls = stories * calls_per_story
epic_input = epic_calls * input_per_call
epic_output = epic_calls * output_per_call
epic_total = epic_input + epic_output
```

**Cost Calculation:**
```
sonnet_input_rate = $3 / 1M tokens
sonnet_output_rate = $15 / 1M tokens
opus_input_rate = $15 / 1M tokens
opus_output_rate = $75 / 1M tokens
```

### 10.9 Generate Conclusion

Based on results:

**All Passed:**
```
The {project_name} was successfully implemented through automated AI-driven
development using the BMAD Epic Chain workflow. All {story_count} stories
across {epic_count} epics were completed in approximately {duration}.

The system provides:
{list_key_capabilities_from_epics}
```

**Partial Success:**
```
The epic chain completed with {completed_count}/{story_count} stories successful.
{failed_count} stories require attention before the system is production-ready.

See Issues Encountered section for details on failures and recommended actions.
```

### 10.10 Render Template

Load template from `{installed_path}/templates/chain-report-template.md`

Replace all `{variable}` placeholders with calculated values.

### 10.11 Save Report

Write rendered report to: `{chain_report_file}`

Default: `{sprint_artifacts}/chain-execution-report.md`

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Execution Report | `{chain_report_file}` | Complete chain execution report |

## Console Output

After generating:

```
═══════════════════════════════════════════════════════════
                 CHAIN EXECUTION REPORT GENERATED
═══════════════════════════════════════════════════════════

Report: {chain_report_file}

Summary:
  Epics: {epic_count}
  Stories: {completed_count}/{story_count} completed
  Duration: {duration}
  Status: {chain_status}

{if issues}
Issues: {issue_count} issues logged (see report)
{endif}

{if uat_failures}
UAT: {uat_pass_count}/{epic_count} epics passed validation
     {fix_total} self-healing fixes applied
{endif}

═══════════════════════════════════════════════════════════
```

## Error Handling

| Error | Action |
|-------|--------|
| Metrics file missing | Log warning, use defaults (0 duration, unknown status) |
| Chain plan missing | Error - cannot generate report without plan |
| Template missing | Use inline default template |
| Write fails | Error with path, suggest manual copy |
