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

```
{dependency_graph_ascii}
```

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

## UAT Validation Summary

| Epic | UAT Doc | Scenarios | Auto-Passed | Fix Attempts | Status |
|------|---------|-----------|-------------|--------------|--------|
{uat_status_rows}

### Self-Healing Fix History

{fix_history_section}

---

## Artifacts Generated

| Artifact | Location | Description |
|----------|----------|-------------|
| Story Files | `{stories_location}` | {story_count} completed stories with dev & review records |
| UAT Documents | `{uat_location}` | {epic_count} User Acceptance Test documents |
| Epic Files | `{epics_location}` | {epic_count} epic definition files |
| Handoffs | `{handoffs_location}` | Cross-epic context transfer documents |
| Chain Plan | `{chain_plan_file}` | Execution plan with dependencies |
| Metrics | `{metrics_folder}` | Per-epic execution metrics |

---

## Estimated Token Usage

| Epic | Stories | Est. Calls | Est. Input | Est. Output | Est. Total |
|------|---------|------------|------------|-------------|------------|
{token_estimate_rows}
| **Total** | **{story_count}** | **{total_calls}** | **~{total_input}** | **~{total_output}** | **~{total_tokens}** |

### Cost Estimates

| Model | Input Cost | Output Cost | Total |
|-------|------------|-------------|-------|
| Claude Sonnet 3.5 ($3/$15 per 1M) | ~${sonnet_input_cost} | ~${sonnet_output_cost} | ~${sonnet_total_cost} |
| Claude Opus ($15/$75 per 1M) | ~${opus_input_cost} | ~${opus_output_cost} | ~${opus_total_cost} |

*Note: These are estimates based on ~8K input / ~4K output tokens per story. Actual usage may vary.*

---

## Next Steps

1. **Review UAT Documents** - Review the {epic_count} UAT documents in `{uat_location}`
2. **Execute UAT Validation** - Run `*uat-validate` for each epic to verify implementations
3. **Manual Acceptance Testing** - Execute manual test scenarios from UAT docs
4. **Code Review** - Review generated code for refinements
5. **Integration Testing** - Test cross-epic integrations
6. **Deploy to Staging** - Deploy complete system to staging environment

---

## Conclusion

{conclusion_text}

---

*Report generated: {generation_timestamp}*
*BMAD Method Epic Chain v1.0*
