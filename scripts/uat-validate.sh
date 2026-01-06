#!/bin/bash
#
# BMAD UAT Validate - Automated UAT Scenario Execution with Self-Healing Fix Loop
#
# Usage: ./uat-validate.sh <epic-id> [options]
#
# Options:
#   --gate-mode=MODE    Validation mode: quick|full|skip (default: quick)
#   --max-retries=N     Max fix attempts before halt (default: 2)
#   --skip-manual       Skip manual-only scenarios (default: skip)
#   --verbose           Show detailed output
#   --dry-run           Show what would be executed without running
#   --timeout=SECONDS   Timeout per scenario (default: 30)
#
# Exit Codes:
#   0 - UAT PASS (all automatable scenarios passed)
#   1 - UAT FAIL (fixable, retries remain or self-heal succeeded)
#   2 - UAT FAIL (max retries exceeded)
#

set -e

# =============================================================================
# Section 1: Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BMAD_DIR="$PROJECT_ROOT/.bmad"

UAT_DIR="$PROJECT_ROOT/docs/uat"
SPRINT_ARTIFACTS_DIR="$PROJECT_ROOT/docs/sprint-artifacts"
METRICS_DIR="$SPRINT_ARTIFACTS_DIR/metrics"
FIX_DIR="$SPRINT_ARTIFACTS_DIR/uat-fixes"
STORIES_DIR="$PROJECT_ROOT/docs/stories"

LOG_FILE="/tmp/bmad-uat-validate-$$.log"

# Default configuration
UAT_GATE_MODE="quick"
MAX_RETRIES=2
SKIP_MANUAL=true
VERBOSE=false
DRY_RUN=false
TIMEOUT_SECONDS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Section 2: Helper Functions
# =============================================================================

log() {
    echo -e "${BLUE}[UAT]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PASS] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FAIL] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_section() {
    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}───────────────────────────────────────────────────────────${NC}"
}

log_header() {
    echo ""
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Section 3: Argument Parsing
# =============================================================================

EPIC_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --gate-mode=*)
            UAT_GATE_MODE="${1#*=}"
            shift
            ;;
        --max-retries=*)
            MAX_RETRIES="${1#*=}"
            shift
            ;;
        --skip-manual)
            SKIP_MANUAL=true
            shift
            ;;
        --include-manual)
            SKIP_MANUAL=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --timeout=*)
            TIMEOUT_SECONDS="${1#*=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            EPIC_ID="$1"
            shift
            ;;
    esac
done

if [ -z "$EPIC_ID" ]; then
    echo "Usage: $0 <epic-id> [options]"
    echo ""
    echo "Options:"
    echo "  --gate-mode=MODE    Validation mode: quick|full|skip (default: quick)"
    echo "  --max-retries=N     Max fix attempts before halt (default: 2)"
    echo "  --skip-manual       Skip manual-only scenarios (default)"
    echo "  --include-manual    Include manual scenarios in checklist"
    echo "  --verbose           Detailed output"
    echo "  --dry-run           Show what would be executed"
    echo "  --timeout=SECONDS   Timeout per scenario (default: 30)"
    echo ""
    echo "Exit Codes:"
    echo "  0 - UAT PASS"
    echo "  1 - UAT FAIL (fixable)"
    echo "  2 - UAT FAIL (max retries exceeded)"
    exit 1
fi

# Validate gate mode
if [[ ! "$UAT_GATE_MODE" =~ ^(quick|full|skip)$ ]]; then
    echo "Invalid gate mode: $UAT_GATE_MODE"
    echo "Valid modes: quick, full, skip"
    exit 1
fi

# =============================================================================
# Section 4: UAT Document Loading
# =============================================================================

