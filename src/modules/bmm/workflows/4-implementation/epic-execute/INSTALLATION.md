# Epic Execute Workflow - Installation Guide

## Overview

The Epic Execute workflow automates the execution of all stories in an epic with context isolation between development and review phases, producing a User Acceptance Testing document for human validation.

## Prerequisites

- BMAD v6 installed in your project
- Claude Code CLI (`claude`) available in PATH
- Git repository initialized
- Node.js 18+ (for Claude Code)

## Installation

### Option 1: Copy to Existing BMAD Installation

Copy the workflow files to your project's BMAD installation:

```bash
# From the bmad-epic-execute directory
cp -r workflows/epic-execute /path/to/your/project/bmad/bmm/workflows/4-implementation/

# Copy the shell script
cp scripts/epic-execute.sh /path/to/your/project/bmad/scripts/

# Make executable
chmod +x /path/to/your/project/bmad/scripts/epic-execute.sh
```

### Option 2: Manual Installation

1. Create the workflow directory structure:

```bash
mkdir -p bmad/bmm/workflows/4-implementation/epic-execute/steps
mkdir -p bmad/bmm/workflows/4-implementation/epic-execute/templates
mkdir -p bmad/bmm/workflows/4-implementation/epic-execute/config
mkdir -p bmad/scripts
```

2. Copy all workflow files to the appropriate locations

3. Make the script executable:

```bash
chmod +x bmad/scripts/epic-execute.sh
```

## Directory Structure

After installation, you should have:

```
your-project/
├── bmad/
│   ├── bmm/
│   │   └── workflows/
│   │       └── 4-implementation/
│   │           └── epic-execute/
│   │               ├── workflow.md
│   │               ├── config/
│   │               │   └── default-config.yaml
│   │               ├── steps/
│   │               │   ├── step-01-init.md
│   │               │   ├── step-02-dev-story.md
│   │               │   ├── step-03-code-review.md
│   │               │   ├── step-04-generate-uat.md
│   │               │   └── step-05-summary.md
│   │               └── templates/
│   │                   └── uat-template.md
│   ├── scripts/
│   │   └── epic-execute.sh
│   └── _cfg/
│       └── epic-execute.yaml  (optional customization)
├── docs/
│   ├── epics/
│   │   └── epic-1.md
│   ├── stories/           (stories can be here)
│   │   ├── story-1.1-feature.md
│   │   └── story-1.2-feature.md
│   ├── sprints/           (OR stories can be here)
│   │   ├── story-1.1-feature.md
│   │   └── story-1.2-feature.md
│   └── uat/               (created during execution)
```

## Configuration

### Custom Configuration

To customize the workflow behavior, copy the default config:

```bash
cp bmad/bmm/workflows/4-implementation/epic-execute/config/default-config.yaml \
   bmad/_cfg/epic-execute.yaml
```

Edit `bmad/_cfg/epic-execute.yaml` to change settings.

### Key Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `execution.auto_commit` | `true` | Commit after each story |
| `review.mode` | `standard` | Review strictness level |
| `review.auto_fix_enabled` | `true` | Allow reviewer to fix issues |
| `context.isolate_phases` | `true` | Fresh context per phase |
| `uat.enabled` | `true` | Generate UAT document |
| `git.auto_push` | `false` | Push after commits |

## Usage

### Basic Usage

```bash
./bmad/scripts/epic-execute.sh <epic-id>

# Example
./bmad/scripts/epic-execute.sh 1
```

### With Options

```bash
# Dry run - see what would execute
./bmad/scripts/epic-execute.sh 1 --dry-run

# Skip code review (not recommended)
./bmad/scripts/epic-execute.sh 1 --skip-review

# Don't commit (stage only)
./bmad/scripts/epic-execute.sh 1 --no-commit

# Verbose output
./bmad/scripts/epic-execute.sh 1 --verbose
```

### Via SM Agent

You can also initiate via the SM agent:

```
/sm
*epic-execute 1
```

The agent will validate the epic and provide the shell command to run.

## Epic and Story Requirements

### Epic File Format

Your epic file should include:

```markdown
# Epic 1: Feature Name

## Goal
[What this epic delivers]

## Success Criteria
- [ ] Users can do X
- [ ] System handles Y

## Stories
- story-1.1: First feature
- story-1.2: Second feature
```

### Story File Format

Stories should include:

```markdown
# Story 1.1: Feature Name

## Status: Ready

## Epic: 1

## Description
As a [user], I can [action] so that [benefit]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Technical Context
[Implementation guidance]

## Files
- path/to/file.ts

## Dependencies
- None (or list story IDs)

## Dev Agent Record
<!-- Filled during execution -->
```

## Output

After execution, you'll have:

| Output | Location | Description |
|--------|----------|-------------|
| Updated Stories | `docs/stories/` | Marked Done with Dev Agent Record + Code Review Record |
| UAT Document | `docs/uat/epic-{id}-uat.md` | Human testing script |
| Execution Log | `docs/sprints/` | Detailed run log |

## Issue Fix Policy

The code review phase automatically fixes issues based on severity:

| Severity | Action |
|----------|--------|
| HIGH | Always fix (security, missing tests, error handling) |
| MEDIUM | Fix if total issues > 5 (pattern violations, edge cases) |
| LOW | Document only (naming, style) |

## Troubleshooting

### "Epic file not found"

Ensure your epic file matches one of these patterns:
- `docs/epics/epic-{id}.md`
- `docs/epics/{id}.md`

### "No stories found"

Stories are discovered from **both** `docs/stories/` and `docs/sprints/` by:
1. Grep for `Epic: {id}` in story files
2. Naming convention: `story-{epic}.{seq}-*.md` or `story-{epic}-*.md`

Check both locations:
```bash
# See what's in both directories
ls docs/stories/*.md docs/sprints/*.md 2>/dev/null

# Check if stories reference the epic
grep -l "Epic.*1" docs/stories/*.md docs/sprints/*.md 2>/dev/null
```

Ensure your stories reference the epic or follow the naming convention.

### "Claude command not found"

Install Claude Code CLI:
```bash
npm install -g @anthropic/claude-code
```

### Context Not Clearing

Each `claude -p` invocation creates a fresh context. If you're seeing context bleed, ensure you're using the shell script (not running steps manually in one session).

## Integration with BMAD Workflow

This workflow fits into the BMAD methodology as:

```
Phase 3: Solutioning
  └── create-epics-and-stories  →  Epic + Story files

Phase 4: Implementation
  └── epic-execute              →  Automated execution
        ├── dev-story (per story)
        ├── code-review (per story)
        └── generate-uat

Human Testing
  └── Execute UAT document

Deployment
  └── Standard deployment process
```

## Support

For issues with this workflow:
- Check the execution log in `docs/sprints/`
- Review story files for Dev Agent Record / Code Review Record
- Ensure prerequisites are met
- Verify epic/story file formats
