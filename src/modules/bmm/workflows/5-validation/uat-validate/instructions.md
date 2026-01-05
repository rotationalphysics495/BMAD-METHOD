# UAT Validate Workflow Instructions

## Purpose

Execute User Acceptance Testing scenarios against a completed epic to validate that implementations meet acceptance criteria. On failure, generate fix context for the self-healing quick-dev loop.

## Workflow Overview

```
Load UAT Doc → Classify Scenarios → Execute Automatable → Evaluate Gate → Report/Fix
```

---

## Phase 1: Load and Classify

### 1.1 Load UAT Document

Load the UAT document from `{uat_docs_location}/epic-{epic_id}-uat.md`.

**Required sections to parse:**
- Test Scenarios (numbered list with steps)
- Success Criteria (checkbox items)
- Prerequisites (environment requirements)

### 1.2 Classify Each Scenario

For each test scenario, classify based on indicators:

| Classification | Indicators | Action |
|----------------|------------|--------|
| **Automatable** | `npx`, `npm run`, `curl`, `--version`, `/health`, `db status`, `config validate` | Execute via shell |
| **Semi-automated** | `test-send`, `email`, `inbox`, `check your` | Execute + flag for manual verify |
| **Manual only** | `Railway`, `dashboard`, `browser`, `two terminal`, `visual` | Skip, add to checklist |

### 1.3 Output Classification Summary

```yaml
scenarios:
  total: 9
  automatable: 6
  semi_automated: 2
  manual_only: 1

automatable_scenarios:
  - id: 1
    name: "Project Initialization"
    command: "npx heimdall --version"
    expected: "displays a version number"
  - id: 3
    name: "Database Migration"
    command: "npx heimdall db migrate"
    expected: "success message"
  # ...
```

---

## Phase 2: Execute Scenarios

### 2.1 Execute Each Automatable Scenario

For each automatable scenario:

1. **Extract command** from scenario steps (look for code blocks or CLI references)
2. **Set timeout** based on `{timeout_per_scenario}` (default: 30s)
3. **Execute command** via shell
4. **Capture output** (stdout, stderr, exit code)
5. **Evaluate result** against expected outcome

### 2.2 Result Evaluation Rules

| Condition | Result |
|-----------|--------|
| Exit code 0 + output matches expected | PASS |
| Exit code 0 + output doesn't match | FAIL (unexpected output) |
| Exit code non-zero | FAIL (command error) |
| Timeout exceeded | FAIL (timeout) |
| Command not found | FAIL (missing dependency) |

### 2.3 Expected Output Matching

Use flexible matching:
- **Contains match**: Expected text appears anywhere in output
- **Regex match**: Pattern matches output
- **Exit code only**: Just verify success (exit 0)

Example matching rules:
```yaml
- scenario: "Database Migration"
  command: "npx heimdall db migrate"
  match_type: "contains"
  expected: ["initialized successfully", "migration complete", "already up to date"]
  # PASS if any of these appear in output
```

### 2.4 Record Execution Results

```yaml
execution_results:
  - scenario_id: 1
    name: "Project Initialization"
    command: "npx heimdall --version"
    status: "PASS"
    exit_code: 0
    output: "1.0.0"
    duration_ms: 1250

  - scenario_id: 3
    name: "Database Migration"
    command: "npx heimdall db migrate"
    status: "FAIL"
    exit_code: 1
    output: ""
    stderr: "Error: relation 'events' does not exist"
    duration_ms: 3400
```

---

## Phase 3: Evaluate Gate

### 3.1 Determine Gate Status

**Gate Mode: Quick** (default)
- Only evaluate automatable scenarios
- All automatable must pass for GATE_PASS

**Gate Mode: Full**
- Evaluate automatable + semi-automated
- Semi-automated failures are warnings, not blockers

### 3.2 Gate Decision Logic

```
if all_automatable_passed:
    GATE_RESULT = PASS
else:
    GATE_RESULT = FAIL
    if self_heal_enabled and attempts < max_retries:
        generate_fix_context()
        trigger_quick_dev()
    elif attempts >= max_retries:
        halt_chain()
```

