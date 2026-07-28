---
name: Issue Lifecycle
description: This skill should be used when the user asks to "work on an issue", "start an issue", "implement this Asana/Linear issue", "take this issue to a PR", pastes an Asana task URL to build, or names a Linear issue key like ONC-5. Drives the issue from breakdown through implementation to an open PR with resumable task tracking.
version: 3.0.0
---

# Issue Lifecycle

This skill drives one tracker issue through a single resumable autonomous pass, from breakdown through implementation to an open pull request.
There is no separate start step and finish step; re-invoke this same skill on the same issue to resume wherever the last run left off.
Every run begins by reading durable state from the repository and the tracker, not from anything remembered between invocations.

## Operating principles

- Treat this as one resumable pass guarded by observable artifacts on disk and in the tracker, never by memory of a previous run.
- After the first-run tracker profile is confirmed, proceed without further mid-run confirmation; only stop when this procedure says to stop.
- The memory backend is the source of truth for task state; state flows one way from it to the tracker, never the reverse.
- On an unfixable test failure, stop and hold rather than pushing partial or broken work forward.

## Read first

Before doing any tracker or memory work, read:

- `../shared/trackers.md` for the tracker contract, phase names, and first-run profile setup.
- `../shared/memory.md` for the memory contract and backend resolution rules.
- `../shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.

## Procedure

1. Run the Asana done-on-merge sweep described in `../shared/trackers/asana.md` before any other tracker work in this repository.
2. Resolve which tracker owns this issue and which memory backend owns its task state, following `trackers.md` and `memory.md`; load the existing `.issue-lifecycle/config.md` tracker profile, or run first-run setup when none exists.
3. Determine the issue ref from the invocation argument, a pasted issue URL, or the current branch name, in that order of preference; when the argument and the branch name name different issues, stop and ask the user which one to use.
4. Call `getIssue` for that ref and save its title, description, type, URL, and existing children for the rest of this run.
5. Search the codebase and read the files that look relevant to this issue, noting existing patterns to follow during implementation.
6. Ensure a feature branch exists for this issue; when one must be created, prefix its name from the issue type (`feat/` for a feature, `fix/` for a bug, `chore/` for a chore, `docs/` for docs, `feat/` by default) followed by the issue ref and a short title slug; skip creation when a matching branch already exists.
7. Ensure the breakdown exists; when it does not, call `parentTask` for the issue, then for each planned unit of work call `createTask` and `createSubIssue` and link the two together, and write the resulting plan into the checklist file at `.issue-lifecycle/tasks/<ISSUE-REF>.md`; when the issue already has children, adopt them via `listSubIssues` instead of inventing a new breakdown; skip this step entirely when a breakdown already exists.
8. Call `updateState` to move the issue to the `inProgress` phase.
9. Run the implementation loop until it stops naturally: call `claimNext`, move the claimed task's linked sub-issue to `inProgress`, implement that unit of work following the codebase patterns found in step 5, then run the tests related to that unit; on a passing run, commit the change with a message referencing the issue ref and the task, call `close` on the task, and move its sub-issue to `done`; on a failure that cannot be fixed, stop and hold, leaving the change uncommitted or committed as-is, the task still in progress, and report the failure before exiting.
10. Once `claimNext` returns none remaining, finish the issue: commit any leftover uncommitted change, close the parent task, push the branch, and open the pull request with the `gh` command-line tool unless one already exists, with a body containing `Closes <ref>` for a Linear issue or the task's URL for an Asana task, plus a summary, the list of completed tasks, and a test plan; call `updateState` to move the issue to the `inReview` phase; then post a completion comment on the issue, including the done-on-merge note from `asana.md` when the tracker is Asana.
11. Report a final summary: the issue, the pull request URL, the tracker's current phase, and the task counts from `status()`.

## Display overlay

When the running agent exposes built-in task-list capabilities, mirror progress into them for a live view; follow the display-overlay rule in `memory.md` and never treat that view as authoritative.
