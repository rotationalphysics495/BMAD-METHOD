# Epic Chain Workflow

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0.0 |
| Trigger | `epic-chain` |
| Agent | SM (Scrum Master) |
| Category | Implementation |
| Complexity | High |

## Purpose

Analyze multiple epics to understand cross-epic dependencies, shared patterns, and optimal execution order, then execute them in sequence with coordinated context sharing. Unlike single-epic execution, this workflow:

1. **Analyzes** all epics before execution to identify relationships
2. **Plans** optimal story ordering across epic boundaries
3. **Shares context** between epics (patterns learned, decisions made)
4. **Chains** execution seamlessly from one epic to the next

## When to Use

- Executing multiple related epics (e.g., Epic 36, 37, 38)
- Epics that build on each other's foundations
- Release planning where multiple epics form a cohesive delivery
- When you want analysis before committing to execution

## Workflow Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│                       EPIC CHAIN FLOW                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    PHASE 1: ANALYSIS                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │    │
│  │  │ Load Epics  │→ │  Detect     │→ │  Build      │          │    │
│  │  │ & Stories   │  │ Dependencies│  │ Chain Plan  │          │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    PHASE 2: APPROVAL                         │    │
│  │  Present chain plan → User reviews → Approve/Modify          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    PHASE 3: EXECUTION                        │    │
│  │                                                               │    │
│  │  For each epic in chain:                                      │    │
│  │  ┌─────────────────────────────────────────────────────┐     │    │
│  │  │  Execute via epic-execute.sh                         │     │    │
│  │  │  ├─ Dev Phase (per story)                           │     │    │
│  │  │  ├─ Review Phase (per story)                        │     │    │
│  │  │  └─ Commit (per story)                              │     │    │
│  │  └─────────────────────────────────────────────────────┘     │    │
│  │                          ↓                                    │    │
│  │  ┌─────────────────────────────────────────────────────┐     │    │
│  │  │  Generate cross-epic context handoff                 │     │    │
│  │  │  (Patterns learned, decisions made, gotchas)         │     │    │
│  │  └─────────────────────────────────────────────────────┘     │    │
│  │                          ↓                                    │    │
│  │  Next epic receives handoff context...                        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              ↓                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    PHASE 4: WRAP-UP                          │    │
│  │  ├─ Generate combined UAT document                           │    │
│  │  ├─ Chain execution summary                                  │    │
│  │  └─ Update sprint-status.yaml                                │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Analysis Capabilities

The analysis phase examines:

### 1. Cross-Epic Dependencies
- Shared database models/migrations
- Shared API endpoints
- Shared components or utilities
- Feature flags or configuration dependencies

### 2. Story Ordering Optimization
- Stories that create foundations used by later stories
- Parallel execution opportunities
- Natural break points

### 3. Pattern Recognition
- Similar implementation patterns across epics
- Reusable code opportunities
- Consistency requirements

### 4. Risk Assessment
- Complex stories that might block others
- Integration points between epics
- Testing dependencies

## Chain Plan Output

The analysis produces a chain plan document:

```yaml
# chain-plan.yaml
generated: 2024-01-15T10:30:00
epics: [36, 37, 38]
total_stories: 24

execution_order:
  - epic: 36
    stories: [36-1, 36-2, 36-3, 36-4, 36-5, 36-6, 36-7, 36-8]
    estimated_complexity: medium
    dependencies: []

  - epic: 37
    stories: [37-1, 37-2, 37-3]
    estimated_complexity: low
    dependencies:
      - epic: 36
        reason: "Uses content management patterns from 36"

  - epic: 38
    stories: [38-1, 38-2, 38-3, 38-4]
    estimated_complexity: high
    dependencies:
      - epic: 36
        reason: "Extends search functionality"
      - epic: 37
        reason: "Integrates with content workflow"

cross_cutting_concerns:
  - name: "Database migrations"
    affects: [36, 37]
    recommendation: "Run all migrations before story execution"

  - name: "API versioning"
    affects: [36, 38]
    recommendation: "Maintain backwards compatibility"

parallel_opportunities:
  - stories: [37-2, 37-3]
    reason: "Independent features with no shared code"

risk_areas:
  - story: 38-3
    risk: "Complex search integration"
    mitigation: "Extensive test coverage, staged rollout"
```

## Orchestration

This workflow uses shell orchestration similar to epic-execute:

```bash
# Analyze and plan (no execution)
./.bmad/scripts/epic-chain.sh 36 37 38 --analyze-only

# Execute with analysis
./.bmad/scripts/epic-chain.sh 36 37 38

# Resume from specific epic
./.bmad/scripts/epic-chain.sh 36 37 38 --start-from 37

# Skip already-done epics
./.bmad/scripts/epic-chain.sh 36 37 38 --skip-done
```

## Context Handoff Between Epics

After each epic completes, a handoff document is generated:

```markdown
# Epic 36 → Epic 37 Handoff

## Patterns Established
- Content validation using Zod schemas in `lib/validators/`
- API routes follow RESTful conventions with `/api/v1/` prefix
- All database queries use connection pooling

## Key Decisions Made
- Used PostgreSQL full-text search instead of Elasticsearch
- Implemented soft deletes for all content types

## Gotchas for Next Epic
- Rate limiting middleware must be added before auth middleware
- Content types require explicit registration in `types/content.ts`

## Files to Reference
- `lib/content/manager.ts` - Core content operations
- `lib/search/index.ts` - Search implementation patterns
```

## Usage

Via SM Agent:
```
/sm
*epic-chain
```

Via Shell (after planning):
```bash
./.bmad/scripts/epic-chain.sh 36 37 38
```

## Configuration

Optional settings in `bmad/_cfg/epic-chain.yaml`:

```yaml
# Analysis depth: quick | standard | thorough
analysis_depth: standard

# Auto-approve chain plan without user confirmation
auto_approve: false

# Generate combined UAT at end
combined_uat: true

# Share context between epics
context_handoff: true

# Parallel story execution within epics
parallel_within_epic: false
```
