---
title: "Epic Chain Execution Report Generator - Proposal"
---

# Epic Chain Execution Report Generator - Proposal

## Overview

This proposal describes how to automatically generate a comprehensive Epic Chain Execution Report at the end of each epic chain run, similar to the sample `epic-chain-execution-report.md`.

---

## 1. Report Generation Strategy

### When to Generate

The report should be generated as **Phase 5** of the epic-chain workflow, after all epics complete:

```
Epic 1 → Epic 2 → ... → Epic N → [Report Generation] → [Optional: UAT Gate]
```

### Data Sources

The report aggregates data from multiple sources created during execution:

| Source | Location | Data Extracted |
|--------|----------|----------------|
| Chain Plan | `{sprint_artifacts}/chain-plan.yaml` | Epic order, dependencies, total stories |
| Execution Logs | `{sprint_artifacts}/epic-{id}-execution.md` | Per-epic timing, status, issues |
| Story Files | `docs/stories/*.md` | Story count, completion status |
| UAT Documents | `docs/uat/epic-{id}-uat.md` | UAT generation confirmation |
| Git Log | `git log --oneline` | Commit count per epic |
| Handoffs | `docs/handoffs/*.md` | Cross-epic context transfers |

---

## 2. Workflow Integration

### Option A: Add Phase to Epic Chain (Recommended)

Modify `epic-chain/workflow.yaml` to include a report generation step:

```yaml
# In workflow.yaml variables section
variables:
  # ... existing variables ...

  # Report configuration
  chain_report_file: "{sprint_artifacts}/chain-execution-report.md"
  generate_report: true
  report_detail_level: "full"  # summary | standard | full

# Add step reference
steps:
  # ... existing steps ...
  - step: generate-report
    file: step-06-generate-report.md
    when: "chain_complete"
    outputs:
      - "{chain_report_file}"
```

### Option B: Separate Workflow (Alternative)

Create `epic-chain-report/workflow.yaml` triggered post-chain:

```yaml
name: epic-chain-report
description: "Generate execution report from completed epic chain"
trigger: "post-chain"

input_file_patterns:
  chain_plan:
    path: "{sprint_artifacts}/chain-plan.yaml"
    required: true
  execution_logs:
    pattern: "{sprint_artifacts}/epic-*-execution.md"
    load_strategy: "FULL_LOAD"
```

---

## 3. Report Template Structure

### Proposed Template: `chain-report-template.md`

```markdown
# {project_name} - Epic Chain Execution Report

## Executive Summary

**Project:** {project_name}
**Execution Method:** BMAD Epic Chain (automated AI-driven development)
**Status:** {chain_status}

| Metric | Value |
|--------|-------|
| Total Epics | {epic_count} |
| Total Stories | {story_count} |
| Start Time | {start_time} |
| End Time | {end_time} |
| Total Duration | {duration} |
| Average per Story | {avg_story_time} |

---

## Timeline

### Epic Execution Duration

| Epic | Name | Stories | Duration | Status |
|------|------|---------|----------|--------|
{epic_timeline_rows}
| **Total** | | **{story_count}** | **{duration}** | **{completion_pct}%** |

---

## Dependency Graph

{dependency_graph_mermaid}

### Explicit Dependencies

| Epic | Depends On | Reason |
|------|------------|--------|
{dependency_table_rows}

---

## What Was Built

{per_epic_summary}

---

## Issues Encountered

{issues_section}

---

## Artifacts Generated

| Artifact | Location | Description |
|----------|----------|-------------|
| Story Files | `docs/stories/` | {story_count} completed stories |
| UAT Documents | `docs/uat/` | {epic_count} UAT test documents |
| Epic Files | `docs/epics/` | {epic_count} epic definitions |
| Handoffs | `docs/handoffs/` | Cross-epic context documents |
| Chain Plan | `{chain_plan_file}` | Execution plan with dependencies |

---

## Metrics

### Estimated Token Usage

| Epic | Stories | Est. Calls | Est. Input | Est. Output | Est. Total |
|------|---------|------------|------------|-------------|------------|
{token_estimate_rows}

### Cost Estimates

| Model | Input Cost | Output Cost | Total |
|-------|------------|-------------|-------|
| Claude Sonnet 3.5 | ~${sonnet_input} | ~${sonnet_output} | ~${sonnet_total} |
| Claude Opus | ~${opus_input} | ~${opus_output} | ~${opus_total} |

---

## UAT Validation Status

| Epic | UAT Doc | Automatable | Auto-Passed | Manual Required | Status |
|------|---------|-------------|-------------|-----------------|--------|
{uat_status_rows}

---

## Next Steps

1. **Review UAT Documents** - Review the {epic_count} UAT documents in `docs/uat/`
2. **Execute UAT Validation** - Run `/uat-validator` for automated scenario testing
3. **Manual Acceptance Testing** - Execute manual test scenarios
4. **Code Review** - Review generated code for refinements
5. **Deploy to Staging** - Deploy complete system to staging environment

---

*Report generated: {generation_timestamp}*
*BMAD Method v{bmad_version}*
```

