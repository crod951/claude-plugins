# Make `/issue-start` Resumable — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `/issue-start` idempotent so re-running it on an already-started issue gracefully resumes instead of failing.

**Architecture:** Add existence checks (guards) to each side-effect-producing step. Reorder steps so the branch is checked out before any files are created. Ask the user whether to re-create or keep existing plans.

**Tech Stack:** Markdown skill file (no code — this is a Claude Code plugin command)

---

### Task 1: Add existing-branch context to the Context section

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md:6-11`

**Step 1: Add a context line for existing branches**

Add to the Context section (after the existing lines):

```markdown
- Local branches: !`git branch --list`
- Remote branches: !`git branch -r --list 2>/dev/null`
```

This gives the skill runtime access to existing branch names for the guard logic in the new Step 5.

**Step 2: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): add branch context for resume detection"
```

---

### Task 2: Move branch creation to Step 5 (before plan doc)

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md`

**Step 1: Replace old Step 5 (plan doc) with new Step 5 (branch checkout)**

Replace the current Step 5 content (lines 60-99) with the new branch step. The new Step 5 should:

1. Determine the branch name (label-based prefix + slug) — same logic as old Step 9
2. Check if the branch exists locally (`git branch --list <branch-name>`)
3. Check if it exists on remote (`git branch -r --list origin/<branch-name>`)
4. Branch based on result:
   - Local exists → `git checkout <branch-name>`, note "Switched to existing branch <branch-name>"
   - Remote only → `git checkout <branch-name>`, note "Checked out existing remote branch <branch-name>"
   - Neither → `git checkout -b <branch-name>`, note "Created new branch <branch-name>"

Full replacement text for Step 5:

~~~markdown
### Step 5: Create or checkout the feature branch

Determine the branch prefix from the Linear issue labels:
- "Feature" → `feat/`
- "Bug" → `fix/`
- "Improvement" or "Chore" → `chore/`
- "Documentation" → `docs/`
- Default (no matching label) → `feat/`

Branch format: `<prefix>/<issue-id-lowercase>-<slug-from-linear-title>`

Example: For ONC-5 "Add Audit Trail" with label "Feature" → `feat/onc-5-add-audit-trail`

**Check if the branch already exists** using the local and remote branch context above:

- **If it exists locally:** `git checkout <branch-name>` — note "Switched to existing branch"
- **If it exists on remote but not locally:** `git checkout <branch-name>` (git will auto-track the remote) — note "Checked out existing remote branch"
- **If it does not exist:** `git checkout -b <branch-name>` — note "Created new branch"

Track whether the branch was pre-existing — this affects later steps.
~~~

**Step 2: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): move branch checkout to step 5 with existence check"
```

---

### Task 3: Rewrite Step 6 (plan doc) with existence guard

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md`

**Step 1: Write the new Step 6**

Replace what was previously the plan step with a version that checks for an existing plan first:

~~~markdown
### Step 6: Write the plan document (or detect existing)

Check if `docs/plans/<ISSUE-ID>.md` already exists.

**If the plan does NOT exist:**

Create the directory `docs/plans/` if it doesn't exist, then write the plan to `docs/plans/<ISSUE-ID>.md` (e.g., `docs/plans/ONC-5.md`).

Plan format:

```
# <Issue Title> — <ISSUE-ID>

> **Linear:** <issue URL>
> **Branch:** <branch name from step 5>
> **Date:** <today's date>
> **Status:** In Progress

## Issue Description

<Copy from Linear issue description>

## Codebase Context

<What you found during research — relevant files, existing patterns, architecture notes>

## Implementation Approach

<High-level approach in 2-3 sentences>

## Tasks

1. <Specific, actionable task with exact file paths>
2. <Next task>
3. ...

## Testing Strategy

<How to verify each task — specific test files, manual testing steps>

## Notes

<Gotchas, risks, decisions, alternative approaches considered>
```

Proceed to Step 7 for review.

**If the plan already exists:**

- **If `--no-confirm` is set:** Keep existing plan, skip to Step 8 (Beads).
- **Otherwise:** Inform the user and ask using `AskUserQuestion`:
  - "Existing plan found at `docs/plans/<ISSUE-ID>.md`. Would you like to re-create it or keep the existing one?"
  - Options: "Re-create plan" (delete old plan, write new one, proceed to Step 7 for review; also triggers Beads task re-creation in Step 9), "Keep existing plan" (skip to Step 8)
~~~

**Step 2: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): add plan existence guard with user prompt"
```

---

