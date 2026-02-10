# Step 5: Report Results

## Purpose

Update metrics files with validation results and output parseable signals for orchestration scripts (epic-chain.sh) to consume.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| gate_status | Step 4 | Yes |
| results | Step 3 | Yes |
| passed_count | Step 3 | Yes |
| failed_count | Step 3 | Yes |
| fix_attempts | State | Yes |
| epic_id | CLI | Yes |
| metrics_dir | Config | Yes |

## Process

### 5.1 Update Metrics File

Update or create metrics file at:
```
{metrics_dir}/epic-{epic_id}-metrics.yaml
```

#### 5.1.1 Using yq (if available)

```bash
yq -i '.validation.gate_executed = true' "$metrics_file"
yq -i '.validation.gate_status = "PASS"' "$metrics_file"
yq -i '.validation.gate_mode = "quick"' "$metrics_file"
yq -i '.validation.fix_attempts = 0' "$metrics_file"
yq -i '.validation.scenarios_passed = 5' "$metrics_file"
yq -i '.validation.scenarios_failed = 1' "$metrics_file"
yq -i '.validation.timestamp = "2026-01-05T17:30:00Z"' "$metrics_file"
```

#### 5.1.2 Fallback (no yq)

Create or append validation section:

```yaml
validation:
  gate_executed: true
  gate_mode: "quick"
  timestamp: "2026-01-05T17:30:00Z"
  results:
    passed: 5
    failed: 1
    skipped: 3
  gate_status: "PASS"
  fix_attempts: 0
```

#### 5.1.3 Record Blocking Issues (if failed)

```yaml
validation:
  # ... other fields ...
  blocking_issues:
    - scenario_id: 3
      name: "Database Migration"
      error: "relation 'events' does not exist"
      command: "npx heimdall db migrate"
```

#### 5.1.4 Record Fix History (if self-healing occurred)

```yaml
validation:
  # ... other fields ...
  fix_history:
    - attempt: 1
      timestamp: "2026-01-05T17:35:00Z"
      failed_scenarios: ["scenario-3"]
      fix_context: "docs/sprint-artifacts/uat-fixes/epic-1-fix-context-1.md"
      result: "partial"
    - attempt: 2
      timestamp: "2026-01-05T17:42:00Z"
      failed_scenarios: []
      result: "success"
```

### 5.2 Output Parseable Signals

Print to stdout in format that epic-chain.sh can parse:

```bash
# Always output these signals
echo "UAT_GATE_RESULT: $gate_status"
echo "UAT_FIX_ATTEMPTS: $fix_attempts"
echo "UAT_SCENARIOS_PASSED: $passed_count/$total_count"
```

**Additional signals on failure:**

```bash
echo "UAT_FIX_REQUIRED: true"
echo "UAT_FIX_CONTEXT: $fix_context_file"
```

**Additional signals on max retries:**

```bash
echo "UAT_MAX_RETRIES: true"
echo "UAT_HALT_CHAIN: true"
```

### 5.3 Set Exit Code

| Status | Exit Code | Meaning |
|--------|-----------|---------|
| PASS | 0 | All scenarios passed |
| FAIL (fixable) | 1 | Failed but retries remain or self-heal disabled |
| FAIL (max retries) | 2 | Max retries exceeded, chain should halt |

### 5.4 Print Human-Readable Summary

```
═══════════════════════════════════════════════════════════
                 UAT VALIDATION COMPLETE
═══════════════════════════════════════════════════════════

  Epic:              1
  Gate Mode:         quick
  Gate Result:       PASS

  Scenarios:
    Automatable:     6
    Semi-automated:  2
    Manual:          1

  Results:
    Passed:          6
    Failed:          0
    Fix Attempts:    0

  Artifacts:
    Log:             /tmp/bmad-uat-validate-12345.log
    UAT Document:    docs/uat/epic-1-uat.md
    Metrics:         docs/sprint-artifacts/metrics/epic-1-metrics.yaml

═══════════════════════════════════════════════════════════
```

### 5.5 Failure Summary (if applicable)

```
═══════════════════════════════════════════════════════════
                 UAT VALIDATION FAILED
═══════════════════════════════════════════════════════════

  Epic:              1
  Gate Mode:         quick
  Gate Result:       FAIL

  Scenarios:
    Automatable:     6
    Semi-automated:  2
    Manual:          1

  Results:
    Passed:          5
    Failed:          1
    Fix Attempts:    2

  Blocking Issues:
    - Scenario 3: Database Migration
      Error: relation 'events' does not exist

  Fix Context:
    docs/sprint-artifacts/uat-fixes/epic-1-fix-context-2.md

  Action Required:
    Manual intervention needed - max retries exceeded

═══════════════════════════════════════════════════════════
```

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| Updated metrics | YAML file | Validation results persisted |
| Signals | stdout | Parseable output for orchestration |
| Summary | stdout | Human-readable summary |
| Exit code | Process | 0=pass, 1=fail-fixable, 2=fail-max-retries |

## Completion Signal

```
RESULTS_REPORTED: {metrics_file_path}
```

## Signal Reference

### For Orchestration Scripts

| Signal | Values | Description |
|--------|--------|-------------|
| `UAT_GATE_RESULT` | PASS, FAIL | Overall gate status |
| `UAT_FIX_ATTEMPTS` | 0-N | Number of fix attempts made |
| `UAT_SCENARIOS_PASSED` | X/Y | Passed/Total ratio |
| `UAT_FIX_REQUIRED` | true | Indicates fixes were needed |
| `UAT_FIX_CONTEXT` | path | Location of fix context doc |
| `UAT_MAX_RETRIES` | true | Max retries exceeded |
| `UAT_HALT_CHAIN` | true | Chain should stop |

### Parsing in Shell

```bash
# In epic-chain.sh
uat_output=$("$SCRIPT_DIR/uat-validate.sh" "$epic_id" 2>&1)

if echo "$uat_output" | grep -q "UAT_GATE_RESULT: PASS"; then
    log_success "UAT passed"
else
    log_error "UAT failed"

    if echo "$uat_output" | grep -q "UAT_HALT_CHAIN: true"; then
        log_error "Halting chain - max retries exceeded"
        exit 2
    fi
fi
```

## Error Handling

| Error | Action |
|-------|--------|
| Metrics file write fails | Log warning, continue with signal output |
| yq not available | Use fallback append method |
| Invalid metrics file | Create new file with validation section |
