# Repository Structure Review: Enhancements for Real-World Coding Projects

After a thorough review of the entire repo, here are the structural issues and enhancement opportunities, organized by impact level.

---

## 1. ~~CRITICAL: Dual Module Location Creates Broken References~~ RESOLVED

**Status:** Fixed.

The repo had two overlapping locations for BMM content (`src/bmm/` and `src/modules/bmm/`), causing 6 broken file references across 2 agent files. Agents referenced workflows that only existed in `src/modules/bmm/`, so the SM and UAT Validator agents would fail at runtime.

**What was done:**

- Moved `epic-execute/`, `epic-chain/`, and `uat-validate/` from `src/modules/bmm/` into `src/bmm/workflows/` (their correct locations)
- Created `src/bmm/workflows/5-validation/` for the UAT validation phase
- Fixed `.bmad/` → `_bmad/` path inconsistencies in the moved epic-chain and epic-execute files
- Removed the `uat-report` menu entry from `uat-validator.agent.yaml` (workflow never existed anywhere)
- Removed the `uat-automation-patterns` knowledge reference from `uat-validator.agent.yaml` (data file never existed)
- Deleted the now-empty `src/modules/bmm/` directory
- All tests pass (schema validation, file refs, installation components, lint, markdown lint, formatting)

---

## 2. ~~HIGH: No Guardrail for Broken File References in CI~~ RESOLVED

**Status:** Fixed.

The repo already had a comprehensive file reference validator (`tools/validate-file-refs.js`) that catches broken references, but it ran in warning mode (exit 0) so issues were never blocking. There were also 6 pre-existing broken references preventing strict mode from being enabled.

**What was done:**

- Fixed 6 broken file references across 3 workflow files:
  - `create-architecture/workflow.md` — wrong directory name (`architecture` → `create-architecture`)
  - `create-story/checklist.md` — wrong filename (`validate-workflow.xml` → `workflow.xml`)
  - `document-project/instructions.md` — removed 3 references to non-existent `workflow-status` workflow
- Switched `validate:refs` to strict mode (`--strict` flag) so broken references now fail with exit code 1
- Added `validate:refs` to the `npm test` script chain, so it runs in both pre-commit hooks and CI
- CI workflow (`.github/workflows/quality.yaml`) already ran `validate:refs` — the `--strict` flag now makes it a blocking check
- All 471 file references across 242 source files now validate cleanly

---

## 3. HIGH: `project-context.md` Is a Hidden Prerequisite

Every Phase 4 implementation workflow declares:

```yaml
project_context: "**/project-context.md"
```

But there's no clear documentation on what this file is, when to create it, or how. The `generate-project-context` workflow exists but:

- It's not mentioned in the Quick Start path in the README
- The Getting Started tutorial doesn't flag it as a prerequisite before Phase 4
- The Quick Flow path (`/quick-spec` → `/dev-story` → `/code-review`) doesn't mention it either

**Impact:** Developers hit Phase 4 workflows and get confusing results because the project context file doesn't exist yet.

**Recommendation:** Either auto-generate `project-context.md` during installation (even a minimal scaffold), or add a prominent step in the README's workflow paths and in the Quick Flow docs. Alternatively, make it optional in workflow configs with a graceful fallback.

---

## 4. HIGH: Artifact Storage Strategy Is Confusing

Three layers of configuration overlap:

- `core/module.yaml` defines `output_folder` (default: `_bmad-output`)
- `bmm/module.yaml` defines `planning_artifacts`, `implementation_artifacts`, `project_knowledge` (nested under output_folder)
- Individual workflows use different variable names (`{sprint_status}`, `{sprint_artifacts}`, `{output_folder}`)
- `.gitignore` ignores both `_bmad/` and `_bmad-output/`

**The confusion for real projects:**

1. Are artifacts meant to be version-controlled? The `.gitignore` says no, but `project_knowledge` defaults to `docs/` which *is* typically committed.
2. Some workflows reference `sprint_artifacts` which isn't defined in any `module.yaml` config.
3. A developer doesn't know where to look for generated PRDs, architecture docs, or sprint tracking files.

**Recommendation:**

- Add a clear section in the README or a post-install message explaining the folder structure and which folders to commit
- Standardize variable names across all workflows (audit `sprint_artifacts` vs `sprint_status`)
- Consider generating a `_bmad-output/README.md` during installation that explains the folder layout

