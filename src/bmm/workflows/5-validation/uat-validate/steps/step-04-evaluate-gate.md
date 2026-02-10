# Step 4: Evaluate Gate

## Purpose

Determine overall pass/fail status based on execution results. If failed and self-healing is enabled, generate fix context and trigger the quick-dev fix loop.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| results | Step 3 | Yes |
| passed_count | Step 3 | Yes |
| failed_count | Step 3 | Yes |
| failed_details | Step 3 | Yes |
| max_retries | CLI | Yes (default: 2) |
| current_attempt | State | Yes (starts at 0) |
| self_heal_enabled | Config | Yes (default: true) |

## Process

### 4.1 Check All Results

```
if failed_count == 0:
    gate_status = PASS
    → Skip to Step 5 (Report Results)
else:
    gate_status = FAIL
    → Continue to 4.2
```

### 4.2 Evaluate Retry Eligibility

```
if current_attempt >= max_retries:
    → Max retries exceeded, halt
    exit_code = 2

if self_heal_enabled == false:
    → Self-healing disabled, report failure
    exit_code = 1

→ Continue to 4.3 (Generate Fix Context)
```

### 4.3 Generate Fix Context Document

Create fix context document at:
```
{sprint_artifacts}/uat-fixes/epic-{epic_id}-fix-context-{attempt}.md
```

#### 4.3.1 Load Template

Load from: `{workflow_path}/uat-fix-context-template.md`

If template not found, use inline default structure.

#### 4.3.2 Populate Template Variables

| Variable | Value |
|----------|-------|
| `{epic_id}` | Epic ID being validated |
| `{attempt}` | Current fix attempt number |
| `{timestamp}` | ISO 8601 timestamp |
| `{max_retries}` | Maximum retry limit |
| `{next_attempt}` | attempt + 1 |
| `{failure_count}` | Number of failed scenarios |
| `{passed}` | Number of passed scenarios |
| `{total}` | Total scenarios executed |

#### 4.3.3 Append Failed Scenario Details

For each failed scenario:

```markdown
### Scenario {id}: {name}

**Command Executed:**
```bash
{command}
```

**Expected Result:**
{expected_result}

**Actual Result:**
```
{actual_output}
```

**Error Output:**
```
{stderr}
```

**Exit Code:** {exit_code}

**Related Story:** {story_id} (if determinable)

**Root Cause Hint:**
{analyze_error_for_hints}

---
```

#### 4.3.4 Add Fix Instructions

```markdown
## Fix Instructions

Address the failures above in priority order. For each fix:

1. **Analyze** - Understand why the scenario failed
2. **Locate** - Find the relevant code files
3. **Fix** - Implement the minimum change to resolve
4. **Verify** - Run the scenario command locally
5. **Commit** - Use: `fix(epic-{epic_id}): {description}`

### Constraints

- Only fix identified failures
- Do not refactor unrelated code
- Run tests after fixes: `npm test`
```

### 4.4 Trigger Quick-Dev Fix

Spawn a fresh Claude session for fixes:

```bash
fix_prompt="You are Barry, the Quick Flow Solo Dev.

Load and process this fix context document:
{fix_context_file}

Your task:
1. Read the failed scenarios and error details
2. Analyze root cause for each failure
3. Implement targeted fixes
4. Run the failing commands to verify fixes
5. Stage changes: git add -A
6. Commit: fix(epic-{epic_id}): UAT fix #{attempt}

Constraints:
- Only fix identified failures
- Do not refactor unrelated code
- Run tests after fixes

When done, output:
FIX_COMPLETE: {fixed_count}/{failure_count}"

claude --dangerously-skip-permissions -p "$fix_prompt"
```

### 4.5 Increment and Re-validate

After fix session completes:

1. Increment `current_attempt`
2. Return to Step 3 (Execute Scenarios)
3. Re-run validation with fresh results

```
current_attempt += 1
→ Go to Step 3: Execute Scenarios
→ Then return to Step 4: Evaluate Gate
```

### 4.6 Gate Decision Flowchart

```
┌─────────────────┐
│ Execute Results │
└────────┬────────┘
         │
         ▼
    ┌─────────┐
    │All Pass?│──Yes──▶ GATE_PASS (exit 0)
    └────┬────┘
         │No
         ▼
    ┌──────────────┐
    │ Retries Left?│──No──▶ GATE_FAIL (exit 2)
    └──────┬───────┘        Max retries exceeded
           │Yes
           ▼
    ┌──────────────┐
    │Self-Heal On? │──No──▶ GATE_FAIL (exit 1)
    └──────┬───────┘        Fixable but disabled
           │Yes
           ▼
    ┌──────────────┐
    │Generate Fix  │
    │Context Doc   │
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │Spawn Quick-  │
    │Dev Fix       │
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │Re-validate   │──────▶ (Back to Execute)
    └──────────────┘
```

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| gate_status | State | PASS or FAIL |
| fix_context_file | Path | Generated fix context (if failed) |
| fix_attempt | State | Current attempt number |

## Completion Signal

```
GATE_EVALUATED: PASS
```
or
```
GATE_EVALUATED: FAIL
FIX_CONTEXT: {fix_context_file}
FIX_ATTEMPT: {attempt}/{max_retries}
```

## Error Handling

| Error | Action |
|-------|--------|
| Template not found | Use inline default template |
| Fix context write fails | Log error, continue without self-healing |
| Claude session fails | Log output, count as failed attempt |
| Fix didn't resolve issue | Increment attempt, retry if allowed |
