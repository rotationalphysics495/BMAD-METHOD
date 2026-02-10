---
title: "UAT Workflow Implementation Gaps & Required Fixes"
---

# UAT Workflow Implementation Gaps & Required Fixes

## Executive Summary

The UAT validation workflow and epic chain report generator have been designed and partially implemented, but several critical components are missing to make them production-ready. This document outlines the gaps, required fixes, and context needed to complete the implementation.

**Current State:** Workflow definitions, templates, and agent triggers exist
**Missing:** Shell orchestration, metrics collection, step files, and integration points

---

## Architecture Context

### How BMAD Workflows Achieve Context Isolation

Native BMAD workflows use a **shell script orchestration pattern** to isolate Claude contexts:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BMAD CONTEXT ISOLATION PATTERN                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Shell Script (epic-execute.sh / epic-chain.sh)                     │
│       │                                                              │
│       ├──► claude -p "Phase 1 prompt..."  ──► Fresh Context A       │
│       │         │                                                    │
│       │         └──► Git staging / Story file (state transfer)      │
│       │                                                              │
│       ├──► claude -p "Phase 2 prompt..."  ──► Fresh Context B       │
│       │         │                                                    │
│       │         └──► Git staging / Story file (state transfer)      │
│       │                                                              │
│       └──► claude -p "Phase 3 prompt..."  ──► Fresh Context C       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Files:**
- `scripts/epic-execute.sh` - 600+ lines, handles dev→review→commit→UAT phases
- `scripts/epic-chain.sh` - Handles multi-epic execution with handoffs

**State Transfer Mechanisms:**
1. **Git staging** - Code changes pass between contexts via `git add`
2. **Story files** - Dev Agent Record and Code Review Record sections
3. **Handoff documents** - Cross-epic context transfer
4. **Completion signals** - `IMPLEMENTATION COMPLETE: {id}`, `REVIEW PASSED: {id}`

---

## Gap 1: Missing Shell Orchestration Script

### Problem

The UAT validation self-healing loop requires context isolation:

```
UAT Validate (Quinn) → Fix Context → Quick Dev (Barry) → Re-validate (Quinn)
```

Without a shell script, these phases would run in the same Claude context, defeating the purpose of fresh-eyes validation after fixes.

### Required: `scripts/uat-validate.sh`

**Location:** `scripts/uat-validate.sh`

**Responsibilities:**
1. Load UAT document for specified epic
2. Execute automatable scenarios via shell commands
3. Collect pass/fail results with evidence
4. On failure: Generate fix context document
5. Spawn fresh Claude session for quick-dev fixes
6. Re-validate in fresh context
7. Loop until pass or max retries
8. Output final gate result

**Interface:**
```bash
# Usage
./scripts/uat-validate.sh <epic_id> [options]

# Options
--gate-mode=quick|full|skip    # Which scenarios to run
--max-retries=2                # Fix attempts before halt
--skip-manual                  # Skip manual-only scenarios
--verbose                      # Detailed output

# Output signals (for epic-chain.sh to parse)
UAT_GATE_RESULT: PASS|FAIL
UAT_FIX_ATTEMPTS: N
UAT_SCENARIOS_PASSED: X/Y
```

**Context Flow:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                     uat-validate.sh Flow                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Load UAT doc: docs/uat/epic-{id}-uat.md                         │
│                                                                      │
│  2. Classify scenarios (automatable / semi-auto / manual)           │
│                                                                      │
│  3. Execute automatable scenarios via shell:                        │
│     for scenario in automatable:                                    │
│         result = execute_command(scenario.command)                  │
│         record_result(scenario.id, result)                          │
│                                                                      │
│  4. Evaluate gate:                                                  │
│     if all_passed:                                                  │
│         echo "UAT_GATE_RESULT: PASS"                                │
│         exit 0                                                      │
│                                                                      │
│  5. On failure (attempt < max_retries):                             │
│     a. Generate fix context document                                │
│     b. Spawn fresh Claude for quick-dev:                            │
│        claude -p "Load fix context, implement fixes..."             │
│     c. Increment attempt counter                                    │
│     d. Go to step 3 (re-validate)                                   │
│                                                                      │
│  6. On max retries exceeded:                                        │
│     echo "UAT_GATE_RESULT: FAIL"                                    │
│     echo "UAT_MAX_RETRIES: true"                                    │
│     exit 2                                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Reference Implementation:** See `scripts/epic-execute.sh` lines 289-438 for how dev and review phases spawn isolated Claude sessions.

