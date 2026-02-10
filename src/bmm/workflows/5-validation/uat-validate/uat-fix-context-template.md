# UAT Fix Context - Epic {epic_id} (Attempt {attempt})

**Generated:** {timestamp}
**Epic:** {epic_id}
**Gate Result:** FAIL ({passed}/{total} scenarios passed)

---

## Summary

This document contains the context needed to fix UAT failures for Epic {epic_id}. Load this document and implement targeted fixes for each failure listed below.

**Failures to fix:** {failure_count}
**Fix attempt:** {attempt} of {max_retries}
**UAT Document:** `{uat_doc_path}`

---

## Quick Start

1. Review the **Human Intervention Items** section first
2. Read each **Failed Scenario** with its root cause hint
3. Check the **Story Context** for acceptance criteria and implementation notes
4. Implement targeted fixes for code-level issues
5. Verify: run the failing command
6. Commit: `fix(epic-{epic_id}): {description}`

---

## Document Structure

This fix context includes:

1. **Human Intervention Items** - Issues that may require human action (env vars, API keys, etc.)
2. **Failed Scenarios** - Detailed failure information with root cause hints
3. **Story Context** - Acceptance criteria and Dev Agent Record from original stories

For items marked as BLOCKING or WARNING that require human configuration:
- Document what configuration is needed
- Proceed with code fixes you CAN make
- Do not create placeholder credentials or fake values

---
