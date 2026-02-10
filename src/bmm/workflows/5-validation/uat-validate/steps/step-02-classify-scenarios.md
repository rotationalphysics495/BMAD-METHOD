# Step 2: Classify Scenarios

## Purpose

Categorize each scenario by its executability level to determine which can be automated, which need partial automation, and which require manual verification.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| scenario_list | Step 1 | Yes |

## Process

### 2.1 Classification Categories

| Classification | Description | Gate Behavior |
|----------------|-------------|---------------|
| **Automatable** | Can be fully executed via shell command | Execute and verify |
| **Semi-automated** | Requires setup, then automated verification | Execute with warning |
| **Manual** | Requires human interaction or visual verification | Skip, add to checklist |

### 2.2 Detect Automatable Scenarios

Check scenario content for these indicators (case-insensitive):

**CLI/Command indicators:**
- `npx`, `npm run`, `yarn`, `pnpm`
- `node `, `python `, `ruby `
- `curl `, `wget `, `http`
- `bash `, `sh `, `./`

**Test framework indicators:**
- `pytest`, `jest`, `vitest`, `mocha`
- `npm test`, `yarn test`

**Verification indicators:**
- `--version`, `--help`
- `/health`, `/api/`, `/status`
- `exit code`, `returns 0`, `returns 1`
- `outputs`, `prints`, `displays`

**Database/Config indicators:**
- `db migrate`, `db status`
- `config validate`, `config check`

### 2.3 Detect Semi-Automated Scenarios

Scenarios with commands that require prior setup:

**Setup-required indicators:**
- "Start the server first"
- "Ensure database is running"
- "In a separate terminal"
- "After deploying"

**Partial automation indicators:**
- `test-send`, `send test`
- "check your email/inbox"
- "verify in browser"
- Manual setup + automated verification

### 2.4 Classify as Manual

Scenarios without detectable automation path:

**Manual-only indicators:**
- "Railway dashboard", "Vercel dashboard"
- "Open browser", "Navigate to"
- "Visual inspection", "Visually verify"
- "Two terminals", "Side by side"
- "User should see", "Observe that"
- No code blocks or CLI references

### 2.5 Extract Commands

For automatable/semi-automated scenarios, extract the verification command:

1. Look for inline code: `` `command here` ``
2. Look for code blocks: ```bash ... ```
3. Look for CLI patterns: `npx ...`, `npm run ...`, `curl ...`
4. Look for expected patterns after "Run:" or "Execute:"

### 2.6 Build Classification Result

```yaml
classification:
  total: 9
  automatable: 6
  semi_automated: 2
  manual: 1

automatable_scenarios:
  - id: 1
    name: "Project Initialization"
    command: "npx heimdall --version"
    expected: "displays a version number"

  - id: 3
    name: "Database Migration"
    command: "npx heimdall db migrate"
    expected: "success message"

semi_automated_scenarios:
  - id: 7
    name: "Email Notification"
    command: "curl -X POST localhost:3000/test-send"
    expected: "email received"
    note: "Requires manual inbox verification"

manual_scenarios:
  - id: 9
    name: "Dashboard Visual Check"
    note: "Requires browser inspection"
```

## Outputs

| Output | Location | Description |
|--------|----------|-------------|
| automatable | Array | Scenarios to execute automatically |
| semi_automated | Array | Scenarios needing setup + execution |
| manual | Array | Scenarios requiring human verification |
| classification_summary | Console | Counts per category |

## Completion Signal

```
SCENARIOS_CLASSIFIED: {automatable}/{semi_automated}/{manual}
```

## Example Output

```
[UAT] Classifying 9 scenarios...
  [AUTO] Scenario 1: Project Initialization
  [AUTO] Scenario 2: Configuration Setup
  [AUTO] Scenario 3: Database Migration
  [AUTO] Scenario 4: Connection Validation
  [AUTO] Scenario 5: Worker Process Startup
  [AUTO] Scenario 6: Job Queue Testing
  [SEMI] Scenario 7: Email Notification
  [SEMI] Scenario 8: Webhook Delivery
  [MANUAL] Scenario 9: Dashboard Visual Check

SCENARIOS_CLASSIFIED: 6/2/1
```

## Classification Confidence

For edge cases, use this priority:
1. If command is clearly present → Automatable
2. If command present but requires setup → Semi-automated
3. If no command detected → Manual

When in doubt, classify as semi-automated (attempts execution, flags for review).