---

## Gap 2: Metrics Collection Not Instrumented

### Problem

The report generator expects metrics at `{metrics_folder}/epic-{id}-metrics.yaml`, but `epic-execute.sh` doesn't write these files.

### Required: Metrics Instrumentation in `epic-execute.sh`

**Location:** Modify `scripts/epic-execute.sh`

**Add at epic start (~line 520):**
```bash
# Initialize metrics
EPIC_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
METRICS_FILE="$SPRINT_ARTIFACTS/metrics/epic-${EPIC_ID}-metrics.yaml"
mkdir -p "$SPRINT_ARTIFACTS/metrics"

# Initialize metrics file
cat > "$METRICS_FILE" << EOF
epic_id: "$EPIC_ID"
epic_name: "$EPIC_NAME"
execution:
  start_time: "$EPIC_START_TIME"
  end_time: ""
  duration_seconds: 0
stories:
  total: ${#STORIES[@]}
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

**Add after each story (~line 595):**
```bash
# Update metrics after story completion
update_story_metrics() {
    local status="$1"  # completed | failed | skipped
    local story_id="$2"

    # Increment appropriate counter
    case "$status" in
        completed) yq -i '.stories.completed += 1' "$METRICS_FILE" ;;
        failed)    yq -i '.stories.failed += 1' "$METRICS_FILE" ;;
        skipped)   yq -i '.stories.skipped += 1' "$METRICS_FILE" ;;
    esac
}
```

**Add at epic end (~line 620):**
```bash
# Finalize metrics
EPIC_END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DURATION=$(($(date +%s) - $(date -d "$EPIC_START_TIME" +%s)))

yq -i ".execution.end_time = \"$EPIC_END_TIME\"" "$METRICS_FILE"
yq -i ".execution.duration_seconds = $DURATION" "$METRICS_FILE"
```

**Template Reference:** `src/modules/bmm/workflows/4-implementation/epic-chain/templates/epic-metrics-template.yaml`

---

## Gap 3: UAT Gate Not Integrated Into epic-chain.sh

### Problem

`epic-chain.sh` executes epics but doesn't call UAT validation between them.

### Required: Add UAT Gate Phase to `epic-chain.sh`

**Location:** Modify `scripts/epic-chain.sh`

**Add configuration variables (~line 50):**
```bash
# UAT Gate Configuration
UAT_GATE_ENABLED="${UAT_GATE_ENABLED:-true}"
UAT_GATE_MODE="${UAT_GATE_MODE:-quick}"
UAT_MAX_RETRIES="${UAT_MAX_RETRIES:-2}"
UAT_BLOCKING="${UAT_BLOCKING:-false}"
```

**Add after epic completion (~line 480, after `run_epic_execute`):**
```bash
# Run UAT validation if enabled
if [ "$UAT_GATE_ENABLED" = true ]; then
    log "Running UAT validation for Epic $epic_id..."

    uat_result=$(./scripts/uat-validate.sh "$epic_id" \
        --gate-mode="$UAT_GATE_MODE" \
        --max-retries="$UAT_MAX_RETRIES" 2>&1)

    # Parse result
    if echo "$uat_result" | grep -q "UAT_GATE_RESULT: PASS"; then
        log "✓ UAT validation passed for Epic $epic_id"
        # Update metrics
        yq -i '.validation.gate_executed = true' "$METRICS_FILE"
        yq -i '.validation.gate_status = "PASS"' "$METRICS_FILE"
    else
        log_error "✗ UAT validation failed for Epic $epic_id"
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