### Task 4: Update Step 7 (plan review) with adjusted references

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md`

**Step 1: Rewrite Step 7**

This step only runs when a new plan was written (either fresh or re-created). Update the step number references and the AskUserQuestion options text.

~~~markdown
### Step 7: Present the plan for review

**This step only runs if a new plan was written in Step 6.** If the user chose "Keep existing plan", skip to Step 8.

Show the user a summary of the plan:

```
--- Plan Created for <ISSUE-ID> ---

  Issue:    <ISSUE-ID> — <Title>
  Plan:     docs/plans/<ISSUE-ID>.md

  Tasks:
    1. <task title>
    2. <task title>
    ...

  Please review the plan at docs/plans/<ISSUE-ID>.md.
  You can discuss changes with me before proceeding.

------------------------------------
```

**If `--no-confirm` flag is set (requires `--auto`):** Skip this approval step entirely — auto-approve the plan and continue directly to Step 8.

**Otherwise**, present the plan for review:

Then use `AskUserQuestion` to ask the user:
- Question: "Does the plan look good? Ready to create Beads tasks?"
- Options: "Approve plan" (proceed to step 8), "I have changes" (wait for user to discuss edits)

**If the user selects "I have changes":** Stop and wait. Let them discuss modifications. After they are satisfied and confirm, resume from Step 8.

**If the user selects "Approve plan":** Continue to Step 8.
~~~

**Step 2: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): update plan review step with skip logic"
```

---

### Task 5: Update Steps 8-9 (Beads) with existence guard

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md`

**Step 1: Rewrite Step 8 (Beads init)**

Same as before — no change needed to the init logic itself, just renumber.

**Step 2: Rewrite Step 9 (Beads tasks) with guard**

~~~markdown
### Step 9: Create Beads tasks (or detect existing)

Check if Beads tasks with label `<ISSUE-ID>` already exist:
```bash
bd list -l "<ISSUE-ID>" --limit 50 2>/dev/null
```

**If the user chose "Re-create plan" in Step 6:**

Delete all existing Beads tasks for this issue, then create fresh tasks from the new plan:
```bash
bd list -l "<ISSUE-ID>" --limit 50 --format json 2>/dev/null
```
For each task found, delete it:
```bash
bd delete <task-id>
```
Then create new tasks from the plan (same as fresh creation below).

**If tasks already exist (and plan was kept):**

Skip creation. Print "Existing Beads tasks found for <ISSUE-ID> — skipping creation."

**If no tasks exist (fresh creation):**

For each task in the plan, create a Beads task:
```bash
bd create "Task title" -d "Detailed description including file paths" -p 2 --external-ref "<ISSUE-ID>-<short-suffix>" -l "<ISSUE-ID>"
```

The `--external-ref` must be unique per task. Use the pattern `<ISSUE-ID>-<short-suffix>` (e.g., `ONC-5-gem`, `ONC-5-models`, `ONC-5-tests`).

After creating all tasks, set up dependencies between sequential tasks:
```bash
bd dep add <child-id> <parent-id>
```

Where `<child-id>` depends on `<parent-id>` completing first.
~~~

**Step 3: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): add beads task existence guard with re-create support"
```

---

### Task 6: Update Steps 10-11 (Linear + summary) and remove old Step 9

**Files:**
- Modify: `plugins/issue-lifecycle/commands/issue-start.md`

**Step 1: Renumber Step 10 (Linear status) and Step 11 (summary)**

Step 10 stays the same (just renumbered). For Step 11, add a "(Resumed)" indicator when any artifacts were pre-existing:

~~~markdown
### Step 11: Present summary

Show the user (use "Resumed" in the header if the branch, plan, or Beads tasks were pre-existing):

```
--- Issue Lifecycle Started [/ Resumed] ---

  Issue:    <ISSUE-ID> — <Title>
  Plan:     docs/plans/<ISSUE-ID>.md
  Branch:   <branch-name>
  Linear:   In Progress
  Tasks:    <count> [created / existing]

  Beads Tasks:
    <id>  <title>
    <id>  <title>
    ...

  Next: Run /issue-task to start working on the first task.

--------------------------------
```
~~~

**Step 2: Remove old Step 9 (branch creation)**

The old Step 9 branch logic was moved to Step 5 in Task 2. Ensure it's fully removed and no duplicate exists.

**Step 3: Commit**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "feat(issue-start): update summary with resume indicator, remove old branch step"
```

---

### Task 7: Final review — read full file, verify correctness

**Step 1:** Read the entire file and verify:
- Steps are numbered 1-11 sequentially with no gaps
- All step cross-references use correct numbers
- The `--auto` and `--no-confirm` flags are respected in all new guard logic
- The plan doc template still references the branch from Step 5 (not Step 9)
- No duplicate branch creation logic remains

**Step 2: Commit any fixes**

```bash
git add plugins/issue-lifecycle/commands/issue-start.md
git commit -m "fix(issue-start): fix step references and clean up"
```
