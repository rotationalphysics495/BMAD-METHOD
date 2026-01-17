# UAT Workflow Implementation Plan

**Date:** 2026-01-05
**Source:** `docs/improvements/uat-workflow-implementation-gaps.md`
**Scope:** All gaps (P0, P1, P2)

---

## Overview

Implement all gaps identified in the UAT workflow implementation gaps analysis to make the UAT validation workflow and epic chain report generator production-ready.

**Current State:** Workflow definitions, templates, and agent triggers exist
**Missing:** Shell orchestration, metrics collection, step files, and integration points

---

## Files to Create

| File | Priority | Lines (est) |
|------|----------|-------------|
| `scripts/uat-validate.sh` | P0 | ~350 |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-01-load-uat.md` | P2 | ~60 |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-02-classify-scenarios.md` | P2 | ~50 |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-03-execute-scenarios.md` | P2 | ~70 |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-04-evaluate-gate.md` | P2 | ~60 |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-05-report-results.md` | P2 | ~50 |

## Files to Modify

| File | Priority | Changes |
|------|----------|---------|
| `scripts/epic-execute.sh` | P0 | Add metrics collection (~60 lines) |
| `scripts/epic-chain.sh` | P1 | Add UAT gate + report generation (~100 lines) |

---

## Implementation Steps

### Step 1: Create `scripts/uat-validate.sh` [P0]

**Purpose:** Shell orchestration for UAT validation with self-healing loop

**Structure (following epic-execute.sh patterns):**

```
Section 1: Configuration (lines 1-50)
  - Script/project paths
  - Color codes
  - Default values: UAT_GATE_MODE=quick, MAX_RETRIES=2

Section 2: Helper Functions (lines 51-90)
  - log(), log_success(), log_error(), log_warn()
  - Log to /tmp/bmad-uat-validate-$$.log

Section 3: Argument Parsing (lines 91-140)
  - Required: <epic_id>
  - Flags: --gate-mode=quick|full|skip, --max-retries=N, --skip-manual, --verbose, --dry-run

Section 4: UAT Document Loading (lines 141-180)
  - Find: docs/uat/epic-{id}-uat.md
  - Parse scenario blocks

Section 5: Scenario Classification (lines 181-230)
  - Automatable: contains npx, npm run, curl, pytest, etc.
  - Semi-auto: requires setup then command
  - Manual: no detectable command

Section 6: Scenario Execution (lines 231-280)
  - Execute automatable scenarios with timeout
  - Capture exit code + output
  - Record pass/fail results

Section 7: Gate Evaluation (lines 281-320)
  - If all passed: output UAT_GATE_RESULT: PASS, exit 0
  - If failed: generate fix context, attempt self-healing

Section 8: Self-Healing Loop (lines 321-380)
  - Generate fix context doc at: docs/sprint-artifacts/uat-fixes/epic-{id}-fix-context-{attempt}.md
  - Spawn fresh Claude for quick-dev fixes
  - Re-validate in new iteration
  - Loop until pass or max_retries

Section 9: Output Signals (lines 381-400)
  - UAT_GATE_RESULT: PASS|FAIL
  - UAT_FIX_ATTEMPTS: N
  - UAT_SCENARIOS_PASSED: X/Y
  - Exit codes: 0=pass, 1=fail-fixable, 2=max-retries-exceeded
```

**Key Functions:**

```bash
load_uat_document()      # Parse UAT doc, extract scenarios
classify_scenario()      # Return: automatable|semi-auto|manual
execute_scenario()       # Run command, capture result
evaluate_gate()          # Determine pass/fail
generate_fix_context()   # Create fix context doc from template
run_quick_dev_fix()      # Spawn fresh Claude session for fixes
```

**Interface:**

```bash
# Usage
./scripts/uat-validate.sh <epic_id> [options]

# Options
--gate-mode=quick|full|skip    # Which scenarios to run
--max-retries=2                # Fix attempts before halt
--skip-manual                  # Skip manual-only scenarios
--verbose                      # Detailed output
--dry-run                      # Show what would run

