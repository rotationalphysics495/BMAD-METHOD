# User Acceptance Testing: Epic 1 - Foundation, CLI & Deployment Infrastructure

**Version:** 1.0
**Date:** January 2, 2026
**Epic:** Foundation, CLI & Deployment Infrastructure
**Status:** Ready for Testing

---

## 1. Overview

### What Was Built

Epic 1 delivers the foundation of the Heimdall Customer Management system. After completing this epic, administrators can:

- **Initialize a new Heimdall project** using a simple command-line tool
- **Configure connections** to Supabase (your database) and Resend (your email service)
- **Set up the database** with all necessary tables for job processing
- **Run a worker process** that continuously processes background jobs
- **Deploy to Railway** (a cloud hosting platform) for production use
- **Send test emails** to verify your email configuration is working

In plain terms: This is the "plumbing" that makes everything else possible. Once Epic 1 is working, you have a running system ready to handle customer management workflows.

---

## 2. Prerequisites

### Test Environment Requirements

Before starting UAT, ensure you have:

| Requirement | Details | How to Verify |
|-------------|---------|---------------|
| **Node.js 20.x** | JavaScript runtime | Run `node --version` - should show v20.x.x |
| **npm** | Package manager | Run `npm --version` - should show 9.x or higher |
| **Git** | Version control | Run `git --version` |
| **Terminal access** | Command line interface | macOS Terminal, Windows PowerShell, or Linux terminal |

### Required Accounts

| Service | Purpose | Sign-up URL |
|---------|---------|-------------|
| **Supabase** | Database hosting | <https://supabase.com> (free tier available) |
| **Resend** | Email delivery | <https://resend.com> (free tier: 100 emails/day) |
| **Railway** (optional) | Cloud deployment | <https://railway.app> (for production testing) |

### Credentials You Will Need

Before testing, gather these from your service dashboards:

1. **From Supabase Dashboard:**
   - Project URL (e.g., `https://xxxxx.supabase.co`)
   - Anon/Public Key (starts with `eyJ...`)
   - Database Connection String (from Settings > Database > Connection string > URI)

2. **From Resend Dashboard:**
   - API Key (starts with `re_...`)
   - A verified sending domain (or use their default for testing)

3. **Your Information:**
   - Admin email address (for receiving notifications and test emails)
   - Workspace name (a label for your installation)

---

## 3. Test Scenarios

### Scenario 1: Project Initialization

**Goal:** Verify that you can create a new Heimdall project with the correct structure.

**Steps:**

1. Open your terminal application
2. Navigate to a folder where you want to create the project:
   ```
   cd ~/Documents
   ```
3. Clone and set up the Heimdall project:
   ```
   git clone <repository-url> heimdall-test
   cd heimdall-test
   npm install
   npm run build
   ```
4. Verify the CLI is available:
   ```
   npx heimdall --version
   ```

**Expected Results:**

- [ ] `npm install` completes without errors
- [ ] `npm run build` shows "5 packages built successfully" or similar
- [ ] `npx heimdall --version` displays a version number (e.g., `1.0.0`)
- [ ] `npx heimdall --help` shows available commands including `config`, `db`, `start`, `test-send`, `test-queue`

**Notes for Tester:**
_Record any error messages or unexpected behavior here:_

---

### Scenario 2: Configuration Setup

**Goal:** Create and validate your configuration file with Supabase and Resend credentials.

**Steps:**

1. Generate a configuration template:
   ```
   npx heimdall config init
   ```
2. Open the created file `heimdall.config.yaml` in a text editor
3. Replace the placeholder values with your real credentials:
   - Under `workspace:` - enter your workspace name and admin email
   - Under `supabase:` - enter your Supabase URL, anon key, and database URL
   - Under `resend:` - enter your Resend API key
4. Save the file
5. Validate your configuration:
   ```
   npx heimdall config validate
   ```

**Expected Results:**

- [ ] `config init` creates a file named `heimdall.config.yaml`
- [ ] The file contains sections for `workspace`, `supabase`, `resend`, and `ai` (optional)
- [ ] `config validate` shows your workspace name and admin email (with secrets partially hidden)
- [ ] Validation shows "Configuration is valid" or similar success message
- [ ] No error messages appear about missing or invalid fields

