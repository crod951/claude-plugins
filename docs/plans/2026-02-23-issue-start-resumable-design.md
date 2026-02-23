# Make `/issue-start` Resumable — Design

> **Date:** 2026-02-23
> **Status:** Approved

## Problem

Running `/issue-start <ISSUE-ID>` on an issue that was already partially or fully started fails at Step 9 (`git checkout -b`) because the branch already exists. The skill should gracefully detect prior progress and resume.

## Design

### Reorder: Move branch checkout before plan creation

**Current order:** parse → fetch → research → clarify → plan → review → beads → branch → linear → summary

**New order:** parse → fetch → research → clarify → **branch** → plan → review → beads → linear → summary

This ensures all artifacts (plan doc, beads tasks) are created on the feature branch, not on `main`.

### Step 5 (was Step 9): Branch — check-then-checkout

Before creating the branch:

1. Check if it exists locally: `git branch --list <branch-name>`
2. Check if it exists on remote: `git branch -r --list origin/<branch-name>`

Behavior:
- **Local exists:** `git checkout <branch-name>` (no `-b`), print "Switched to existing branch"
- **Remote exists (not local):** `git checkout <branch-name>` (git auto-tracks remote), print "Checked out existing remote branch"
- **Neither exists:** `git checkout -b <branch-name>` (create new branch)

### Step 6 (was Step 5): Plan doc — ask user if existing

Before writing the plan, check if `docs/plans/<ISSUE-ID>.md` exists.

- **Plan does NOT exist:** Write the plan as normal, proceed to review.
- **Plan exists AND `--no-confirm` is set:** Keep existing plan, skip review.
- **Plan exists (interactive):** Ask the user:
  - "Existing plan found at `docs/plans/<ISSUE-ID>.md`. Do you want to re-create it or keep the existing one?"
  - **Re-create plan:** Delete old plan, write new one, proceed to review. Also triggers re-creation of Beads tasks.
  - **Keep existing plan:** Skip plan creation and review.

### Steps 8-9 (was Steps 7-8): Beads — existence-aware

After initializing Beads (if needed), check if tasks with label `<ISSUE-ID>` already exist using `bd list -l "<ISSUE-ID>"`.

Behavior depends on the plan decision:

- **User chose "Re-create plan":** Delete existing Beads tasks for `<ISSUE-ID>`, then create fresh ones matching the new plan.
- **User chose "Keep existing plan" (or plan was new):**
  - If Beads tasks exist: skip creation, print "Existing Beads tasks found for <ISSUE-ID> — skipping creation"
  - If Beads tasks don't exist: create them from the existing plan

This handles the partial-failure case where a prior run wrote the plan but crashed before creating Beads tasks.

### Step 10: Linear status — no change

Setting "In Progress" when already in progress is a no-op.

### Step 11: Summary — note if resumed

If any artifacts were pre-existing (branch, plan, or beads tasks), add "(Resumed)" to the summary header.

## Affected File

- `plugins/issue-lifecycle/commands/issue-start.md` — single file change