# Output signals (for epic-chain.sh to parse)
UAT_GATE_RESULT: PASS|FAIL
UAT_FIX_ATTEMPTS: N
UAT_SCENARIOS_PASSED: X/Y
```

---

### Step 2: Add Metrics Instrumentation to `scripts/epic-execute.sh` [P0]

**Location:** Modify existing file

**Add at epic start (~line 145, after directory setup):**

```bash
# Initialize metrics file
METRICS_DIR="$SPRINT_ARTIFACTS_DIR/metrics"
METRICS_FILE="$METRICS_DIR/epic-${EPIC_ID}-metrics.yaml"
mkdir -p "$METRICS_DIR"
EPIC_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EPIC_START_SECONDS=$(date +%s)

cat > "$METRICS_FILE" << EOF
epic_id: "$EPIC_ID"
execution:
  start_time: "$EPIC_START_TIME"
  end_time: ""
  duration_seconds: 0
stories:
  total: 0
  completed: 0
  failed: 0
  skipped: 0
validation:
  gate_executed: false
  gate_status: "PENDING"
  fix_attempts: 0
issues: []
EOF
```

**Add helper function (~line 65):**

```bash
update_story_metrics() {
    local status="$1"  # completed|failed|skipped
    case "$status" in
        completed) yq -i '.stories.completed += 1' "$METRICS_FILE" ;;
        failed)    yq -i '.stories.failed += 1' "$METRICS_FILE" ;;
        skipped)   yq -i '.stories.skipped += 1' "$METRICS_FILE" ;;
    esac
}
```

**Call after each story completion in main loop:**

```bash
update_story_metrics "completed"  # or failed/skipped based on result
```

**Add at epic end (~line 400, before summary):**

```bash
# Finalize metrics
EPIC_END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$(($(date +%s) - EPIC_START_SECONDS))
yq -i ".execution.end_time = \"$EPIC_END_TIME\"" "$METRICS_FILE"
yq -i ".execution.duration_seconds = $DURATION" "$METRICS_FILE"
yq -i ".stories.total = ${#STORIES[@]}" "$METRICS_FILE"
```

---

### Step 3: Integrate UAT Gate into `scripts/epic-chain.sh` [P1]

**Add configuration variables (~line 42):**

```bash
# UAT Gate Configuration
UAT_GATE_ENABLED="${UAT_GATE_ENABLED:-true}"
UAT_GATE_MODE="${UAT_GATE_MODE:-quick}"
UAT_MAX_RETRIES="${UAT_MAX_RETRIES:-2}"
UAT_BLOCKING="${UAT_BLOCKING:-false}"
```

**Add CLI flags (~line 120):**

```bash
--uat-gate=*)
    UAT_GATE_MODE="${1#*=}"
    shift
    ;;
--uat-blocking)
    UAT_BLOCKING=true
    shift
    ;;
--no-uat)
    UAT_GATE_ENABLED=false
    shift
    ;;
```

**Add UAT gate phase after epic completion (~line 320, after epic-execute succeeds):**

```bash
# Run UAT validation if enabled
if [ "$UAT_GATE_ENABLED" = true ]; then
    log_section "UAT Validation Gate: Epic $epic_id"

    uat_result=$("$SCRIPT_DIR/uat-validate.sh" "$epic_id" \
        --gate-mode="$UAT_GATE_MODE" \
        --max-retries="$UAT_MAX_RETRIES" 2>&1) || true

    # Parse result
    if echo "$uat_result" | grep -q "UAT_GATE_RESULT: PASS"; then
        log_success "UAT validation passed for Epic $epic_id"
        # Update metrics
        yq -i '.validation.gate_executed = true' "$METRICS_FILE"
        yq -i '.validation.gate_status = "PASS"' "$METRICS_FILE"
    else
        log_error "UAT validation failed for Epic $epic_id"
        yq -i '.validation.gate_executed = true' "$METRICS_FILE"
        yq -i '.validation.gate_status = "FAIL"' "$METRICS_FILE"

        if [ "$UAT_BLOCKING" = true ]; then
            log_error "UAT blocking enabled - halting chain"
            exit 1
        else
            log_warn "UAT blocking disabled - continuing to next epic"
        fi
    fi