**Notes for Tester:**
_If validation fails, record the error message:_

---

### Scenario 3: Database Migration

**Goal:** Set up the required database tables in your Supabase instance.

**Prerequisites:** Scenario 2 must be completed successfully.

**Steps:**

1. Run the database migration:
   ```
   npx heimdall db migrate
   ```
2. Check the database status:
   ```
   npx heimdall db status
   ```

**Expected Results:**

- [ ] `db migrate` completes with a success message (e.g., "pg-boss initialized successfully")
- [ ] `db status` shows:
  - Database connected: Yes
  - pg-boss schema: Exists
  - Tables: job, schedule, subscription, version (or similar)
- [ ] Running `db migrate` a second time does NOT cause errors (idempotent)

**Verification in Supabase Dashboard:**
1. Log into your Supabase project
2. Go to the Table Editor
3. Look for a schema named `pgboss`
4. Verify tables exist: `job`, `schedule`, `subscription`, `version`

- [ ] pg-boss tables visible in Supabase Dashboard

**Notes for Tester:**
_Record database status output:_

---

### Scenario 4: Connection Validation (Detailed)

**Goal:** Verify both Supabase API and direct database connections work correctly.

**Prerequisites:** Scenario 3 must be completed successfully.

**Steps:**

1. Run the full validation:
   ```
   npx heimdall config validate
   ```

**Expected Results:**

- [ ] Message: "Supabase API connected" with response time in milliseconds
- [ ] Message: "Operational DB connected" with response time in milliseconds
- [ ] Message: "Resend API connected" (if Resend key is configured)
- [ ] All connections show as successful (green checkmarks or similar)

**Notes for Tester:**
_Record connection times and any warnings:_

---

### Scenario 5: Worker Process Startup

**Goal:** Start the background worker that processes jobs.

**Prerequisites:** Scenario 3 must be completed successfully.

**Steps:**

1. Start the worker process:
   ```
   npx heimdall start
   ```
2. Observe the output for approximately 30 seconds
3. Press `Ctrl+C` to stop the worker

**Expected Results:**

- [ ] Message appears: "Heimdall worker started, polling for jobs..." or similar
- [ ] No error messages during startup
- [ ] Worker continues running without crashing
- [ ] When you press `Ctrl+C`, message appears: "Heimdall worker shutting down gracefully..."
- [ ] Process exits cleanly (returns to command prompt)

**Notes for Tester:**
_Record startup messages:_

---

### Scenario 6: Job Queue Testing

**Goal:** Verify that jobs can be queued and processed by the worker.

**Prerequisites:** Scenario 5 must work (worker can start).

**Steps:**

1. Open **two terminal windows** side by side
2. In Terminal 1, start the worker:
   ```
   npx heimdall start
   ```
3. Wait for the "polling for jobs" message
4. In Terminal 2, enqueue a test job:
   ```
   npx heimdall test-queue
   ```
5. Watch Terminal 1 for job processing
6. Stop the worker in Terminal 1 with `Ctrl+C`

**Expected Results:**

- [ ] Terminal 2 shows: "Test job enqueued: test-job-{some-id}"
- [ ] Within 60 seconds, Terminal 1 shows: "Job executed: test-job-{same-id}"
- [ ] No errors in either terminal
- [ ] Job ID in Terminal 2 matches the ID in Terminal 1

**Notes for Tester:**
_Record time between enqueueing and execution:_
_Record job ID:_

---

### Scenario 7: Test Email Sending

**Goal:** Verify that Heimdall can send emails through Resend.

**Prerequisites:**
- Scenario 2 completed with valid Resend API key
- You have access to the email inbox specified

**Steps:**

1. Send a test email to yourself:
   ```
   npx heimdall test-send --to your-email@example.com
   ```
   (Replace with your actual email address)
2. Check your email inbox (including spam/junk folder)

**Expected Results:**

- [ ] Command shows: "Test email sent: {resend-message-id}"
- [ ] Email arrives in inbox within 2-5 minutes
- [ ] Email subject: "Heimdall Test Email"
- [ ] Email body confirms configuration is working

