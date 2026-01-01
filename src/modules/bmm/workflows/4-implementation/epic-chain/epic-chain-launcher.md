# Epic Chain Launcher

This workflow orchestrates the execution of multiple epics in sequence with cross-epic analysis and context sharing.

## Instructions

When the user invokes `*epic-chain`, follow these steps:

### Step 1: Gather Epic IDs

Ask the user which epics to chain. Accept input in any of these formats:
- Space-separated: `36 37 38`
- Comma-separated: `36, 37, 38`
- Range: `36-38` (expands to 36, 37, 38)

Validate each epic ID:
1. Check that epic file exists at `docs/epics/epic-{id}-*.md`
2. Check that stories exist for each epic

### Step 2: Run Analysis Phase

Before execution, analyze all epics to understand:

1. **Load all epic files** - Read the full content of each epic
2. **Load all story files** - Read stories for each epic
3. **Detect dependencies**:
   - Look for explicit `## Dependencies` sections in epic files
   - Scan for shared patterns (database tables, API endpoints, components)
   - Identify stories that reference other epics' outputs

4. **Build execution plan**:
   - Determine optimal epic order (respecting dependencies)
   - Identify cross-cutting concerns
   - Flag risk areas
   - Note parallel execution opportunities within epics

### Step 3: Present Chain Plan

Display the analysis results to the user:

```
═══════════════════════════════════════════════════════════
                    EPIC CHAIN ANALYSIS
═══════════════════════════════════════════════════════════

Epics to Execute: 36, 37, 38
Total Stories: 24

EXECUTION ORDER
───────────────────────────────────────────────────────────
1. Epic 36: Content Management (8 stories)
   Dependencies: None
   Complexity: Medium

2. Epic 37: Search Enhancement (3 stories)
   Dependencies: Epic 36 (uses content patterns)
   Complexity: Low

3. Epic 38: Security Hardening (4 stories)
   Dependencies: Epic 36, 37
   Complexity: High

CROSS-CUTTING CONCERNS
───────────────────────────────────────────────────────────
• Database migrations span epics 36, 37
• API versioning affects epics 36, 38

RISK AREAS
───────────────────────────────────────────────────────────
• Story 38-3: Complex search integration
  Mitigation: Comprehensive test coverage

═══════════════════════════════════════════════════════════
```

### Step 4: Get User Approval

Ask the user to confirm:
- **Approve**: Proceed with execution
- **Modify**: Reorder epics or exclude some
- **Analyze Only**: Save plan but don't execute

### Step 5: Provide Execution Command

If approved, provide the shell command:

**Dry run (recommended first):**
```bash
./.bmad/scripts/epic-chain.sh 36 37 38 --dry-run --verbose
```

**Full execution:**
```bash
./.bmad/scripts/epic-chain.sh 36 37 38
```

**Resume from specific epic:**
```bash
./.bmad/scripts/epic-chain.sh 36 37 38 --start-from 37
```

### Step 6: Explain Execution Flow

The chain execution will:

1. **For each epic in order:**
   - Load context handoff from previous epic (if any)
   - Execute all stories via `epic-execute.sh`
   - Generate epic completion summary
   - Create context handoff for next epic

2. **After all epics complete:**
   - Generate combined UAT document
   - Update `sprint-status.yaml`
   - Display chain execution summary

### Context Handoff

Between epics, the workflow generates a handoff document containing:
- Patterns established (coding conventions, architectural decisions)
- Key decisions made during implementation
- Gotchas and lessons learned
- Files to reference for the next epic

This ensures each subsequent epic benefits from learnings without context window pollution.

## Analysis Depth Options

- **quick**: Basic dependency check, file existence validation
- **standard**: Full epic/story analysis, pattern detection, risk assessment
- **thorough**: Deep code analysis, test coverage review, performance considerations

Set via: `./.bmad/scripts/epic-chain.sh 36 37 38 --analysis thorough`