fi
```

---

### Step 4: Integrate Report Generation into `scripts/epic-chain.sh` [P1]

**Add configuration (~line 45):**

```bash
GENERATE_REPORT="${GENERATE_REPORT:-true}"
CHAIN_REPORT_FILE="$SPRINT_ARTIFACTS_DIR/chain-execution-report.md"
METRICS_DIR="$SPRINT_ARTIFACTS_DIR/metrics"
```

**Add CLI flag (~line 130):**

```bash
--no-report)
    GENERATE_REPORT=false
    shift
    ;;
```

**Add report generation after all epics (~line 400, before final summary):**

```bash
# Generate chain execution report
if [ "$GENERATE_REPORT" = true ] && [ "$DRY_RUN" = false ]; then
    log_section "Generating Chain Execution Report"

    INSTALLED_PATH="$BMAD_DIR/bmm/workflows/4-implementation/epic-chain"

    report_prompt="You are Bob, the Scrum Master.

Execute the chain report generation workflow:
- Step file: $INSTALLED_PATH/steps/step-10-generate-report.md
- Metrics folder: $METRICS_DIR
- Chain plan: $CHAIN_PLAN_FILE
- Output to: $CHAIN_REPORT_FILE

Generate the complete execution report."

    claude --dangerously-skip-permissions -p "$report_prompt" || true

    if [ -f "$CHAIN_REPORT_FILE" ]; then
        log_success "Report generated: $CHAIN_REPORT_FILE"
        git add "$CHAIN_REPORT_FILE" 2>/dev/null || true
    else
        log_warn "Report generation did not produce output"
    fi
fi
```

---

### Step 5: Create UAT Validation Step Files [P2]

**Directory:** `src/modules/bmm/workflows/5-validation/uat-validate/steps/`

#### step-01-load-uat.md

```markdown
# Step 1: Load UAT Document

## Purpose
Load and validate the UAT document for the specified epic.

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| epic_id | CLI argument | Yes |
| uat_dir | Configuration | Yes |

## Process

### 1.1 Locate UAT Document
Search for UAT document at: `{uat_dir}/epic-{epic_id}-uat.md`

### 1.2 Validate Structure
Confirm document contains:
- ## Acceptance Criteria or ## Scenarios section
- At least one scenario block

### 1.3 Parse Scenarios
Extract scenario blocks with:
- Scenario ID/Title
- Given/When/Then steps
- Verification command (if present)
- Expected result

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| scenario_list | Memory | Parsed scenario objects |
| scenario_count | Console | Number of scenarios found |

## Completion Signal
UAT_LOADED: {scenario_count}

## Error Handling
| Error | Action |
|-------|--------|
| File not found | Exit 1 with clear message |
| Invalid structure | Exit 1 with parsing error |
```

#### step-02-classify-scenarios.md

```markdown
# Step 2: Classify Scenarios

## Purpose
Categorize scenarios by their executability level.

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| scenario_list | Step 1 | Yes |

## Process

### 2.1 Detect Automatable Scenarios
Keywords that indicate automatability:
- npx, npm run, yarn
- curl, wget, http
- pytest, jest, vitest
- /health, /api/
- exit code, returns

### 2.2 Detect Semi-Automated
Scenarios with commands that require setup:
- "Start the server first"
- "Ensure database is running"
- Manual setup + automated verification

### 2.3 Classify as Manual
No detectable command or automation path.

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| automatable | Array | Scenarios to execute |
| semi_auto | Array | Scenarios needing setup |
| manual | Array | Human verification required |

## Completion Signal
SCENARIOS_CLASSIFIED: {auto}/{semi}/{manual}
```

#### step-03-execute-scenarios.md

```markdown
# Step 3: Execute Scenarios

## Purpose
Run automatable scenarios via shell commands.

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| automatable | Step 2 | Yes |
| gate_mode | CLI | Yes (quick/full) |
| timeout | Config | No (default: 30s) |

## Process

### 3.1 Filter by Gate Mode
- quick: Execute only critical/blocking scenarios
- full: Execute all automatable scenarios
- skip: Return success without execution

### 3.2 Execute Each Scenario
For each scenario:
1. Extract command from verification step
2. Execute with timeout: `timeout {seconds} {command}`
3. Capture exit code and output
4. Record result: PASS (exit 0) or FAIL (exit non-zero)