**Add CLI flag parsing (~line 120):**
```bash
--uat-gate=*)
    UAT_GATE_MODE="${1#*=}"
    ;;
--uat-blocking)
    UAT_BLOCKING=true
    ;;
--no-uat)
    UAT_GATE_ENABLED=false
    ;;
```

---

## Gap 4: Step Files Not Following BMAD Pattern

### Problem

The UAT validation workflow has `instructions.md` but not the step-file architecture used by epic-execute:
- `step-01-init.md`
- `step-02-dev-story.md`
- `step-03-code-review.md`
- etc.

### Required: Create Step Files for UAT Validation

**Location:** `src/modules/bmm/workflows/5-validation/uat-validate/steps/`

**Files to create:**

| File | Purpose |
|------|---------|
| `step-01-load-uat.md` | Load UAT document, parse scenarios |
| `step-02-classify-scenarios.md` | Categorize as automatable/semi-auto/manual |
| `step-03-execute-scenarios.md` | Run automatable scenarios via shell |
| `step-04-evaluate-gate.md` | Determine pass/fail, generate fix context if needed |
| `step-05-report-results.md` | Update metrics, output signals |

**Step File Template (from epic-execute pattern):**
```markdown
# Step N: {Title}

## Purpose
{What this step accomplishes}

## Inputs
| Input | Source | Required |
|-------|--------|----------|
| ... | ... | Yes/No |

## Process

### N.1 {Sub-step}
{Detailed instructions}

### N.2 {Sub-step}
{Detailed instructions}

## Outputs
| Output | Location | Description |
|--------|----------|-------------|
| ... | ... | ... |

## Completion Signal
```
{SIGNAL_NAME}: {value}
```

## Error Handling
| Error | Action |
|-------|--------|
| ... | ... |
```

---

## Gap 5: Fix Context Not Integrated With Handoff Pattern

### Problem

The fix context template exists but isn't written to the handoff directory or loaded by quick-dev.

### Required: Integrate Fix Context With Handoff Flow

**Fix context location should follow handoff pattern:**
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

**In `uat-validate.sh`, write fix context:**
```bash
generate_fix_context() {
    local epic_id="$1"
    local attempt="$2"
    local failed_scenarios="$3"

    local fix_dir="$SPRINT_ARTIFACTS/uat-fixes"
    mkdir -p "$fix_dir"

    local fix_file="$fix_dir/epic-${epic_id}-fix-context-${attempt}.md"

    # Render template with variables
    sed -e "s/{epic_id}/$epic_id/g" \
        -e "s/{attempt}/$attempt/g" \
        -e "s/{timestamp}/$(date -u +"%Y-%m-%dT%H:%M:%SZ")/g" \
        "$WORKFLOW_PATH/uat-fix-context-template.md" > "$fix_file"

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

    local fix_prompt="You are Barry, the Quick Flow Solo Dev.

Load and process this fix context document:
$fix_context_file

Your task:
1. Read the failed scenarios and error details
2. Analyze root cause for each failure
3. Implement targeted fixes
4. Run the failing commands to verify fixes
5. Commit with message: fix(epic-{id}): UAT fix #{attempt}

Constraints:
- Only fix the identified failures
- Do not refactor unrelated code
- Run tests after fixes

When done, output:
FIX_COMPLETE: {number_fixed}/{total_failures}
"

    # Fresh Claude context for fixes
    claude --dangerously-skip-permissions -p "$fix_prompt"
}
```

---

## Gap 6: Report Generator Missing Chain Integration

### Problem

Step 10 (generate report) exists but isn't called automatically by `epic-chain.sh`.

### Required: Add Report Generation to `epic-chain.sh`