load_uat_document() {
    local epic_id="$1"

    # Find UAT document (try multiple patterns)
    UAT_FILE=""
    for pattern in "epic-${epic_id}-uat.md" "epic-0${epic_id}-uat.md" "${epic_id}-uat.md"; do
        found=$(find "$UAT_DIR" -name "$pattern" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            UAT_FILE="$found"
            break
        fi
    done

    if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
        log_error "UAT document not found for Epic $epic_id"
        log_error "Searched in: $UAT_DIR"
        log_error "Expected: epic-${epic_id}-uat.md"
        return 1
    fi

    log "Found UAT document: $UAT_FILE"

    # Validate structure - check for scenarios section
    if ! grep -qE "^##.*[Ss]cenario|^##.*[Tt]est|^##.*[Cc]riteria" "$UAT_FILE"; then
        log_warn "UAT document may not have standard scenario sections"
    fi

    # Count scenario blocks (lines starting with ### or numbered items under Test Scenarios)
    SCENARIO_COUNT=$(grep -cE "^###|^[0-9]+\." "$UAT_FILE" 2>/dev/null || echo "0")
    log "Found approximately $SCENARIO_COUNT scenario entries"

    return 0
}

# =============================================================================
# Section 5: Scenario Classification
# =============================================================================

# Arrays to store classified scenarios
declare -a AUTOMATABLE_SCENARIOS
declare -a SEMI_AUTO_SCENARIOS
declare -a MANUAL_SCENARIOS

classify_scenarios() {
    local uat_file="$1"

    # Reset arrays
    AUTOMATABLE_SCENARIOS=()
    SEMI_AUTO_SCENARIOS=()
    MANUAL_SCENARIOS=()

    # Read the UAT file and extract scenario blocks
    local current_scenario=""
    local current_name=""
    local in_scenario=false
    local scenario_num=0

    while IFS= read -r line; do
        # Detect scenario headers (### or numbered items)
        if [[ "$line" =~ ^###[[:space:]]*(.*) ]] || [[ "$line" =~ ^([0-9]+)\.[[:space:]]+(.*) ]]; then
            # Save previous scenario if exists
            if [ -n "$current_scenario" ]; then
                classify_single_scenario "$scenario_num" "$current_name" "$current_scenario"
            fi

            # Start new scenario
            ((scenario_num++))
            if [[ "$line" =~ ^###[[:space:]]*(.*) ]]; then
                current_name="${BASH_REMATCH[1]}"
            else
                current_name="${BASH_REMATCH[2]}"
            fi
            current_scenario="$line"
            in_scenario=true
        elif [ "$in_scenario" = true ]; then
            # Continue accumulating scenario content
            current_scenario+=$'\n'"$line"
        fi
    done < "$uat_file"

    # Handle last scenario
    if [ -n "$current_scenario" ]; then
        classify_single_scenario "$scenario_num" "$current_name" "$current_scenario"
    fi

    log "Classification complete:"
    log "  Automatable: ${#AUTOMATABLE_SCENARIOS[@]}"
    log "  Semi-auto:   ${#SEMI_AUTO_SCENARIOS[@]}"
    log "  Manual:      ${#MANUAL_SCENARIOS[@]}"
}

classify_single_scenario() {
    local id="$1"
    local name="$2"
    local content="$3"

    # Check for automatable indicators
    if echo "$content" | grep -qiE 'npx|npm run|yarn|node |curl |wget |pytest|jest|vitest|--version|/health|/api/|exit code|returns [0-9]|\.sh |bash '; then
        # Extract command from code block if present
        local cmd=""
        cmd=$(echo "$content" | grep -oE '`[^`]+`' | head -1 | tr -d '`')
        if [ -z "$cmd" ]; then
            cmd=$(echo "$content" | grep -oE 'npx [a-zA-Z0-9_-]+.*|npm run [a-zA-Z0-9_:-]+.*|curl [^[:space:]]+.*' | head -1)
        fi
        AUTOMATABLE_SCENARIOS+=("$id|$name|$cmd")
        [ "$VERBOSE" = true ] && log "  [AUTO] Scenario $id: $name"

    # Check for semi-automated indicators
    elif echo "$content" | grep -qiE 'test-send|email|inbox|check your|verify.*manually|setup.*first|start.*server'; then
        SEMI_AUTO_SCENARIOS+=("$id|$name|")
        [ "$VERBOSE" = true ] && log "  [SEMI] Scenario $id: $name"

    # Everything else is manual
    else
        MANUAL_SCENARIOS+=("$id|$name|")
        [ "$VERBOSE" = true ] && log "  [MANUAL] Scenario $id: $name"
    fi
}

# =============================================================================
# Section 6: Scenario Execution
# =============================================================================

# Arrays to store results
declare -a PASSED_SCENARIOS
declare -a FAILED_SCENARIOS
declare -a FAILED_DETAILS

execute_scenarios() {
    local gate_mode="$1"

    # Reset results
    PASSED_SCENARIOS=()
    FAILED_SCENARIOS=()
    FAILED_DETAILS=()

    # Skip mode - pass automatically
    if [ "$gate_mode" = "skip" ]; then
        log "Gate mode: skip - bypassing scenario execution"
        echo "UAT_GATE_RESULT: PASS"
        echo "UAT_SCENARIOS_PASSED: 0/0 (skipped)"
        return 0
    fi

    # Select scenarios based on gate mode
    local scenarios_to_run=()
    if [ "$gate_mode" = "quick" ]; then
        scenarios_to_run=("${AUTOMATABLE_SCENARIOS[@]}")
    elif [ "$gate_mode" = "full" ]; then
        scenarios_to_run=("${AUTOMATABLE_SCENARIOS[@]}" "${SEMI_AUTO_SCENARIOS[@]}")
    fi

    if [ ${#scenarios_to_run[@]} -eq 0 ]; then
        log_warn "No automatable scenarios found - gate passes by default"
        echo "UAT_GATE_RESULT: PASS"
        echo "UAT_SCENARIOS_PASSED: 0/0 (none automatable)"
        return 0
    fi

    log_section "Executing ${#scenarios_to_run[@]} Scenarios"

    for scenario_entry in "${scenarios_to_run[@]}"; do
        IFS='|' read -r scenario_id scenario_name scenario_cmd <<< "$scenario_entry"

        execute_single_scenario "$scenario_id" "$scenario_name" "$scenario_cmd"
    done

    # Report results
    local total=${#scenarios_to_run[@]}
    local passed=${#PASSED_SCENARIOS[@]}
    local failed=${#FAILED_SCENARIOS[@]}

    echo ""
    log "Results: $passed/$total passed"

    if [ $failed -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

execute_single_scenario() {
    local scenario_id="$1"
    local scenario_name="$2"
    local scenario_cmd="$3"

    echo ""
    log "Scenario $scenario_id: $scenario_name"

    # If no command extracted, try to infer from name
    if [ -z "$scenario_cmd" ]; then
        log_warn "  No command detected - marking as manual verification needed"
        FAILED_SCENARIOS+=("$scenario_id")
        FAILED_DETAILS+=("$scenario_id|$scenario_name|No automatable command found|manual|1")
        return 1
    fi

    if [ "$VERBOSE" = true ]; then
        log "  Command: $scenario_cmd"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would execute: $scenario_cmd"
        PASSED_SCENARIOS+=("$scenario_id")
        return 0
    fi

    # Execute with timeout
    local start_time=$(date +%s%N)
    local output=""
    local exit_code=0
    local stderr_file="/tmp/uat-stderr-$$.txt"

    # Run command with timeout
    set +e
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout "$TIMEOUT_SECONDS" bash -c "$scenario_cmd" 2>"$stderr_file")
        exit_code=$?
        # timeout returns 124 on timeout
        if [ $exit_code -eq 124 ]; then
            exit_code=124
        fi
    else
        # macOS fallback using perl
        output=$(perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT_SECONDS" bash -c "$scenario_cmd" 2>"$stderr_file")
        exit_code=$?
    fi
    set -e

    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    local stderr=""
    [ -f "$stderr_file" ] && stderr=$(cat "$stderr_file")
    rm -f "$stderr_file"

    # Evaluate result
    if [ $exit_code -eq 0 ]; then
        log_success "  Scenario $scenario_id: PASS (${duration_ms}ms)"
        PASSED_SCENARIOS+=("$scenario_id")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scenario $scenario_id PASS: $scenario_cmd" >> "$LOG_FILE"
    elif [ $exit_code -eq 124 ]; then
        log_error "  Scenario $scenario_id: FAIL (timeout after ${TIMEOUT_SECONDS}s)"
        FAILED_SCENARIOS+=("$scenario_id")
        FAILED_DETAILS+=("$scenario_id|$scenario_name|$scenario_cmd|timeout|$exit_code|$output|$stderr")
    else
        log_error "  Scenario $scenario_id: FAIL (exit code $exit_code)"
        if [ -n "$stderr" ] && [ "$VERBOSE" = true ]; then
            echo "    Error: $stderr"
        fi
        FAILED_SCENARIOS+=("$scenario_id")
        FAILED_DETAILS+=("$scenario_id|$scenario_name|$scenario_cmd|error|$exit_code|$output|$stderr")
    fi

    return $exit_code
}

# =============================================================================
# Section 7: Gate Evaluation
# =============================================================================

evaluate_gate() {
    local total=${#AUTOMATABLE_SCENARIOS[@]}
    local passed=${#PASSED_SCENARIOS[@]}
    local failed=${#FAILED_SCENARIOS[@]}

    log_section "Gate Evaluation"

    if [ $failed -eq 0 ]; then
        log_success "All automatable scenarios passed"
        return 0
    else
        log_error "$failed scenario(s) failed"
        return 1
    fi
}

# =============================================================================
# Section 8: Self-Healing Loop
# =============================================================================

generate_fix_context() {
    local epic_id="$1"
    local attempt="$2"

    mkdir -p "$FIX_DIR"

    local fix_file="$FIX_DIR/epic-${epic_id}-fix-context-${attempt}.md"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Find template
    local template="$PROJECT_ROOT/src/modules/bmm/workflows/5-validation/uat-validate/uat-fix-context-template.md"

    if [ -f "$template" ]; then
        # Render template with basic variable substitution
        sed -e "s/{epic_id}/$epic_id/g" \
            -e "s/{attempt}/$attempt/g" \
            -e "s/{timestamp}/$timestamp/g" \
            -e "s/{max_retries}/$MAX_RETRIES/g" \
            -e "s/{next_attempt}/$((attempt + 1))/g" \
            -e "s/{failure_count}/${#FAILED_SCENARIOS[@]}/g" \
            -e "s|{uat_doc_path}|$UAT_FILE|g" \
            "$template" > "$fix_file"
    else
        # Create minimal fix context without template
        cat > "$fix_file" << EOF
# UAT Fix Context - Epic $epic_id (Attempt $attempt)

**Generated:** $timestamp
**Epic:** $epic_id
**Gate Result:** FAIL (${#PASSED_SCENARIOS[@]}/${#AUTOMATABLE_SCENARIOS[@]} scenarios passed)

---

## Summary

This document contains the context needed to fix UAT failures for Epic $epic_id.

**Failures to fix:** ${#FAILED_SCENARIOS[@]}
**Fix attempt:** $attempt of $MAX_RETRIES

---

EOF
    fi

    # Append failed scenarios details
    echo "" >> "$fix_file"
    echo "## Failed Scenarios" >> "$fix_file"
    echo "" >> "$fix_file"

    for detail in "${FAILED_DETAILS[@]}"; do
        IFS='|' read -r scenario_id scenario_name cmd error_type exit_code output stderr <<< "$detail"

        cat >> "$fix_file" << EOF
### Scenario $scenario_id: $scenario_name

**Command Executed:**
\`\`\`bash
$cmd
\`\`\`

**Error Type:** $error_type
**Exit Code:** $exit_code

**Output:**
\`\`\`
$output
\`\`\`

**Error Output:**
\`\`\`
$stderr
\`\`\`

---

EOF
    done

    # Add context references section
    cat >> "$fix_file" << EOF

## Context References

The following files provide additional context for fixing these failures:

| File | Purpose |
|------|---------|
| \`$UAT_FILE\` | Full UAT document with all scenarios |
| \`$STORIES_DIR/${epic_id}-*\` | Story files with acceptance criteria |
| \`$METRICS_DIR/epic-${epic_id}-metrics.yaml\` | Execution metrics |

## Fix Instructions

Address the failures above in priority order. For each fix:

1. **Analyze** - Understand why the scenario failed
2. **Locate** - Find the relevant code files
3. **Fix** - Implement the minimum change to resolve the failure
4. **Verify** - Run the scenario command locally to confirm fix
5. **Commit** - Use message format: \`fix(epic-$epic_id): {description}\`

### Constraints

- Only fix the identified failures - do not refactor unrelated code
- Run the specific failing commands to verify each fix
- Run project tests after all fixes: \`npm test\`
- If a fix requires changes that would break other scenarios, document the tradeoff

## After Fixing

Once all fixes are committed, the UAT validation will automatically re-run.

- **If all pass:** Epic continues to next phase
- **If failures remain:** Another fix context will be generated (attempt $((attempt + 1)))
- **If max retries exceeded:** Chain halts for human intervention

---

*Generated by UAT Validate Workflow*
*BMAD Method - Epic Chain Self-Healing*
*Fix Context: epic-${epic_id}-fix-context-${attempt}.md*
EOF

    log "Fix context generated: $fix_file"
    echo "$fix_file"
}

run_quick_dev_fix() {
    local fix_context_file="$1"
    local epic_id="$2"
    local attempt="$3"

    log "Spawning quick-dev fix session (attempt $attempt/$MAX_RETRIES)"

    local fix_prompt="You are Barry, the Quick Flow Solo Dev.

Load and process this fix context document:
$fix_context_file

Your task:
1. Read the failed scenarios and error details from the fix context
2. Analyze root cause for each failure
3. Implement targeted fixes
4. Run the failing commands to verify fixes
5. Stage changes: git add -A
6. Commit with message: fix(epic-${epic_id}): UAT fix #${attempt}

Constraints:
- Only fix the identified failures
- Do not refactor unrelated code
- Run tests after fixes

When done, output exactly:
FIX_COMPLETE: {number_fixed}/${#FAILED_SCENARIOS[@]}"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would spawn Claude for fixes with prompt:"
        echo "  Fix context: $fix_context_file"
        return 0
    fi

    # Execute in isolated context
    local result
    result=$(claude --dangerously-skip-permissions -p "$fix_prompt" 2>&1) || true

    echo "$result" >> "$LOG_FILE"

    if echo "$result" | grep -q "FIX_COMPLETE"; then
        log_success "Quick-dev fix session completed"
        return 0
    else
        log_warn "Quick-dev fix session may not have completed cleanly"
        return 1
    fi
}

self_healing_loop() {
    local epic_id="$1"
    local attempt=0

    while [ $attempt -lt $MAX_RETRIES ]; do
        ((attempt++))

        log_section "Self-Healing Fix Loop (Attempt $attempt/$MAX_RETRIES)"

        # Generate fix context
        local fix_file
        fix_file=$(generate_fix_context "$epic_id" "$attempt")

        # Run quick-dev fix
        if ! run_quick_dev_fix "$fix_file" "$epic_id" "$attempt"; then
            log_warn "Fix attempt $attempt may have issues"
        fi

        # Re-run validation
        log "Re-validating after fix attempt $attempt..."

        # Reset and re-execute
        PASSED_SCENARIOS=()
        FAILED_SCENARIOS=()
        FAILED_DETAILS=()

        if execute_scenarios "$UAT_GATE_MODE"; then
            log_success "UAT passed after fix attempt $attempt"
            return 0
        fi

        log_warn "UAT still failing after attempt $attempt"
    done

    log_error "Max retries ($MAX_RETRIES) exceeded"
    return 2
}

# =============================================================================
# Section 9: Output Signals and Metrics
# =============================================================================

update_metrics() {
    local epic_id="$1"
    local gate_status="$2"
    local fix_attempts="$3"

    mkdir -p "$METRICS_DIR"

    local metrics_file="$METRICS_DIR/epic-${epic_id}-metrics.yaml"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Check if yq is available for YAML manipulation
    if command -v yq >/dev/null 2>&1; then
        if [ -f "$metrics_file" ]; then
            yq -i ".validation.gate_executed = true" "$metrics_file"
            yq -i ".validation.gate_status = \"$gate_status\"" "$metrics_file"
            yq -i ".validation.fix_attempts = $fix_attempts" "$metrics_file"
            yq -i ".validation.scenarios_passed = ${#PASSED_SCENARIOS[@]}" "$metrics_file"
            yq -i ".validation.scenarios_failed = ${#FAILED_SCENARIOS[@]}" "$metrics_file"
            yq -i ".validation.timestamp = \"$timestamp\"" "$metrics_file"
        else
            # Create new metrics file
            cat > "$metrics_file" << EOF
epic_id: "$epic_id"
validation:
  gate_executed: true
  gate_status: "$gate_status"
  fix_attempts: $fix_attempts
  scenarios_passed: ${#PASSED_SCENARIOS[@]}
  scenarios_failed: ${#FAILED_SCENARIOS[@]}
  timestamp: "$timestamp"
EOF
        fi
    else
        # Fallback: append to file or create new
        if [ ! -f "$metrics_file" ]; then
            cat > "$metrics_file" << EOF
epic_id: "$epic_id"
validation:
  gate_executed: true
  gate_status: "$gate_status"
  fix_attempts: $fix_attempts
  scenarios_passed: ${#PASSED_SCENARIOS[@]}
  scenarios_failed: ${#FAILED_SCENARIOS[@]}
  timestamp: "$timestamp"
EOF
        else
            # Simple append for validation section
            log_warn "yq not found - metrics update may be incomplete"
        fi
    fi

    log "Metrics updated: $metrics_file"
}

output_signals() {
    local gate_status="$1"
    local fix_attempts="$2"

    local total=${#AUTOMATABLE_SCENARIOS[@]}
    local passed=${#PASSED_SCENARIOS[@]}

    echo ""
    echo "UAT_GATE_RESULT: $gate_status"
    echo "UAT_FIX_ATTEMPTS: $fix_attempts"
    echo "UAT_SCENARIOS_PASSED: $passed/$total"
}

print_summary() {
    local gate_status="$1"
    local fix_attempts="$2"

    log_header "UAT VALIDATION COMPLETE"

    echo "  Epic:              $EPIC_ID"
    echo "  Gate Mode:         $UAT_GATE_MODE"
    echo "  Gate Result:       $gate_status"
    echo ""
    echo "  Scenarios:"
    echo "    Automatable:     ${#AUTOMATABLE_SCENARIOS[@]}"
    echo "    Semi-automated:  ${#SEMI_AUTO_SCENARIOS[@]}"
    echo "    Manual:          ${#MANUAL_SCENARIOS[@]}"
    echo ""
    echo "  Results:"
    echo "    Passed:          ${#PASSED_SCENARIOS[@]}"
    echo "    Failed:          ${#FAILED_SCENARIOS[@]}"
    echo "    Fix Attempts:    $fix_attempts"
    echo ""
    echo "  Artifacts:"
    echo "    Log:             $LOG_FILE"
    echo "    UAT Document:    $UAT_FILE"
    if [ ${#FAILED_SCENARIOS[@]} -gt 0 ] && [ -d "$FIX_DIR" ]; then
        echo "    Fix Contexts:    $FIX_DIR/"
    fi
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

log_header "UAT VALIDATION: Epic $EPIC_ID"
log "Gate mode: $UAT_GATE_MODE"
log "Max retries: $MAX_RETRIES"
log "Timeout: ${TIMEOUT_SECONDS}s"

# Ensure directories exist
mkdir -p "$METRICS_DIR"
mkdir -p "$FIX_DIR"

# Step 1: Load UAT document
log_section "Loading UAT Document"
if ! load_uat_document "$EPIC_ID"; then
    echo "UAT_GATE_RESULT: FAIL"
    echo "UAT_FIX_ATTEMPTS: 0"
    echo "UAT_SCENARIOS_PASSED: 0/0"
    exit 1
fi

# Step 2: Classify scenarios
log_section "Classifying Scenarios"
classify_scenarios "$UAT_FILE"

# Step 3: Execute scenarios
if ! execute_scenarios "$UAT_GATE_MODE"; then
    # Gate failed - check if we should try self-healing
    if [ "$DRY_RUN" = false ] && [ $MAX_RETRIES -gt 0 ]; then
        if ! self_healing_loop "$EPIC_ID"; then
            # Max retries exceeded
            update_metrics "$EPIC_ID" "FAIL" "$MAX_RETRIES"
            output_signals "FAIL" "$MAX_RETRIES"
            print_summary "FAIL" "$MAX_RETRIES"
            exit 2
        fi
    else
        # No self-healing or dry-run
        update_metrics "$EPIC_ID" "FAIL" "0"
        output_signals "FAIL" "0"
        print_summary "FAIL" "0"
        exit 1
    fi
fi

# Step 4: Gate passed
FINAL_ATTEMPTS=0
if [ ${#FAILED_SCENARIOS[@]} -gt 0 ]; then
    # Passed after retries
    FINAL_ATTEMPTS=$((MAX_RETRIES - $(ls -1 "$FIX_DIR"/epic-${EPIC_ID}-fix-context-*.md 2>/dev/null | wc -l) + 1))
fi

update_metrics "$EPIC_ID" "PASS" "$FINAL_ATTEMPTS"
output_signals "PASS" "$FINAL_ATTEMPTS"
print_summary "PASS" "$FINAL_ATTEMPTS"

log_success "UAT validation passed for Epic $EPIC_ID"
exit 0