### 3.3 Handle Execution Errors
- Command not found: Record as FAIL with clear message
- Timeout exceeded: Record as FAIL with timeout note
- Unexpected error: Record as FAIL with stderr

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| results | Array | {scenario_id, status, output, exit_code} |
| passed_count | Console | Scenarios that passed |
| failed_count | Console | Scenarios that failed |

## Completion Signal
SCENARIOS_EXECUTED: {passed}/{total}
```

#### step-04-evaluate-gate.md

```markdown
# Step 4: Evaluate Gate

## Purpose
Determine pass/fail status and trigger self-healing if needed.

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| results | Step 3 | Yes |
| max_retries | CLI | Yes |
| current_attempt | State | Yes |

## Process

### 4.1 Check All Results
If all automatable scenarios passed:
- Set gate_status = PASS
- Skip to Step 5

### 4.2 Handle Failures
If any scenario failed:
- Collect failed scenario details
- Check if current_attempt < max_retries

### 4.3 Generate Fix Context
If retries available:
1. Load fix context template
2. Populate with failed scenarios
3. Write to: `{sprint_artifacts}/uat-fixes/epic-{id}-fix-context-{attempt}.md`

### 4.4 Trigger Quick-Dev Fix
Spawn fresh Claude session:
```
claude --dangerously-skip-permissions -p "Load fix context, implement fixes..."
```

### 4.5 Increment and Retry
- Increment attempt counter
- Return to Step 3 for re-validation

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| gate_status | State | PASS or FAIL |
| fix_context_file | Path | Generated fix context (if failed) |

## Completion Signal
GATE_EVALUATED: PASS|FAIL
```

#### step-05-report-results.md

```markdown
# Step 5: Report Results

## Purpose
Update metrics and output parseable signals.

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| gate_status | Step 4 | Yes |
| results | Step 3 | Yes |
| fix_attempts | State | Yes |

## Process

### 5.1 Update Metrics File
Update `{metrics_dir}/epic-{id}-metrics.yaml`:
```yaml
validation:
  gate_executed: true
  gate_status: "PASS|FAIL"
  fix_attempts: N
  scenarios_passed: X
  scenarios_failed: Y
```

### 5.2 Output Signals
Print to stdout (for parent script parsing):
```
UAT_GATE_RESULT: PASS|FAIL
UAT_FIX_ATTEMPTS: N
UAT_SCENARIOS_PASSED: X/Y
```

### 5.3 Set Exit Code
- 0: PASS
- 1: FAIL (fixable, retries remain)
- 2: FAIL (max retries exceeded)

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| Updated metrics | YAML file | Validation results |
| Signals | stdout | Parseable output |

## Completion Signal
RESULTS_REPORTED: {metrics_path}
```

---

### Step 6: Integrate Fix Context with Handoff Pattern [P2]

**Directory structure:**

```
docs/sprint-artifacts/
├── handoffs/
│   ├── epic-1-to-2-handoff.md
│   └── epic-2-to-3-handoff.md
├── uat-fixes/                    # NEW
│   ├── epic-1-fix-context-1.md
│   └── epic-2-fix-context-1.md
└── metrics/
    ├── epic-1-metrics.yaml
    └── epic-2-metrics.yaml