### 3.3 Generate Fix Context (On Failure)

When gate fails, create fix context document at `{fix_context_file}`:

**Include for each failure:**
1. Scenario ID and name
2. Command that was executed
3. Expected result
4. Actual result (stdout/stderr)
5. Exit code
6. Related story ID (if determinable)
7. Acceptance criteria from story

**Use template:** `{installed_path}/uat-fix-context-template.md`

---

## Phase 4: Report Results

### 4.1 Update Metrics File

Update or create `{metrics_file}` with validation results:

```yaml
validation:
  gate_executed: true
  gate_mode: "quick"
  timestamp: "{date}"
  results:
    passed: 5
    failed: 1
    skipped: 3
  gate_status: "FAIL"
  blocking_issues:
    - scenario_id: 3
      name: "Database Migration"
      error: "relation 'events' does not exist"

  fix_attempts: 1
  fix_history:
    - attempt: 1
      timestamp: "{date}"
      failed_scenarios: ["scenario-3"]
      fix_context: "docs/sprint-artifacts/uat-fix-context-1-1.md"
      result: "pending"
```

### 4.2 Output Gate Result

Output in parseable format for orchestration scripts:

```
UAT_GATE_RESULT: FAIL
CRITICAL_PASSED: 5/6
BLOCKING_ISSUES: [scenario-3]
FIX_CONTEXT: docs/sprint-artifacts/uat-fix-context-1-1.md
FIX_ATTEMPT: 1/2
```

### 4.3 Console Summary

Also output human-readable summary:

```
UAT Validation Results - Epic 1
================================

Scenarios Executed: 6/9
  - Automatable: 6 (executed)
  - Semi-automated: 2 (flagged for manual)
  - Manual only: 1 (skipped)

Results:
  ✓ Scenario 1: Project Initialization - PASS
  ✓ Scenario 2: Configuration Setup - PASS
  ✗ Scenario 3: Database Migration - FAIL
    Error: relation 'events' does not exist
  ✓ Scenario 4: Connection Validation - PASS
  ✓ Scenario 5: Worker Process Startup - PASS
  ✓ Scenario 6: Job Queue Testing - PASS

Gate Status: FAIL (5/6 passed)
Initiating self-healing fix loop (attempt 1/2)...
Fix context generated: docs/sprint-artifacts/uat-fix-context-1-1.md
```

---

## Self-Healing Integration

### Triggering Quick Dev

When gate fails and `self_heal_enabled: true`:

1. Generate fix context document
2. Invoke quick-dev workflow with fix context as input
3. After quick-dev completes, re-run UAT validate
4. Repeat until PASS or max_retries reached

### Orchestration Script Signal

For shell orchestration, output these signals:

```bash
# On PASS
echo "UAT_GATE_RESULT: PASS"
exit 0

# On FAIL with fix attempt
echo "UAT_GATE_RESULT: FAIL"
echo "UAT_FIX_REQUIRED: true"
echo "UAT_FIX_CONTEXT: {path}"
exit 1

# On FAIL after max retries
echo "UAT_GATE_RESULT: FAIL"
echo "UAT_MAX_RETRIES: true"
echo "UAT_HALT_CHAIN: true"
exit 2
```

---

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `gate_mode` | `quick` | Which scenarios to evaluate (quick/full/skip) |
| `timeout_per_scenario` | `30` | Seconds before scenario timeout |
| `self_heal_enabled` | `true` | Trigger quick-dev on failure |
| `max_retries` | `2` | Fix attempts before halting |
| `on_max_retries` | `halt` | Action when max retries exceeded |

---

## Error Handling

| Error | Action |
|-------|--------|
| UAT document not found | FAIL with clear error message |
| No automatable scenarios | WARN, gate passes (nothing to validate) |
| All scenarios manual | WARN, generate manual checklist, gate passes |
| Scenario command unclear | Skip scenario, log warning |
| Shell execution fails | Record as FAIL with error details |
