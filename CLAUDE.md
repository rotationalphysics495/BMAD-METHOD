# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BMad Method is an AI-driven agile development framework built on BMad Core (Collaboration Optimized Reflection Engine). It provides specialized AI agents and guided workflows for software development lifecycle management.

**Key Modules:**
- **Core** (`src/core/`) - Universal framework with shared agents, tasks, and workflows
- **BMM** (`src/bmm/`) - BMad Method for agile software development (flagship module)

## Common Commands

```bash
# Run all tests (schemas, installation, validation, lint, markdown lint, format check)
npm test

# Run specific test suites
npm run test:schemas          # Agent YAML schema validation tests
npm run test:install          # Installation component tests
npm run validate:schemas      # Validate all *.agent.yaml files against schema

# Code quality
npm run lint                  # ESLint with YAML support
npm run lint:fix              # Auto-fix linting issues
npm run lint:md               # Markdown linting
npm run format:check          # Check Prettier formatting
npm run format:fix            # Auto-fix formatting

# Test coverage
npm run test:coverage         # Generate coverage report with c8

# CLI integration tests
./test/test-cli-integration.sh
```

## Architecture

### Module Structure
Each module in `src/` follows this pattern:
```
module/
├── module.yaml           # Module configuration and installer prompts
├── agents/               # Agent definitions (*.agent.yaml)
├── workflows/            # Workflow definitions with workflow.yaml files
├── data/                 # Data files used by workflows
├── teams/                # Team configurations (agent groupings)
└── _module-installer/    # Module-specific installation logic
```

### Agent YAML Schema
Agent files (`*.agent.yaml`) are validated by `tools/schema/agent.js` using Zod. Key rules:
- Required fields: `id`, `name`, `title`, `icon`, `persona`, `menu`
- Module agents must have `module` field matching their path (e.g., `bmm` for files in `src/bmm/agents/`)
- Menu triggers must be kebab-case or compound format (`TS or fuzzy match on tech-spec`)
- Test fixtures in `test/fixtures/agent-schema/` demonstrate valid/invalid patterns

### CLI Tools
- `tools/cli/bmad-cli.js` - Main CLI entry point
- `tools/bmad-npx-wrapper.js` - NPX wrapper (`npx bmad-method install`)
- `tools/validate-agent-schema.js` - Schema validation CLI wrapper

### Workflow System
Workflows are YAML files that guide multi-step processes. Located in module `workflows/` directories with:
- `workflow.yaml` - Workflow definition and steps
- Supporting data files and templates

## Development Notes

### Adding New Agents
1. Create `*.agent.yaml` in appropriate `src/*/agents/` directory
2. Follow schema in `tools/schema/agent.js`
3. Validate with `npm run validate:schemas`
4. Add test fixtures if introducing new validation patterns

### Modifying Validation
Schema changes go in `tools/schema/agent.js`. Test fixtures in `test/fixtures/agent-schema/` must cover all validation paths (100% coverage required).

### PR Guidelines
- Submit to `main` branch for critical fixes only
- Keep PRs under 800 lines; split larger changes
- Use conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- Validate YAML schemas before committing: `npm run validate:schemas`
