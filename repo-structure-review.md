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

## 3. ~~HIGH: `project-context.md` Is a Hidden Prerequisite~~ RESOLVED

**Status:** Fixed.

`project-context.md` is now surfaced as a recommended step across all user-facing documentation:

- **README.md** — Added a tip after Quick Flow's 3-command list for existing codebases, and inserted `/generate-project-context` as step 6 in the Full Planning Path before the build cycle
- **Getting Started tutorial** — Added a "Project Context (Recommended for Existing Codebases)" subsection between Phase 3 and the build step, with Analyst agent instructions. Also added `generate-project-context` to the Quick Reference table
- **Established Projects guide** — Inserted a new Step 3: "Generate Project Context" explaining both `generate-project-context` (lean rules) and `document-project` (comprehensive docs) options
- **Workflow Map** — Replaced the dense Context Management paragraph with a scannable "Creating Project Context" sub-heading and a comparison table of both workflows

---

## 4. ~~HIGH: Artifact Storage Strategy Is Confusing~~ RESOLVED

**Status:** Fixed.

Two sub-problems were addressed:

**A) Orphaned `sprint_artifacts` variable (code fix):**
- `sprint_artifacts` was referenced in `epic-chain/workflow.yaml`, `uat-validate/workflow.yaml`, and 3 supporting markdown files but was never defined in any `module.yaml` — causing those workflows to break at runtime
- All references replaced with `implementation_artifacts`, which is properly defined in `bmm/module.yaml` and serves the same purpose

**B) Documentation gap (folder strategy):**
- **Getting Started tutorial** — Expanded the installation section to explain all three output areas (`_bmad/`, `_bmad-output/`, `docs/`), their purposes, and version control strategy
- **Workflow Map** — Added an "Artifact Locations" reference table showing default paths, contents, and version control guidance for each folder category

**Remaining (out of scope):** The `epic-execute/` workflow has hardcoded `docs/` paths in its own config system (`default-config.yaml`) rather than using module variables — this is a separate issue

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

## 7. ~~MEDIUM: No Example Project or Post-Install Scaffold~~ PARTIALLY RESOLVED

**Status:** Documentation improvements applied. Installer code enhancements remain as a future improvement.

**What was done:**

- **README.md** — Improved the post-install section to explain what folders were created (`_bmad/`, `_bmad-output/`) and direct users to `/bmad-help`
- **Getting Started tutorial** — Fixed the project folder tree to show the actual subfolder structure (`planning-artifacts/`, `implementation-artifacts/`, `docs/`) instead of a flat layout. Added a "How do I verify my installation?" FAQ entry

**Remaining (future enhancements):**

- Generate a `_bmad-output/GETTING-STARTED.md` at install time with module-specific next steps
- Enhance installer `renderInstallSummary()` with module-aware guidance
- Add sample PRD, architecture, and project-context outputs to the docs site
- Enhance `bmad status` to show project phase and recommend next workflow

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
| ~~**3**~~ | ~~Document and scaffold `project-context.md` in onboarding flow~~ | **RESOLVED** |
| ~~**4**~~ | ~~Standardize artifact folder strategy with clear commit guidance~~ | **RESOLVED** |
| ~~**5**~~ | ~~Add post-install guidance with example outputs~~ | **PARTIALLY RESOLVED** (docs improved; installer enhancements remain) |
