---
title: UAT Validation Integration Architecture
---

# UAT Validation Integration Architecture

## Overview

This document describes how UAT validation integrates with the epic-chain workflow to provide automated quality gates, self-healing fix loops, and comprehensive validation reporting.

---

## Integration Points

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                    EPIC CHAIN WITH UAT VALIDATION + SELF-HEALING                  │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                            PER EPIC LOOP                                     │ │
│  │                                                                              │ │
│  │  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐       │ │
│  │  │ Phase 1 │──►│ Phase 2 │──►│ Phase 3 │──►│ Phase 4 │──►│ Phase 5 │       │ │
│  │  │  Dev    │   │ Review  │   │ Commit  │   │  UAT    │   │  Gate   │       │ │
│  │  │         │   │         │   │         │   │  Gen    │   │ Check   │       │ │
│  │  └─────────┘   └─────────┘   └─────────┘   └─────────┘   └────┬────┘       │ │
│  │                                                                │            │ │
│  └────────────────────────────────────────────────────────────────┼────────────┘ │
│                                                                   │              │
│                                                     ┌─────────────┴───────┐      │
│                                                     │    GATE DECISION    │      │
│                                                     └──────────┬──────────┘      │
│                                                                │                 │
│                              ┌──────────────────┬──────────────┴──────────┐      │
│                              │                  │                         │      │
│                              ▼                  ▼                         ▼      │
│                           ┌──────┐          ┌──────┐               ┌──────────┐  │
│                           │ PASS │          │ FAIL │               │ MAX      │  │
│                           │      │          │      │               │ RETRIES  │  │
│                           └──┬───┘          └──┬───┘               └────┬─────┘  │
│                              │                 │                        │        │
│                              │                 ▼                        ▼        │
│                              │    ┌────────────────────────┐    ┌────────────┐   │
│                              │    │      SELF-HEALING      │    │   HALT +   │   │
│                              │    │                        │    │   NOTIFY   │   │
│                              │    │  ┌──────────────────┐  │    └────────────┘   │
│                              │    │  │  Quick Dev Fix   │  │                     │
│                              │    │  │  (Barry Agent)   │  │                     │
│                              │    │  │                  │  │                     │
│                              │    │  │ • Load failures  │  │                     │
│                              │    │  │ • Generate fix   │  │                     │
│                              │    │  │ • Commit changes │  │                     │
│                              │    │  └────────┬─────────┘  │                     │
│                              │    │           │            │                     │
│                              │    │           ▼            │                     │
│                              │    │  ┌──────────────────┐  │                     │
│                              │    │  │   Re-validate    │  │                     │
│                              │    │  │   UAT Gate       │──┼──► Back to GATE     │
│                              │    │  └──────────────────┘  │                     │
│                              │    │                        │                     │
│                              │    └────────────────────────┘                     │
│                              │                                                   │
│                              ▼                                                   │
│                        ┌──────────┐                                              │
│                        │  Next    │                                              │
│                        │  Epic    │                                              │
│                        └──────────┘                                              │
│                                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                          CHAIN COMPLETION                                    │ │
│  │                                                                              │ │
│  │  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────────┐       │ │
│  │  │  Aggregate      │──►│  Generate       │──►│  Final UAT         │       │ │
│  │  │  Metrics        │   │  Chain Report   │   │  Summary           │       │ │
│  │  └─────────────────┘   └─────────────────┘   └─────────────────────┘       │ │
│  │                                                                              │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Self-Healing Loop: UAT Failure → Quick Dev → Re-validate

When UAT validation fails, the system automatically triggers a quick-dev session to fix the identified issues.

### Flow Detail