```

**In uat-validate.sh, implement generate_fix_context():**

```bash
generate_fix_context() {
    local epic_id="$1"
    local attempt="$2"
    local failed_scenarios="$3"

    local fix_dir="$SPRINT_ARTIFACTS_DIR/uat-fixes"
    mkdir -p "$fix_dir"

    local fix_file="$fix_dir/epic-${epic_id}-fix-context-${attempt}.md"
    local template="$PROJECT_ROOT/src/modules/bmm/workflows/5-validation/uat-validate/uat-fix-context-template.md"

    # Render template with variables
    sed -e "s/{epic_id}/$epic_id/g" \
        -e "s/{attempt}/$attempt/g" \
        -e "s/{timestamp}/$(date -u +"%Y-%m-%dT%H:%M:%SZ")/g" \
        "$template" > "$fix_file"

    # Append failed scenarios
    echo "" >> "$fix_file"
    echo "## Failed Scenarios" >> "$fix_file"
    echo "$failed_scenarios" >> "$fix_file"

    echo "$fix_file"
}
```

**In quick-dev fix session, load context:**

```bash
run_quick_dev_fix() {
    local fix_context_file="$1"
    local epic_id="$2"
    local attempt="$3"

    local fix_prompt="You are Barry, the Quick Flow Solo Dev.

Load and process this fix context document:
$fix_context_file

Your task:
1. Read the failed scenarios and error details
2. Analyze root cause for each failure
3. Implement targeted fixes
4. Run the failing commands to verify fixes
5. Stage changes: git add -A
6. Commit with message: fix(epic-${epic_id}): UAT fix #${attempt}

Constraints:
- Only fix the identified failures
- Do not refactor unrelated code
- Run tests after fixes

When done, output:
FIX_COMPLETE: {number_fixed}/{total_failures}"

    # Fresh Claude context for fixes
    claude --dangerously-skip-permissions -p "$fix_prompt"
}
```

---

## Execution Order

1. **`scripts/uat-validate.sh`** - Core orchestration (enables self-healing)
2. **`scripts/epic-execute.sh`** modifications - Metrics collection (enables reporting)
3. **`scripts/epic-chain.sh`** modifications - UAT gate + report integration
4. **Step files** - Documentation and maintainability

---

## Testing Plan

### Unit Tests

1. `uat-validate.sh --dry-run` - Verify argument parsing and flow
2. Metrics YAML structure matches template at `src/modules/bmm/workflows/4-implementation/epic-chain/templates/epic-metrics-template.yaml`
3. Signal output format matches spec

### Integration Tests

1. Run epic-execute with metrics collection, verify `docs/sprint-artifacts/metrics/epic-{id}-metrics.yaml` created
2. Run uat-validate against known-passing UAT doc, verify `UAT_GATE_RESULT: PASS`
3. Run uat-validate against known-failing UAT doc, verify fix loop triggers
4. Run epic-chain with `--uat-gate=quick`, verify gate runs after each epic

### Manual Verification

1. Run `epic-chain 1-3` on test project
2. Verify `docs/sprint-artifacts/metrics/` populated with per-epic metrics
3. Verify `docs/sprint-artifacts/uat-fixes/` created on UAT failure
4. Verify `chain-execution-report.md` generated with accurate aggregated data

---

## Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| `yq` | YAML manipulation | Recommended (fallback: inline append) |
| `timeout` | Command timeout | Yes (GNU coreutils) |
| `claude` CLI | Isolated context spawning | Yes |
| `sed` | Template rendering | Yes (POSIX) |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `yq` not installed | Detect and fall back to inline YAML append via echo/cat |
| UAT document malformed | Validate structure before processing, clear error messages |
| Claude session fails | Capture exit code, log output, allow retry |
| Infinite fix loop | Hard limit via `--max-retries`, default 2 |
| Scenario command not found | Record as FAIL with clear "command not found" message |
| Timeout exceeded | Record as FAIL, include timeout duration in output |

---

## Reference Files

### Existing (to read for patterns)

- `scripts/epic-execute.sh` - Context isolation, logging, argument parsing
- `scripts/epic-chain.sh` - Orchestration, CLI flags, integration points
- `src/modules/bmm/workflows/5-validation/uat-validate/instructions.md` - Validation logic
- `src/modules/bmm/workflows/5-validation/uat-validate/uat-fix-context-template.md` - Fix context template
- `src/modules/bmm/workflows/4-implementation/epic-chain/templates/epic-metrics-template.yaml` - Metrics schema
- `src/modules/bmm/workflows/4-implementation/epic-chain/steps/step-10-generate-report.md` - Report generation

### To Create

- `scripts/uat-validate.sh`
- `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-01-load-uat.md`
- `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-02-classify-scenarios.md`
- `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-03-execute-scenarios.md`
- `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-04-evaluate-gate.md`
- `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-05-report-results.md`

### To Modify

- `scripts/epic-execute.sh` - Add metrics collection
- `scripts/epic-chain.sh` - Add UAT gate and report generation
