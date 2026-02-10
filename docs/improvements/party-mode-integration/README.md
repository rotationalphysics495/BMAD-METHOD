---
title: Party Mode Integration with Epic Execute
---

# Party Mode Integration with Epic Execute

**Status**: Planning
**Version**: 1.0.0
**Date**: 2026-01-03

---

## Overview

This folder contains the complete documentation for integrating Party Mode's multi-agent collaboration capabilities into the Epic Execute and Epic Chain workflows.

## Documents

| Document | Description |
|----------|-------------|
| [01-implementation-plan.md](./01-implementation-plan.md) | High-level implementation plan with CLI flags, configuration, and phases |
| [02-context-management.md](./02-context-management.md) | Deep dive into context isolation architecture and data transfer mechanisms |
| [03-file-modifications.md](./03-file-modifications.md) | Detailed specification of all file changes required |
| 04-prompt-engineering.md | Prompt templates for each party phase (future - not yet created) |

## Quick Links

- **Why Party Mode?** See [Benefits Analysis](#benefits-of-integration)
- **How does context work?** See [02-context-management.md](./02-context-management.md)
- **What files change?** See [03-file-modifications.md](./03-file-modifications.md)

---

## Benefits of Integration

### Current Pain Points

| Pain Point | Impact |
|------------|--------|
| Architectural issues found mid-implementation | Costly rework, context loss |
| Single-perspective code review | Missed issues in blind spots |
| Shallow context handoffs in epic-chain | Next epic starts without learnings |
| Silent failures with only logged errors | No actionable remediation guidance |

### Party Mode Solutions

| Party Phase | Addresses |
|-------------|-----------|
| **Story Kickoff Party** | Surfaces architectural/implementation/testing concerns before coding |
| **Party Review** | Multi-perspective code review catches more issue categories |
| **Failure Analysis Party** | Root cause analysis with actionable remediation |
| **Post-Epic Retrospective** | Rich context handoffs, documented patterns and lessons |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                   ENHANCED EPIC EXECUTE FLOW                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Per Story:                                                          │
│  ┌──────────────┐                                                   │
│  │ PARTY:       │ ← --party-kickoff (optional)                     │
│  │ Kickoff      │   Agents: Winston + Amelia + Murat                │
│  └──────┬───────┘                                                   │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ Dev Phase    │───►│ Review Phase │───►│ Commit       │          │
│  │ (Context A)  │    │ Standard OR  │    │ (Shell)      │          │
│  │              │    │ PARTY Review │    │              │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│         │                                                            │
│         ▼ (on failure)                                              │
│  ┌──────────────┐                                                   │
│  │ PARTY:       │ ← --party-failure (optional)                     │
│  │ Failure      │                                                   │
│  │ Analysis     │                                                   │
│  └──────────────┘                                                   │
│                                                                      │
│  Post-Epic:                                                          │
│  ┌──────────────┐    ┌──────────────┐                              │
│  │ UAT          │    │ PARTY:       │ ← --party-retro (optional)   │
│  │ Generation   │    │ Retrospective│                              │
│  └──────────────┘    └──────────────┘                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## CLI Usage

```bash
# Enable individual party phases
./epic-execute.sh 42 --party-kickoff
./epic-execute.sh 42 --party-review
./epic-execute.sh 42 --party-failure
./epic-execute.sh 42 --party-retro

# Enable all party phases
./epic-execute.sh 42 --party-all

# Custom agents for a phase
./epic-execute.sh 42 --party-review --party-agents "Winston,Murat"

# Combine with existing flags
./epic-execute.sh 42 --party-all --skip-done --verbose
```

---

## Implementation Phases

| Phase | Priority | Scope |
|-------|----------|-------|
| **Phase 1** | High | CLI flags + Story Kickoff Party |
| **Phase 2** | High | Party Review (multi-agent code review) |
| **Phase 3** | Medium | Failure Analysis Party |
| **Phase 4** | Medium | Retrospective + epic-chain handoff integration |
| **Phase 5** | Low | Polish (TTS, metrics, comprehensive docs) |

---

## Related Documents

- [Epic Workflows v1 Improvements](../epic-workflows-v1.md) - General workflow improvements
- Party Mode Core Docs: `src/core/workflows/party-mode/workflow.md`
- Epic Execute Workflow: `src/modules/bmm/workflows/4-implementation/epic-execute/workflow.md`

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-03 | Option B: Configurable flags | Opt-in approach preserves existing behavior, allows gradual adoption |
| 2026-01-03 | File-based context transfer | Maintains context isolation while enabling information flow |
| 2026-01-03 | Non-blocking kickoff | Kickoff insights are helpful but not critical path |