```
UAT Gate Check
     │
     ├── PASS ──────────────────────────────► Continue to Next Epic
     │
     └── FAIL
          │
          ▼
     ┌─────────────────────────────────────────────────────────────┐
     │                    FAILURE ANALYSIS                          │
     │                                                              │
     │  1. Collect failed scenarios with:                          │
     │     - Scenario ID and description                           │
     │     - Expected vs actual output                             │
     │     - Error messages / stack traces                         │
     │     - Related story acceptance criteria                     │
     │                                                              │
     │  2. Generate fix context document:                          │
     │     docs/sprint-artifacts/uat-fix-context-{epic}-{attempt}.md │
     └─────────────────────────────────────────────────────────────┘
          │
          ▼
     ┌─────────────────────────────────────────────────────────────┐
     │                    QUICK DEV SESSION                         │
     │                    (Barry - Quick Flow Solo Dev)             │
     │                                                              │
     │  Input: uat-fix-context-{epic}-{attempt}.md                 │
     │                                                              │
     │  Process:                                                    │
     │  1. Load fix context (failed scenarios + error details)     │
     │  2. Analyze root cause for each failure                     │
     │  3. Implement targeted fixes                                │
     │  4. Run self-check (step-04)                                │
     │  5. Commit with message: "fix(epic-{id}): UAT fix #{n}"     │
     │                                                              │
     │  Output:                                                     │
     │  - Code changes committed                                   │
     │  - Fix summary in story dev record                          │
     └─────────────────────────────────────────────────────────────┘
          │
          ▼
     ┌─────────────────────────────────────────────────────────────┐
     │                    RE-VALIDATE                               │
     │                                                              │
     │  Run UAT Gate Check again on same scenarios                 │
     │                                                              │
     │  Outcomes:                                                   │
     │  - PASS → Continue to next epic                             │
     │  - FAIL + attempts < max_retries → Loop back to Quick Dev   │
     │  - FAIL + attempts >= max_retries → HALT chain              │
     └─────────────────────────────────────────────────────────────┘
```

### Configuration

```yaml
# In epic-chain config
uat:
  gate_enabled: true
  gate_mode: quick              # quick | full | skip

  # Self-healing configuration
  self_heal:
    enabled: true
    max_retries: 2              # Maximum fix attempts per epic
    fix_workflow: quick-dev     # Workflow to use for fixes
    fix_agent: barry            # Agent to invoke

    # What to include in fix context
    include_in_context:
      - failed_scenarios
      - error_output
      - related_stories
      - acceptance_criteria
      - recent_commits         # Last 3 commits for context

    # Escalation
    on_max_retries: halt        # halt | continue_with_warning | notify_human
    notification_channel: null  # Optional: slack, email, etc.
```

### Fix Context Document Template

Generated when UAT fails, consumed by Quick Dev:

```markdown
# UAT Fix Context - Epic {epic_id} (Attempt {n})

## Failed Scenarios

### Scenario {id}: {name}

**Expected Result:**
{expected}

**Actual Result:**
{actual}

**Error Output:**
```
{stderr or error message}
```

**Related Story:** {story_id}
**Acceptance Criteria:**
- {criteria from story}

---

## Fix Instructions

Address the following failures in priority order:

1. **{scenario_id}**: {one-line description of what's broken}
   - Root cause hint: {if determinable}
   - Files likely involved: {if determinable}

## Constraints

- Only fix the identified failures
- Do not refactor unrelated code
- Run tests after each fix
- Commit with message format: `fix(epic-{id}): {description}`
```

---

## UAT Scenario Classification

Based on the UAT sample document, scenarios fall into three categories:

### Automatable (Execute via Shell)

| Scenario Type | Example | Automation Method |
|---------------|---------|-------------------|
| CLI commands | `npx heimdall --version` | Shell execution, check exit code + output |
| Build verification | `npm run build` | Shell execution, parse output for success |
| API health checks | `curl /health` | HTTP request, validate JSON response |
| Database status | `npx heimdall db status` | Shell execution, parse structured output |
| Configuration validation | `npx heimdall config validate` | Shell execution, check for "valid" in output |

### Semi-Automated (Execute + Manual Verify)