---

## 5. HIGH: Inconsistent Workflow File Format

Workflows use two different formats with no documented rationale:

| Format | Examples |
|--------|----------|
| `workflow.yaml` (structured) | dev-story, code-review, sprint-planning, correct-course |
| `workflow.md` (markdown) | quick-spec, quick-dev, create-architecture, create-prd |
| Custom names | `workflow-create-prd.md`, `workflow-validate-prd.md` |

Some workflows have both a `workflow.yaml` and a separate `instructions.md`, while others put everything in a single `workflow.md`.

**Impact:** IDE integrations, the manifest generator, and agent command generators all need to handle multiple formats. Contributors don't know which format to use when adding workflows.

**Recommendation:** Document the rationale (e.g., `.yaml` for machine-parseable configs with `input_file_patterns`, `.md` for pure instructional workflows). Consider standardizing on `.yaml` as the entry point with `.md` for instructions only.

---

## 6. ~~MEDIUM: Missing Data Files Referenced by Agents~~ RESOLVED

**Status:** Fixed as part of item #1. The `uat-automation-patterns.yaml` reference and the `uat-report` menu entry were removed from `uat-validator.agent.yaml` since neither resource existed anywhere in the repo.

---

## 7. MEDIUM: No Example Project or Post-Install Scaffold

After running `npx bmad-method install`, developers get agents and workflows but no example of what a successful project looks like. There's no:

- Example `project-context.md`
- Sample PRD or architecture doc showing expected output format
- Starter `.claude/commands/` or equivalent showing what commands were generated
- Post-install "what to do next" guide in the terminal

**Recommendation:** Consider adding:

- A `_bmad-output/GETTING-STARTED.md` generated at install time with next steps specific to the chosen modules/IDE
- Example outputs in the docs site showing what a completed PRD, architecture doc, or sprint plan looks like
- A `bmad status` CLI command that shows what phase the project is in and what the next recommended workflow is (the `status` command exists but appears minimal)

---

## 8. MEDIUM: Test Suite Doesn't Use a Standard Test Runner

Tests in `test/` use raw `node:assert` and `node:test` with custom scripts rather than a standard test framework. While Jest is in devDependencies, the actual tests don't use it. The test runner is bare `node test/test-agent-schema.js`.

**Impact for contributors:** No test watch mode, no standard patterns for adding tests, no IDE test integration. The Jest dependency appears unused.

**Recommendation:** Either migrate to Jest (since it's already a dependency) or remove Jest and document the `node:test` approach. Either way, add test watch capabilities for contributor DX.

---

## 9. MEDIUM: `src/utility/agent-components/` Is Undocumented

The `src/utility/` directory contains shared agent components but isn't mentioned in the README, CLAUDE.md, or CONTRIBUTING.md. Its relationship to the module system is unclear.

**Recommendation:** Document this directory's purpose and how components are shared across modules.

---

## 10. LOW: CONTRIBUTING.md References Non-Existent Scripts

The contribution workflow likely references `npm run validate:refs` which doesn't exist as a standalone script in `package.json`. The actual ref validation is `test:refs` (which runs `test-file-refs-csv.js`).

**Recommendation:** Audit CONTRIBUTING.md to ensure all referenced commands exist.

---

## 11. ~~LOW: Workflow Phase Numbering Gap~~ RESOLVED

**Status:** Fixed as part of item #1. Phase 5 (`5-validation/uat-validate/`) has been moved into `src/bmm/workflows/`, completing the phase 1-5 progression in the main module.

---

## Summary: Top 5 Actionable Improvements

| Priority | Enhancement | User Impact |
|----------|------------|-------------|
| ~~**1**~~ | ~~Consolidate `src/bmm/` and `src/modules/bmm/`~~ | **RESOLVED** |
| ~~**2**~~ | ~~Add file reference validation to CI pipeline~~ | **RESOLVED** |
| **3** | Document and scaffold `project-context.md` in onboarding flow | Unblocks Phase 4 workflows for new users |
| **4** | Standardize artifact folder strategy with clear commit guidance | Developers understand where outputs go and what to version control |
| **5** | Add post-install guidance with example outputs | Reduces time-to-first-workflow from "confused" to "productive" |