**Notes for Tester:**
_Record Resend message ID:_
_Time until email arrived:_
_Did email land in spam?:_

---

### Scenario 8: Health Endpoint (Local)

**Goal:** Verify the worker's health endpoint responds correctly.

**Prerequisites:** Worker can start (Scenario 5).

**Steps:**

1. Start the worker:
   ```
   npx heimdall start
   ```
2. Open a web browser
3. Navigate to: `http://localhost:3000/health`
4. Stop the worker with `Ctrl+C`

**Expected Results:**

- [ ] Browser shows JSON response
- [ ] Response contains: `"status": "healthy"`
- [ ] Response contains: `"queue": "connected"`
- [ ] Response contains: `"uptime": {some-number}`

**Sample Expected Response:**
```json
{
  "status": "healthy",
  "queue": "connected",
  "uptime": 45
}
```

**Notes for Tester:**
_Copy the actual response here:_

---

### Scenario 9: Railway Deployment (Optional)

**Goal:** Deploy Heimdall to Railway for production use.

**Prerequisites:**
- Railway account created
- All previous scenarios pass locally

**Steps:**

1. Log into Railway Dashboard
2. Create a new project from the GitHub repository
3. Add environment variables in Railway settings:
   - `DATABASE_URL` = your Supabase connection string
   - `SUPABASE_URL` = your Supabase project URL
   - `SUPABASE_ANON_KEY` = your Supabase anon key
   - `RESEND_API_KEY` = your Resend API key
   - `ADMIN_EMAIL` = your admin email
   - `WORKSPACE_NAME` = your workspace name
4. Deploy the service
5. Once deployed, access the health endpoint at your Railway URL + `/health`

**Expected Results:**

- [ ] Deployment completes without build errors
- [ ] Service shows as "Running" in Railway dashboard
- [ ] Health endpoint at `https://your-app.railway.app/health` returns:
  - `"status": "healthy"`
  - `"queue": "connected"`
- [ ] Logs show "Heimdall worker started, polling for jobs..."

**Notes for Tester:**
_Railway deployment URL:_
_Any deployment warnings or notes:_

---

## 4. Success Criteria

### Minimum Requirements for Sign-off

All of the following must pass for Epic 1 to be accepted:

| # | Criteria | Scenario | Status |
|---|----------|----------|--------|
| 1 | Project builds successfully | Scenario 1 | [ ] Pass / [ ] Fail |
| 2 | CLI commands are accessible | Scenario 1 | [ ] Pass / [ ] Fail |
| 3 | Configuration file is created correctly | Scenario 2 | [ ] Pass / [ ] Fail |
| 4 | Configuration validation works | Scenario 2 | [ ] Pass / [ ] Fail |
| 5 | Database migration completes | Scenario 3 | [ ] Pass / [ ] Fail |
| 6 | Database migration is idempotent | Scenario 3 | [ ] Pass / [ ] Fail |
| 7 | Supabase API connection validated | Scenario 4 | [ ] Pass / [ ] Fail |
| 8 | Operational DB connection validated | Scenario 4 | [ ] Pass / [ ] Fail |
| 9 | Worker process starts and polls | Scenario 5 | [ ] Pass / [ ] Fail |
| 10 | Worker shuts down gracefully | Scenario 5 | [ ] Pass / [ ] Fail |
| 11 | Test jobs are processed | Scenario 6 | [ ] Pass / [ ] Fail |
| 12 | Jobs processed within 60 seconds | Scenario 6 | [ ] Pass / [ ] Fail |
| 13 | Test emails are sent and received | Scenario 7 | [ ] Pass / [ ] Fail |
| 14 | Health endpoint responds correctly | Scenario 8 | [ ] Pass / [ ] Fail |

### Optional (Recommended)

| # | Criteria | Scenario | Status |
|---|----------|----------|--------|
| 15 | Railway deployment successful | Scenario 9 | [ ] Pass / [ ] Fail / [ ] Skipped |
| 16 | Production health endpoint works | Scenario 9 | [ ] Pass / [ ] Fail / [ ] Skipped |