| Scenario Type | Example | Approach |
|---------------|---------|----------|
| Email delivery | `npx heimdall test-send` | Execute command, log message ID, flag for inbox check |
| File creation | `heimdall config init` | Execute, verify file exists, show contents for review |
| Worker processes | `heimdall start` | Start, verify startup message, terminate after timeout |

### Manual Only

| Scenario Type | Example | Approach |
|---------------|---------|----------|
| External service setup | Railway deployment | Document steps, skip in automation |
| Visual verification | UI appearance | Generate screenshots if possible, flag for review |
| Multi-step human flows | Full onboarding journey | Provide checklist, require human sign-off |

---

## Gate Check Implementation

### Quick Gate (Default)

Runs only automatable scenarios from the "Minimum Requirements" section:

```yaml
# uat-gate-config.yaml
gate_mode: quick
timeout_per_scenario: 30  # seconds
fail_threshold: 0         # any failure = gate fail

scenarios_to_run:
  - type: "cli_command"
    match: "Expected Results" sections with CLI commands
  - type: "health_check"
    match: "/health endpoint" scenarios
  - type: "validation"
    match: "validate" command scenarios

skip_scenarios:
  - contains: "email inbox"
  - contains: "Railway"
  - contains: "browser"
  - contains: "terminal window"
```

### Full Gate

Runs all automatable scenarios plus flags semi-automated for review:

```yaml
gate_mode: full
include_semi_automated: true
generate_manual_checklist: true
```

---

## Data Flow

### Per-Epic Metrics Collection

```yaml
# Written to: {sprint_artifacts}/metrics/epic-{id}-metrics.yaml

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

uat:
  document_generated: true
  document_path: "docs/uat/epic-1-uat.md"
  scenarios:
    total: 9
    automatable: 6
    semi_automated: 2
    manual_only: 1

validation:
  gate_executed: true
  gate_mode: "quick"
  results:
    passed: 6
    failed: 0
    skipped: 3
  gate_status: "PASS"
  blocking_issues: []

  # Self-healing loop tracking
  fix_attempts: 0
  fix_history: []
  # Example when fixes were needed:
  # fix_attempts: 2
  # fix_history:
  #   - attempt: 1
  #     failed_scenarios: ["scenario-3", "scenario-5"]
  #     fix_context: "docs/sprint-artifacts/uat-fix-context-1-1.md"
  #     fix_commit: "abc123"
  #     result: "partial"  # 1 of 2 fixed
  #   - attempt: 2
  #     failed_scenarios: ["scenario-5"]
  #     fix_context: "docs/sprint-artifacts/uat-fix-context-1-2.md"
  #     fix_commit: "def456"
  #     result: "success"  # all fixed

issues:
  - type: "signaling_mismatch"
    story: "1-3"
    severity: "low"
    resolved: true
```

### Chain Report Aggregation

```yaml
# Read from: {sprint_artifacts}/metrics/epic-*-metrics.yaml
# Write to: {sprint_artifacts}/chain-execution-report.md

chain:
  total_epics: 8
  total_stories: 58
  total_duration_seconds: 63000

  epics:
    - id: "1"
      stories: 7
      duration: 5400
      uat_gate: "PASS"
    # ... etc

  uat_summary:
    total_scenarios: 72
    automatable: 48
    auto_passed: 45
    auto_failed: 3
    manual_pending: 24

  gate_results:
    passed: 7
    failed: 1
    blocked_chain: false
```

---

## Workflow File Changes

### Modified: `epic-chain/workflow.yaml`

```yaml
# Add to variables section:
variables:
  # ... existing ...

  # UAT Gate Configuration
  uat_gate_enabled: true
  uat_gate_mode: "quick"      # quick | full | skip
  uat_gate_blocking: false    # If true, halts chain on failure

  # Report Configuration
  generate_chain_report: true
  chain_report_file: "{sprint_artifacts}/chain-execution-report.md"
  metrics_folder: "{sprint_artifacts}/metrics"
```

### New: `step-05-uat-gate.md`