**Add after all epics complete (~line 550):**
```bash
# Generate chain execution report
if [ "$GENERATE_REPORT" = true ]; then
    log "Generating chain execution report..."

    # Invoke report generation via Claude
    report_prompt="You are Bob, the Scrum Master.

Execute the chain report generation workflow:
- Load: $INSTALLED_PATH/steps/step-10-generate-report.md
- Metrics folder: $SPRINT_ARTIFACTS/metrics
- Chain plan: $CHAIN_PLAN_FILE
- Output to: $CHAIN_REPORT_FILE

Generate the complete execution report."

    claude --dangerously-skip-permissions -p "$report_prompt"

    if [ -f "$CHAIN_REPORT_FILE" ]; then
        log "✓ Report generated: $CHAIN_REPORT_FILE"
    else
        log_error "Report generation failed"
    fi
fi
```

---

## Implementation Priority

| Priority | Gap | Effort | Impact |
|----------|-----|--------|--------|
| **P0** | Create `uat-validate.sh` | High | Critical - self-healing loop won't work without it |
| **P0** | Add metrics instrumentation to `epic-execute.sh` | Medium | Critical - report generator needs data |
| **P1** | Integrate UAT gate into `epic-chain.sh` | Medium | High - enables automated validation |
| **P1** | Integrate report generation into `epic-chain.sh` | Low | High - automates report creation |
| **P2** | Create step files for UAT validation | Medium | Medium - improves maintainability |
| **P2** | Integrate fix context with handoff pattern | Low | Medium - cleaner file organization |

---

## File Reference

### Existing Files (Created)

| File | Status | Purpose |
|------|--------|---------|
| `src/modules/bmm/agents/uat-validator.agent.yaml` | ✅ Complete | Quinn agent definition |
| `src/modules/bmm/workflows/5-validation/uat-validate/workflow.yaml` | ✅ Complete | Workflow configuration |
| `src/modules/bmm/workflows/5-validation/uat-validate/instructions.md` | ✅ Complete | Execution instructions |
| `src/modules/bmm/workflows/5-validation/uat-validate/uat-fix-context-template.md` | ✅ Complete | Fix context template |
| `src/modules/bmm/workflows/4-implementation/epic-chain/templates/chain-report-template.md` | ✅ Complete | Report template |
| `src/modules/bmm/workflows/4-implementation/epic-chain/templates/epic-metrics-template.yaml` | ✅ Complete | Metrics schema |
| `src/modules/bmm/workflows/4-implementation/epic-chain/steps/step-10-generate-report.md` | ✅ Complete | Report generation step |

### Files to Create

| File | Priority | Purpose |
|------|----------|---------|
| `scripts/uat-validate.sh` | P0 | Shell orchestration for UAT validation |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-01-load-uat.md` | P2 | Step file |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-02-classify-scenarios.md` | P2 | Step file |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-03-execute-scenarios.md` | P2 | Step file |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-04-evaluate-gate.md` | P2 | Step file |
| `src/modules/bmm/workflows/5-validation/uat-validate/steps/step-05-report-results.md` | P2 | Step file |

### Files to Modify

| File | Priority | Changes |
|------|----------|---------|
| `scripts/epic-execute.sh` | P0 | Add metrics collection |
| `scripts/epic-chain.sh` | P1 | Add UAT gate phase, report generation |

---

## Testing Plan

### Unit Tests

1. **uat-validate.sh** - Test scenario classification, command execution, signal output
2. **Metrics collection** - Verify YAML structure matches template
3. **Report generation** - Verify all placeholders replaced

### Integration Tests

1. **Self-healing loop** - Intentionally fail a scenario, verify fix + re-validate
2. **Epic chain with UAT** - Run full chain, verify UAT runs after each epic
3. **Report accuracy** - Compare report metrics to actual execution

### Manual Verification

1. Run `epic-chain 1-3` on test project
2. Verify metrics files created
3. Verify UAT validation runs
4. Verify report generated with accurate data

---

## Conclusion

The UAT validation and report generation workflows are architecturally sound but missing the shell orchestration layer that makes BMAD workflows production-ready. The highest priority items are:

1. **Create `uat-validate.sh`** - Without this, context isolation doesn't happen
2. **Instrument `epic-execute.sh`** - Without this, reports have no data

Once these are complete, the full flow will work:

```
epic-chain → epic-execute → UAT validate → (fix loop if needed) → next epic → report
```
