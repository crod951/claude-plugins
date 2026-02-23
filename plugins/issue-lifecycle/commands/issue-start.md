---
description: Start working on a Linear issue - fetches issue, creates plan, Beads tasks, and feature branch
argument-hint: "<ISSUE-ID> [--auto] [--no-confirm]"
---

## Context

- Current branch: !`git branch --show-current`
- Beads status: !`bd status 2>/dev/null || echo "BEADS_NOT_INITIALIZED"`
- Existing plans: !`ls docs/plans/ 2>/dev/null || echo "NO_PLANS_DIR"`
- Project directory name: !`basename $(pwd)`
- Local branches: !`git branch --list`
- Remote branches: !`git branch -r --list 2>/dev/null`

## Instructions

You are starting work on Linear issue: **$ARGUMENTS**

Follow these steps precisely:

### Step 1: Parse arguments and flags

Parse `$ARGUMENTS` to extract:

- **Issue ID:** The required non-flag argument (e.g., `ONC-5`).
- **`--auto`:** If present, after plan approval and setup, automatically continue into auto-loop mode (implement all tasks, commit each, and finish the issue).
- **`--no-confirm`:** If present (requires `--auto`), skip the plan approval pause — auto-approve the plan and proceed immediately.

Examples:
- `/issue-start ONC-5` → normal manual flow
- `/issue-start ONC-5 --auto` → plan with approval pause, then auto-loop all tasks + finish
- `/issue-start ONC-5 --auto --no-confirm` → fully autonomous, no pauses

Use the extracted issue ID for all subsequent steps where `$ARGUMENTS` was previously referenced.

### Step 2: Fetch the Linear issue

Use the `mcp__plugin_linear_linear__get_issue` tool with id: `$ARGUMENTS`.
Save the response — you'll need the title, description, labels, URL, and UUID (id field).

### Step 3: Research the codebase

Based on the issue description, use Glob, Grep, and Read to search the codebase for relevant files (models, controllers, views, services, tests). Understand the existing architecture that relates to this issue. Be thorough — this context feeds the plan.

### Step 4: Ask clarifying questions (if needed)

After reviewing the issue description and researching the codebase, evaluate whether the requirements are clear enough to write a solid plan. If there are ambiguities, missing details, or multiple valid interpretations, use `AskUserQuestion` to clarify before writing the plan.

Common reasons to ask:
- The issue description is vague about scope or expected behavior
- Multiple implementation approaches are viable and the choice affects the plan significantly
- Business logic or edge cases are not specified
- It's unclear which parts of the codebase should be modified
- The issue references external systems, APIs, or dependencies you don't have context on

**If `--no-confirm` is set:** Skip this step — proceed directly to writing the plan using your best judgment.

**If everything is clear:** Skip this step — proceed to Step 5.

**If you have questions:** Ask them using `AskUserQuestion` (prefer multiple-choice options when possible). Wait for answers before proceeding. You may ask follow-up questions if the answers surface new ambiguities.

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

- **If `--no-confirm` is set:** Keep existing plan, skip to Step 8 (Beads init).
- **Otherwise:** Inform the user and ask using `AskUserQuestion`:
  - "Existing plan found at `docs/plans/<ISSUE-ID>.md`. Would you like to re-create it or keep the existing one?"
  - Options: "Re-create plan" (delete old plan, write new one, proceed to Step 7 for review; also triggers Beads task re-creation in Step 9), "Keep existing plan" (skip to Step 8)

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

### Step 8: Initialize Beads (if needed)

If the context above shows "BEADS_NOT_INITIALIZED", initialize Beads using the project directory name as the prefix:

```bash
bd init --prefix <project-directory-name> --skip-hooks
```

For example, if the project directory is `oncuria`, run `bd init --prefix onc --skip-hooks`. Use a short, recognizable abbreviation of the project name (3-4 characters).

### Step 9: Create Beads tasks (or detect existing)

Check if Beads tasks with label `<ISSUE-ID>` already exist:
```bash
bd list -l "<ISSUE-ID>" --limit 50 2>/dev/null
```

**If the user chose "Re-create plan" in Step 6:**

Delete all existing Beads tasks for this issue. List them first:
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

### Step 10: Update Linear status to In Progress

Use `mcp__plugin_linear_linear__update_issue` with:
- id: <the issue's UUID from step 2>
- state: "In Progress"

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

**If `--auto` flag is set:** Do NOT show "Next: Run /issue-task" in the summary above. Instead, immediately continue into auto-loop mode. Execute the full auto-loop as defined in the `/issue-task` command's Auto-Loop Mode: implement all unblocked tasks continuously with inline commits (following Conventional Commits, safe staging, HEREDOC format), show progress summaries after each task, then finish the issue (push branch, create PR with `Closes <ISSUE-ID>`, update Linear to "In Review", post completion comment). Follow the `--on-failure=stop` default for failure handling.
