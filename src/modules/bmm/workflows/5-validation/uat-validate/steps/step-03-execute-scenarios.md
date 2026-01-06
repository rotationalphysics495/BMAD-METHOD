# Step 3: Execute Scenarios

## Purpose

Run automatable scenarios via shell commands, capture results, and determine pass/fail status for each.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| automatable | Step 2 | Yes |
| semi_automated | Step 2 | For full gate mode |
| gate_mode | CLI | Yes (quick/full/skip) |
| timeout | Config | No (default: 30s) |

## Process

### 3.1 Filter by Gate Mode

| Mode | Scenarios Executed |
|------|-------------------|
| `quick` | Automatable only |
| `full` | Automatable + Semi-automated |
| `skip` | None (gate passes automatically) |

**Skip mode behavior:**
```
[UAT] Gate mode: skip - bypassing scenario execution
UAT_GATE_RESULT: PASS
UAT_SCENARIOS_PASSED: 0/0 (skipped)
```

### 3.2 Handle Empty Scenario List

If no scenarios to execute:
```
[UAT] No automatable scenarios found - gate passes by default
UAT_GATE_RESULT: PASS
UAT_SCENARIOS_PASSED: 0/0 (none automatable)
```

### 3.3 Execute Each Scenario

For each scenario in the execution list:

#### 3.3.1 Extract Command

```bash
# From scenario object
command="${scenario.command}"

# If no command extracted, mark as failed
if [ -z "$command" ]; then
    status="FAIL"
    error="No automatable command found"
fi
```

#### 3.3.2 Execute with Timeout

```bash
# Using GNU timeout
output=$(timeout $TIMEOUT_SECONDS bash -c "$command" 2>&1)
exit_code=$?

# macOS fallback (perl-based timeout)
output=$(perl -e 'alarm shift @ARGV; exec @ARGV' $TIMEOUT_SECONDS bash -c "$command" 2>&1)
exit_code=$?
```

#### 3.3.3 Capture Results

Record for each execution:
- **stdout**: Command output
- **stderr**: Error output (captured via 2>&1)
- **exit_code**: Process exit code
- **duration_ms**: Execution time in milliseconds
- **status**: PASS or FAIL

### 3.4 Result Evaluation Rules

| Condition | Result | Notes |
|-----------|--------|-------|
| Exit code 0 | PASS | Command succeeded |
| Exit code 124 | FAIL (timeout) | Exceeded timeout limit |
| Exit code 127 | FAIL (not found) | Command not found |
| Exit code non-zero | FAIL (error) | Command failed |

### 3.5 Expected Output Matching (Optional)

If scenario has `expected_result`, apply flexible matching:

**Contains match** (default):
```bash
if echo "$output" | grep -qi "$expected"; then
    match="true"
fi
```

**Exit code only match:**
```bash
# If expected contains "exit 0" or "returns 0"
if [ $exit_code -eq 0 ]; then
    match="true"
fi
```

**Note:** Output matching is advisory. Primary pass/fail is based on exit code.

### 3.6 Record Execution Results

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

### 3.7 Progress Output

During execution, output progress:

```
[UAT] Executing 6 scenarios...

Scenario 1: Project Initialization
  Command: npx heimdall --version
  [PASS] (1250ms)

Scenario 2: Configuration Setup
  Command: npx heimdall config validate
  [PASS] (890ms)

Scenario 3: Database Migration
  Command: npx heimdall db migrate
  [FAIL] (3400ms)
    Error: relation 'events' does not exist
```

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| results | Array | Per-scenario execution results |
| passed_count | State | Number of passed scenarios |
| failed_count | State | Number of failed scenarios |
| failed_details | Array | Details for failed scenarios |

## Completion Signal

```
SCENARIOS_EXECUTED: {passed}/{total}
```

## Error Handling

| Error | Action |
|-------|--------|
| Command not found | Record as FAIL with "command not found" message |
| Timeout exceeded | Record as FAIL with "timeout after Xs" message |
| Permission denied | Record as FAIL with permission error |
| Shell syntax error | Record as FAIL with syntax error details |

## Example Complete Output

```
[UAT] Executing 6 scenarios (gate mode: quick)

Scenario 1: Project Initialization
  [PASS] npx heimdall --version (1250ms)

Scenario 2: Configuration Setup
  [PASS] npx heimdall config validate (890ms)

Scenario 3: Database Migration
  [FAIL] npx heimdall db migrate (3400ms)
    Error: relation 'events' does not exist

Scenario 4: Connection Validation
  [PASS] npx heimdall db status (450ms)

Scenario 5: Worker Process Startup
  [PASS] npx heimdall worker --check (2100ms)

Scenario 6: Job Queue Testing
  [PASS] npx heimdall queue test (1800ms)

SCENARIOS_EXECUTED: 5/6
```