---

## 4. Data Collection During Execution

### Metrics to Track Per Epic

Add to `epic-execute` workflow to collect data for the report:

```yaml
# Proposed: epic-metrics.yaml (created per epic)
epic_id: 1
epic_name: "Foundation, CLI & Deployment"
stories:
  total: 7
  completed: 7
  failed: 0
  skipped: 0
timing:
  start_time: "2026-01-02T13:40:00Z"
  end_time: "2026-01-02T15:10:00Z"
  duration_seconds: 5400
  avg_story_seconds: 771
issues:
  - story: "1-3"
    type: "signaling_mismatch"
    description: "Completed but didn't output expected phrase"
    resolution: "manual_status_update"
dependencies:
  requires: []
  enables: ["2", "5"]
artifacts:
  stories_created: 7
  uat_generated: true
  commits: 7
```

### Collection Script Enhancement

The orchestration script (`epic-chain.sh`) should:

1. **Start timer** at chain initialization
2. **Per epic**: Record start/end times, story counts, issues
3. **Write metrics** to `{sprint_artifacts}/epic-{id}-metrics.yaml`
4. **On completion**: Trigger report generation step

---

## 5. UAT Validation Integration

### Gate Check Before Next Epic (Optional)

```yaml
# In epic-chain workflow
chain_mode: "dependency-aware"
uat_gate:
  enabled: true
  mode: "quick"  # quick | full | skip
  blocking: false  # If true, stops chain on UAT failure

# After each epic completes:
# 1. Generate UAT doc (already in epic-execute)
# 2. Run uat-quick validation
# 3. Record results in metrics
# 4. Continue or halt based on blocking setting
```

### Validation Flow

```
Epic Complete
     │
     ▼
Generate UAT Doc
     │
     ▼
Run UAT Quick ──────┐
(automatable only)  │
     │              │
     ▼              ▼
 PASS           FAIL
   │              │
   ▼              ▼
Continue     blocking=true? ──► HALT CHAIN
                │
                ▼ (blocking=false)
           Log Warning
                │
                ▼
           Continue
```

---

## 6. Implementation Phases

### Phase 1: Metrics Collection
- [ ] Add timing instrumentation to `epic-execute.sh`
- [ ] Create `epic-metrics.yaml` output per epic
- [ ] Store in `{sprint_artifacts}/metrics/`

### Phase 2: Report Generation
- [ ] Create `step-06-generate-report.md` for epic-chain
- [ ] Build `chain-report-template.md` template
- [ ] Add report generation to workflow.yaml

### Phase 3: UAT Integration
- [ ] Create UAT Validator agent (see `uat-validator.agent.yaml`)
- [ ] Add `uat-validate/workflow.yaml`
- [ ] Integrate gate check into epic-chain

### Phase 4: Visualization
- [ ] Add Mermaid dependency graph generation
- [ ] Add timeline visualization
- [ ] Consider HTML report option

---

## 7. Report Generation Agent Action

For the SM agent or a dedicated Report Generator, add this action:

```yaml
- trigger: CR or fuzzy match on chain-report
  action: |
    Generate Epic Chain Execution Report:
    1. Load chain-plan.yaml for epic list and dependencies
    2. For each epic, load epic-{id}-metrics.yaml
    3. Aggregate timing, story counts, issues
    4. Generate dependency graph (Mermaid format)
    5. Calculate token/cost estimates
    6. Load UAT validation results if available
    7. Render template with collected data
    8. Output to {sprint_artifacts}/chain-execution-report.md
  description: "[CR] Generate comprehensive execution report for completed epic chain"
```

---

## 8. Sample Output

See `/epic-chain-execution-report.md` for a complete example of the target output format. Key sections:

- Executive summary with totals
- Timeline table with per-epic duration
- Dependency graph (ASCII or Mermaid)
- What was built (per epic)
- Issues encountered
- Artifacts generated
- Token/cost estimates
- Next steps

---

## Questions for Decision

1. **Report timing**: Generate after each epic (incremental) or only at chain end?
2. **UAT gate**: Should failed UAT block the chain or just warn?
3. **Token tracking**: Actual counts (requires API integration) or estimates?
4. **Report format**: Markdown only, or also HTML/PDF export?
5. **Integration with SM**: Add to SM agent menu, or create dedicated reporter agent?