```markdown
# UAT Gate Check

## Purpose
Validate epic implementation against automatable UAT scenarios before proceeding.

## Inputs
- UAT document: `docs/uat/epic-{id}-uat.md`
- Gate config: `{uat_gate_mode}`

## Process
1. Parse UAT document for test scenarios
2. Identify automatable scenarios (CLI commands, API calls, file checks)
3. Execute each in isolated shell
4. Collect results with stdout/stderr evidence
5. Determine gate status

## Outputs
- Gate result: PASS | FAIL
- Metrics update: `{metrics_folder}/epic-{id}-metrics.yaml`

## Exit Conditions
- PASS: Continue to next epic
- FAIL + blocking=false: Log warning, continue
- FAIL + blocking=true: Halt chain, require intervention
```

### New: `step-06-generate-report.md`

```markdown
# Chain Report Generation

## Purpose
Generate comprehensive execution report after chain completion.

## Inputs
- All metrics files: `{metrics_folder}/epic-*-metrics.yaml`
- Chain plan: `{chain_plan_file}`
- Template: `chain-report-template.md`

## Process
1. Load all epic metrics
2. Calculate aggregates (totals, averages, percentages)
3. Build dependency graph visualization
4. Compile issues list
5. Generate token/cost estimates
6. Render report template

## Outputs
- `{chain_report_file}` - Complete execution report
```

---

## Agent Interaction Model

### SM Agent (Orchestrator) - With Self-Healing

```
User: *epic-chain 1-8

SM: Loading chain plan...
    Found 8 epics, 58 stories
    Dependencies analyzed: sequential with branches

    Starting Epic 1 (Foundation)...
    [Dev → Review → Commit → UAT Gen → Gate Check]
    Epic 1: COMPLETE (7/7 stories, UAT PASS)

    Starting Epic 2 (Event Ingestion)...
    [Dev → Review → Commit → UAT Gen → Gate Check]

    ⚠ UAT GATE FAILED - 2 scenarios failed

    Initiating self-healing loop (attempt 1/2)...
    Generating fix context → docs/sprint-artifacts/uat-fix-context-2-1.md

    [Invoking Barry for quick-dev fix session]
    Barry: Loading fix context...
           Failure 1: API endpoint returning 404
           Failure 2: Missing auth header validation
           Implementing fixes...
           ✓ Fixed route registration in server.ts
           ✓ Added auth middleware check
           Committed: fix(epic-2): UAT fix #1

    Re-validating UAT gate...
    ✓ All scenarios now passing

    Epic 2: COMPLETE (5/5 stories, UAT PASS after 1 fix)

    Starting Epic 3 (Workflow Engine)...
    ...

    Chain Complete.
    Generating execution report...
    Report: docs/sprint-artifacts/chain-execution-report.md

    Summary:
    - 8/8 epics completed
    - 2 epics required self-healing fixes
    - Total fix attempts: 3
    - All UAT gates now passing
```

### UAT Validator Agent (Validation)

```
User: *uat-validate 1

Quinn: Loading UAT document for Epic 1...
       Found 9 scenarios:
       - 6 automatable
       - 2 semi-automated
       - 1 manual only

       Executing automatable scenarios...

       ✓ Scenario 1: Project Initialization
         Command: npx heimdall --version
         Result: PASS (output: "1.0.0")

       ✓ Scenario 3: Database Migration
         Command: npx heimdall db migrate
         Result: PASS (output contains "initialized successfully")

       ⚠ Scenario 7: Test Email Sending
         Command: npx heimdall test-send --to test@example.com
         Result: SEMI-AUTO (executed, requires inbox verification)
         Message ID: re_abc123

       ○ Scenario 9: Railway Deployment
         Result: SKIPPED (manual only)

       Summary: 6/6 automatable PASSED
       Recommendation: APPROVE (pending manual verification of 3 scenarios)
```

### Self-Healing Loop Example (Failure → Fix → Pass)