---

## 5. Known Limitations

The following are expected behaviors, not bugs:

1. **Error messages for invalid credentials** are intentionally detailed to help debugging
2. **First database migration** may take 10-30 seconds as pg-boss creates multiple tables
3. **Test emails** may land in spam for unverified domains
4. **Worker polling interval** is 5 seconds, so jobs may take up to 5 seconds to start processing
5. **Config validate** shows partial secrets (first/last 4 characters) for verification purposes

---

## 6. Troubleshooting Guide

### Common Issues and Solutions

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| "Command not found: heimdall" | Build not completed | Run `npm run build` first |
| "Cannot connect to database" | Wrong db_url | Check Supabase connection string format |
| "Invalid API key" | Resend key incorrect | Regenerate key in Resend dashboard |
| "ECONNREFUSED" | Database not accessible | Check Supabase project is running, check IP restrictions |
| Worker crashes on startup | Missing configuration | Run `heimdall config validate` first |
| Email not received | Domain not verified | Verify domain in Resend or check spam folder |

---

## 7. Sign-off Section

### Testing Summary

| Item | Value |
|------|-------|
| **Tester Name** | _________________________ |
| **Test Date** | _________________________ |
| **Environment** | [ ] Local / [ ] Railway / [ ] Both |
| **Node.js Version** | _________________________ |
| **Operating System** | _________________________ |

### Test Results Summary

| Category | Passed | Failed | Skipped |
|----------|--------|--------|---------|
| Required Scenarios (1-8) | ___ / 8 | ___ | ___ |
| Optional Scenarios (9) | ___ / 1 | ___ | ___ |
| Success Criteria (1-14) | ___ / 14 | ___ | ___ |

### Issues Found

| Issue # | Scenario | Description | Severity |
|---------|----------|-------------|----------|
| | | | [ ] Blocker / [ ] Major / [ ] Minor |
| | | | [ ] Blocker / [ ] Major / [ ] Minor |
| | | | [ ] Blocker / [ ] Major / [ ] Minor |

### Final Decision

- [ ] **APPROVED** - All required criteria pass, ready for production
- [ ] **APPROVED WITH CONDITIONS** - Minor issues noted, can proceed
- [ ] **NOT APPROVED** - Blocker issues must be resolved

### Signatures

| Role | Name | Signature | Date |
|------|------|-----------|------|
| **Tester** | | | |
| **Product Owner** | | | |
| **Technical Lead** | | | |

---

## 8. Appendix

### A. CLI Command Reference

| Command | Purpose |
|---------|---------|
| `heimdall --version` | Display version number |
| `heimdall --help` | Show available commands |
| `heimdall config init` | Create configuration file |
| `heimdall config validate` | Validate configuration |
| `heimdall db migrate` | Set up database tables |
| `heimdall db status` | Check database status |
| `heimdall start` | Start worker process |
| `heimdall test-queue` | Enqueue a test job |
| `heimdall test-send --to EMAIL` | Send a test email |

### B. Configuration File Template

```yaml
# heimdall.config.yaml
workspace:
  name: "my-workspace"
  admin_email: "admin@example.com"

supabase:
  url: "https://xxxxx.supabase.co"
  anon_key: "eyJ..."
  db_url: "postgresql://postgres:password@db.xxxxx.supabase.co:5432/postgres"

resend:
  api_key: "re_..."

# Optional AI configuration
ai:
  provider: "anthropic"
  api_key: "sk-ant-..."
  model: "claude-3-haiku-20240307"
```

### C. Environment Variables for Railway

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `SUPABASE_URL` | Yes | Supabase project URL |
| `SUPABASE_ANON_KEY` | Yes | Supabase anonymous key |
| `RESEND_API_KEY` | Yes | Resend API key |
| `ADMIN_EMAIL` | Yes | Admin notification email |
| `WORKSPACE_NAME` | No | Workspace identifier |
| `PORT` | No | Server port (default: 3000) |

---

*Document generated: January 2, 2026*
*Epic 1: Foundation, CLI & Deployment Infrastructure*
