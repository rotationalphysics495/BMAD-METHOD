# Epic Chain - Analysis and Execution Instructions

<critical>The workflow execution engine is governed by: {project-root}/.bmad/core/tasks/workflow.xml</critical>
<critical>You MUST have already loaded and processed: {project-root}/.bmad/bmm/workflows/4-implementation/epic-chain/workflow.yaml</critical>

## Overview

This workflow analyzes multiple epics to understand their relationships, then chains their execution with context sharing between epics.

<workflow>

<step n="1" goal="Gather and validate epic IDs">
<action>Communicate in {communication_language} with {user_name}</action>
<action>Ask which epics to chain if not already provided</action>

**Accept input formats:**
- Space-separated: `36 37 38`
- Comma-separated: `36, 37, 38`
- Range notation: `36-38` (expand to individual IDs)
- Mixed: `36-38, 40` (expand ranges, keep individuals)

**For each epic ID, validate:**
1. Epic file exists at `{epics_location}/epic-{id}*.md`
2. At least one story exists for the epic in `{stories_location}/`

**Output:** List of validated epic IDs in order provided

<on-failure>Report which epic IDs failed validation and ask user to correct</on-failure>
</step>

<step n="2" goal="Load epic and story content">
<action>For each validated epic, load:</action>

1. **Epic file**: Read full content from `{epics_location}/epic-{id}*.md`
2. **Story files**: Find all stories matching patterns:
   - `{stories_location}/{id}-*-*.md` (e.g., `36-1-user-auth.md`)
   - `{stories_location}/story-{id}.*-*.md`
   - Files containing `Epic: {id}` in content

**Extract from each epic:**
- Title and description
- User stories listed
- Any `## Dependencies` section
- Technical context or requirements
- Mentioned patterns, components, or integrations

**Extract from each story:**
- Story ID and title
- Status (Draft, Ready, In Progress, Done)
- Acceptance criteria
- Technical implementation notes
- References to shared code, APIs, or components

<output>Structured data for all epics and stories</output>
</step>

<step n="3" goal="Analyze cross-epic dependencies">
<action>Perform dependency analysis across all loaded epics:</action>

**3.1 Explicit Dependencies**
- Check each epic for `## Dependencies` section
- Parse references like "Depends on Epic 36" or "Requires 36-3 complete"
- Build explicit dependency graph

**3.2 Implicit Dependencies (Pattern Detection)**

Scan story content for shared resources:

| Pattern | Detection Method | Dependency Type |
|---------|------------------|-----------------|
| Database tables | Look for `CREATE TABLE`, model names, migrations | Schema dependency |
| API endpoints | Look for `/api/`, route definitions | API dependency |
| Components | Look for `import` from shared paths | Code dependency |
| Configuration | Look for env vars, feature flags | Config dependency |
| Types/Interfaces | Look for shared type definitions | Type dependency |

**3.3 Build Dependency Matrix**

```
Epic    | Depends On | Required By
--------|------------|------------
36      | -          | 37, 38
37      | 36         | 38
38      | 36, 37     | -
```

<output>dependency_graph with edges and reasons</output>
</step>

<step n="4" goal="Determine optimal execution order">
<action>Using dependency graph, determine execution order:</action>

**4.1 Topological Sort**
- Epics with no dependencies execute first
- Epics are ordered so dependencies are satisfied
- Circular dependencies → error and ask user to resolve

**4.2 Story-Level Ordering (within epic)**
- Stories execute in numerical order by default
- Detect story-level dependencies if specified
- Identify parallelizable stories (no shared resources)

**4.3 Risk Assessment**

For each epic/story, assess complexity:
- **High**: Multiple integrations, new patterns, security-sensitive
- **Medium**: Extends existing patterns, moderate scope
- **Low**: Simple CRUD, isolated changes

<output>execution_order list with risk annotations</output>
</step>

<step n="5" goal="Identify cross-cutting concerns">
<action>Detect concerns that span multiple epics:</action>

**5.1 Database Migrations**
- If multiple epics modify schema, flag migration order requirements
- Recommend: Run all migrations before story execution, or sequence carefully

**5.2 API Versioning**
- If epics add/modify APIs, check for versioning consistency
- Flag breaking changes that affect other epics

**5.3 Shared Component Changes**
- If early epic modifies shared code, flag impact on later epics
- Recommend: Review shared code changes before proceeding

**5.4 Test Dependencies**
- If tests in later epics depend on fixtures from earlier epics
- Recommend: Ensure test data setup is consistent

<output>cross_cutting_concerns list with recommendations</output>
</step>

<step n="6" goal="Identify parallel execution opportunities">
<action>Find stories that can execute in parallel:</action>