```
Quinn: UAT Gate Check for Epic 2...

       ✓ Scenario 1: Event Ingestion Endpoint
         Command: curl -X POST http://localhost:3000/api/v1/events
         Result: PASS (201 Created)

       ✗ Scenario 2: API Key Authentication
         Command: curl -H "X-API-Key: test" http://localhost:3000/api/v1/events
         Expected: 200 OK with auth header validated
         Actual: 401 Unauthorized
         Error: "Missing authentication middleware"

       ✗ Scenario 3: Events Database Table
         Command: npx heimdall db status
         Expected: "events table: exists"
         Actual: Exit code 1
         Error: "relation 'events' does not exist"

       UAT_GATE_RESULT: FAIL
       CRITICAL_PASSED: 1/3
       BLOCKING_ISSUES: [scenario-2, scenario-3]

       Generating fix context for quick-dev...
       Output: docs/sprint-artifacts/uat-fix-context-2-1.md

---

Barry: Loading fix context for Epic 2 (Attempt 1)...

       Issue 1: API Key Authentication failing
       - Root cause: Auth middleware not registered on route
       - Fix: Add authMiddleware to route handler chain

       Issue 2: Events table missing
       - Root cause: Migration file exists but wasn't run
       - Fix: Ensure migration runs in db:migrate command

       Implementing fixes...
       ✓ Updated packages/api/src/routes/events.ts
       ✓ Updated packages/cli/src/commands/db.ts

       Running self-check...
       ✓ Tests passing

       Committing: fix(epic-2): add auth middleware, fix migration order

---

Quinn: Re-validating UAT Gate for Epic 2...

       ✓ Scenario 1: Event Ingestion Endpoint - PASS
       ✓ Scenario 2: API Key Authentication - PASS (was FAIL)
       ✓ Scenario 3: Events Database Table - PASS (was FAIL)

       UAT_GATE_RESULT: PASS
       CRITICAL_PASSED: 3/3

       Epic 2 approved after 1 fix attempt.
```

---

## Configuration Options

### Default Configuration

```yaml
# {project-root}/.bmad/bmm/config.yaml additions

epic_chain:
  # UAT Settings
  uat:
    gate_enabled: true
    gate_mode: quick          # quick | full | skip
    gate_blocking: false      # Stop chain on failure?
    timeout_seconds: 30       # Per-scenario timeout

  # Report Settings
  report:
    enabled: true
    format: markdown          # markdown | html | both
    include_token_estimates: true
    include_dependency_graph: true

  # Metrics Settings
  metrics:
    enabled: true
    per_story_timing: true
    track_retries: true
```

### Per-Run Override

```bash
# Override gate settings for a specific run
./bmad/scripts/epic-chain.sh 1-8 --uat-gate=full --uat-blocking=true
```

---

## Summary

This integration provides:

1. **Automated Quality Gates** - Verify implementations meet acceptance criteria before proceeding
2. **Self-Healing Fix Loop** - Failed UAT automatically triggers quick-dev to fix issues and re-validate
3. **Comprehensive Reporting** - Generate detailed execution reports with metrics, timing, fix history, and issues
4. **Flexible Configuration** - Adjust gate strictness, retry limits, and escalation behavior per project/run
5. **Clear Traceability** - Every test scenario maps back to story acceptance criteria, every fix links to failure
6. **Graceful Degradation** - Semi-automated and manual scenarios documented but not blocking

### Agent Responsibilities

| Agent | Role | Key Actions |
|-------|------|-------------|
| **SM (Bob)** | Chain Orchestrator | Runs epic-chain, coordinates phases, triggers fix loops |
| **Quinn** | UAT Validator | Executes scenarios, generates fix context on failure |
| **Barry** | Quick Dev Fixer | Receives fix context, implements targeted fixes, commits |

### Self-Healing Flow

```
UAT Fail → Generate Fix Context → Quick Dev Fix → Re-validate → Pass/Retry/Halt
```

The maximum retry count (default: 2) prevents infinite loops. After max retries, the chain halts and requires human intervention, ensuring issues are surfaced rather than ignored.
