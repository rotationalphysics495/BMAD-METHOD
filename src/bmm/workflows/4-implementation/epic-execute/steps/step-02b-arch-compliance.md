# Step 2b: Architecture Compliance Check (Per-Story)

## Context Isolation

**IMPORTANT**: This step executes in a fresh Claude context after the dev phase completes but before code review. It validates that the implementation follows architectural constraints before detailed review begins.

## Objective

Verify that the staged implementation follows the project's established architecture patterns, module boundaries, and dependency rules. Catch structural violations early before they compound across stories.

## Inputs

- `story_id`: The story being validated
- `story_file`: Path to story markdown file (contains Dev Agent Record from dev phase)

## Validation Categories

| Category | What It Catches | Severity if Failed |
|----------|-----------------|-------------------|
| Layer violations | Business logic in UI, DB calls from controllers | HIGH |
| Dependency direction | Circular dependencies, wrong import directions | HIGH |
| Pattern conformance | Using wrong state management, deviating from established patterns | MEDIUM |
| Module boundaries | Features leaking across module boundaries | MEDIUM |
| File organization | Files in wrong directories, naming convention violations | LOW |

## Prompt Template

```
You are an Architecture Compliance Validator executing a BMAD compliance check.

## Your Task

Validate architecture compliance for story: {story_id}

You are checking the staged changes against the project's established architecture patterns.
This is a TARGETED CHECK - focus only on structural/architectural issues, not code quality.

## Story Context

<story>
{story_file_contents}
</story>

## Architecture Reference

Read and understand the project architecture:

<architecture>
{architecture_file_contents}
</architecture>

## Staged Changes

Run this command and analyze the output:

```bash
git diff --staged --name-only
```

Then for each changed file, examine the changes:

```bash
git diff --staged
```

## Compliance Checklist

### 1. Layer Violations

Check that code respects architectural layers:

- [ ] UI/Presentation layer only handles display logic
- [ ] Business logic is in appropriate service/domain layer
- [ ] Data access is confined to repository/data layer
- [ ] Controllers/routes only orchestrate, don't contain business logic
- [ ] No direct database calls from UI components

### 2. Dependency Direction

Verify dependencies flow in the correct direction:

- [ ] No circular dependencies between modules
- [ ] Lower layers don't import from higher layers
- [ ] Shared utilities don't depend on feature-specific code
- [ ] Core/domain doesn't depend on infrastructure

### 3. Pattern Conformance

Ensure implementation follows established patterns:

- [ ] State management uses project's standard approach
- [ ] Error handling follows project conventions
- [ ] API calls use established client/service patterns
- [ ] Authentication/authorization uses project's auth system
- [ ] Configuration follows project's config management

### 4. Module Boundaries

Validate feature isolation:

- [ ] Feature code is in correct module directory
- [ ] No cross-module imports that bypass public interfaces
- [ ] Shared types are in shared/common locations
- [ ] Feature-specific code doesn't leak to unrelated modules

### 5. File Organization

Check structural conventions:

- [ ] Files are in correct directories per architecture
- [ ] File naming follows project conventions
- [ ] Test files are alongside or in standard test directories
- [ ] No orphaned files in wrong locations

## Issue Collection

Compile all violations found:

```markdown
### Architecture Violations Found

| # | Category | Description | Severity | File:Line | Fixable |
|---|----------|-------------|----------|-----------|---------|
| 1 | Layer | [description] | HIGH/MEDIUM/LOW | path:123 | Yes/No |
| 2 | Dependency | [description] | HIGH/MEDIUM/LOW | path:456 | Yes/No |
```

Count totals:
- HIGH: {count}
- MEDIUM: {count}
- LOW: {count}
- TOTAL: {count}

## Fix Policy

Architecture violations are addressed before code review to prevent wasted effort:

| Severity | Action |
|----------|--------|
| **HIGH** | Must fix before proceeding to review |
| **MEDIUM** | Fix if possible, otherwise document for review phase |
| **LOW** | Document only, review phase will handle |

## Fixing Violations

For HIGH severity violations:

1. Make the structural change (move code, fix imports, etc.)
2. Run tests to verify the fix doesn't break functionality
3. Stage the changes: `git add -A`
4. Document the fix in the issue table

## Completion Signals

### COMPLIANT if:
- No HIGH severity violations
- No MEDIUM severity violations (or all fixed)

Output: `ARCH COMPLIANT: {story_id}`
or: `ARCH COMPLIANT WITH FIXES: {story_id} - Fixed {n} violations`

### VIOLATIONS FOUND if:
- HIGH severity violations that cannot be fixed without major rework

1. Output the violations block:
```
ARCH VIOLATIONS START
- [HIGH] Description of violation 1 (file:line)
- [HIGH] Description of violation 2
- [MEDIUM] Description of violation 3
ARCH VIOLATIONS END
```
2. Output: `ARCH VIOLATIONS: {story_id} - {summary}`

## Example Violations

### Layer Violation (HIGH)
```typescript
// ❌ BAD: UI component making direct database call
// src/components/UserProfile.tsx
import { db } from '../database/connection';
const user = await db.query('SELECT * FROM users WHERE id = ?', [id]);

// ✅ GOOD: UI uses service layer
import { userService } from '../services/user-service';
const user = await userService.getUserById(id);
```

### Dependency Direction (HIGH)
```typescript
// ❌ BAD: Core domain importing from infrastructure
// src/domain/order.ts
import { sendEmail } from '../infrastructure/email-client';

// ✅ GOOD: Core domain uses interface, infrastructure implements
// src/domain/order.ts
import type { NotificationService } from './interfaces';
```

### Pattern Conformance (MEDIUM)
```typescript
// ❌ BAD: Using fetch directly when project uses axios client
const response = await fetch('/api/users');

// ✅ GOOD: Using established API client
import { apiClient } from '../lib/api-client';
const response = await apiClient.get('/users');
```

### Module Boundary (MEDIUM)
```typescript
// ❌ BAD: Feature importing internal from another feature
// src/features/orders/components/OrderForm.tsx
import { validateEmail } from '../../users/utils/validation'; // internal util

// ✅ GOOD: Using shared utility or feature's public interface
import { validateEmail } from '../../../shared/validation';
// or
import { UserValidation } from '../../users'; // public export
```

## Notes

- This check happens BEFORE detailed code review to catch structural issues early
- Architectural violations are often harder to fix after more code is built on top
- The goal is to maintain architectural integrity across the epic, not just individual stories
- When in doubt about architecture rules, reference architecture.md and existing patterns
```

## Orchestration Integration

```bash
# Fresh context - focused only on architecture compliance
claude -p "$(cat step-02b-arch-compliance.md | envsubst)"
```

## Integration with Fix Loop

If violations are found:
1. Violations are passed to a fix phase (similar to code review fix loop)
2. Fix phase addresses HIGH violations
3. Re-run compliance check
4. Max 2 attempts before escalating to human

## Success Criteria

Phase complete when:
- All HIGH severity violations resolved
- Changes are staged in git
- ARCH COMPLIANT signal output