**Within an epic:**
- Stories with no shared files or dependencies
- Stories that only read (don't modify) shared resources
- Stories flagged as `parallel-safe` in story file

**Across epics (advanced):**
- Independent epics with no dependency relationship
- Requires `--parallel-epics` flag to enable

<output>parallel_opportunities list</output>
</step>

<step n="7" goal="Generate chain plan document">
<action>Create chain-plan.yaml with all analysis results:</action>

```yaml
# chain-plan.yaml
generated: {date}
epics: [{epic_ids}]
total_stories: {story_count}
analysis_depth: {analysis_depth}

execution_order:
  - epic: {id}
    title: "{epic_title}"
    stories: [{story_ids}]
    story_count: {count}
    estimated_complexity: {low|medium|high}
    dependencies: []
    # OR
    dependencies:
      - epic: {dep_id}
        reason: "{why}"

cross_cutting_concerns:
  - name: "{concern_name}"
    affects: [{epic_ids}]
    recommendation: "{action}"

parallel_opportunities:
  - scope: "within-epic"
    epic: {id}
    stories: [{story_ids}]
    reason: "{why_parallel}"

risk_areas:
  - epic: {id}
    story: "{story_id}"
    risk: "{description}"
    severity: {low|medium|high}
    mitigation: "{recommendation}"

estimated_execution:
  total_stories: {count}
  complex_stories: {count}
  low_risk_stories: {count}
```

<action>Save to {chain_plan_file}</action>
</step>

<step n="8" goal="Present analysis and get approval">
<action>Display formatted analysis to {user_name}:</action>

```
═══════════════════════════════════════════════════════════
                    EPIC CHAIN ANALYSIS
═══════════════════════════════════════════════════════════

Epics: {epic_list}
Total Stories: {total_stories}

EXECUTION ORDER
───────────────────────────────────────────────────────────
{For each epic in execution_order:}
{n}. Epic {id}: {title} ({story_count} stories)
   Dependencies: {deps or "None"}
   Complexity: {complexity}
{end for}

CROSS-CUTTING CONCERNS
───────────────────────────────────────────────────────────
{For each concern:}
• {name}
  Affects: {epic_ids}
  Action: {recommendation}
{end for}

RISK AREAS
───────────────────────────────────────────────────────────
{For each risk:}
• Story {story_id}: {risk}
  Severity: {severity}
  Mitigation: {mitigation}
{end for}

═══════════════════════════════════════════════════════════
```

<action>Ask user to choose:</action>
1. **Approve** - Proceed with execution
2. **Modify** - Change order or exclude epics
3. **Analyze Only** - Save plan, don't execute
4. **Cancel** - Abort workflow

<on-user-choice name="Approve">Proceed to step 9</on-user-choice>
<on-user-choice name="Modify">Return to step 1 with modifications</on-user-choice>
<on-user-choice name="Analyze Only">Save plan, display shell command for later, end workflow</on-user-choice>
<on-user-choice name="Cancel">End workflow</on-user-choice>
</step>

<step n="9" goal="Provide execution command">
<action>Display the shell command for execution:</action>

**The epic chain requires shell orchestration for context isolation.**

Provide commands:

```bash
# Dry run (recommended first)
./.bmad/scripts/epic-chain.sh {epic_ids} --dry-run --verbose

# Full execution
./.bmad/scripts/epic-chain.sh {epic_ids}

# With specific options
./.bmad/scripts/epic-chain.sh {epic_ids} --skip-done --verbose
```

<action>Explain what will happen:</action>

1. For each epic in order:
   - Load context handoff from previous epic (if any)
   - Execute via `epic-execute.sh` (dev → review → commit per story)
   - Generate context handoff for next epic

2. After all epics:
   - Generate combined UAT document
   - Update sprint-status.yaml
   - Display execution summary

<action>Remind user:</action>
- Use `--dry-run` first to validate
- Use `--start-from {epic_id}` to resume after interruption
- Use `--skip-done` to skip already-completed stories
- Check logs at `{chain_log_file}` if issues occur
</step>

</workflow>

## Context Handoff Template

After each epic completes, generate handoff:

```markdown
# Epic {id} → Epic {next_id} Handoff

## Generated
{timestamp}

## Patterns Established
{List coding patterns, conventions, architectural decisions made}

## Key Decisions
{Major technical decisions with rationale}

## Gotchas & Lessons Learned
{Issues encountered, workarounds applied, things to watch for}

## Files to Reference
{Key files that establish patterns for next epic}

## Test Patterns
{Testing conventions, fixture patterns, coverage expectations}
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Epic not found | Report missing epic, ask user to correct |
| Circular dependency | Report cycle, ask user to resolve |
| Story execution fails | Log failure, continue to next story, report in summary |
| Epic fails completely | Pause chain, ask user whether to continue or abort |
| Context handoff fails | Log warning, continue without handoff |

---

## Report Generation

After chain completion, generate an execution report using step 10:

<step n="10" goal="Generate chain execution report">
<action>Load step file: `{installed_path}/steps/step-10-generate-report.md`</action>

This step:
1. Loads metrics from `{metrics_folder}/epic-{id}-metrics.yaml` for each epic
2. Aggregates timing, story counts, issues, and UAT results
3. Builds dependency graph visualization
4. Calculates token/cost estimates
5. Renders the report template
6. Saves to `{chain_report_file}`

**Trigger manually:** `*chain-report` or `*CR`

**Output:** `{sprint_artifacts}/chain-execution-report.md`
</step>

## Metrics Collection

During epic execution, metrics are collected to `{metrics_folder}/epic-{id}-metrics.yaml`:

| Metric | Source | Description |
|--------|--------|-------------|
| Timing | Shell script | Start/end timestamps per epic |
| Story counts | Story file status | Completed/failed/skipped counts |
| UAT results | uat-validate | Gate status, fix attempts |
| Issues | Dev/review phases | Problems encountered |
| Git info | git log | Commit counts, SHAs |

See `templates/epic-metrics-template.yaml` for full schema.
