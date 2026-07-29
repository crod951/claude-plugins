---
name: execute
description: This skill should be used when the user asks to "execute ONC-5", "run execute on this issue", "work on an issue", "start an issue", "implement this Asana/Linear issue", "take this issue to a PR", pastes an Asana task URL to build, or names a Linear issue key like ONC-5. Also use when the user says something like "the PR for <issue> merged", "clean up merged issues", or "close out merged work", to run the done-on-merge sweep on demand. Drives an existing tracker issue from breakdown through implementation to an open PR with resumable task tracking.
version: 3.0.0
---

# Execute

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse the request and stop.
Say which MCP is missing and that the user must connect it before this skill can continue.
Refuse even when a bypass looks possible and helpful.
Do not read or search for credentials in files, environment variables, or token caches.
Do not call tracker HTTP APIs.
Do not edit MCP or agent configuration.
Treat a disabled server as a deliberate user decision, a stop condition, never an obstacle to route around.

This skill drives one tracker issue through a single resumable autonomous pass, from breakdown through implementation to an open pull request.
There is no separate start step and finish step; re-invoke this same skill on the same issue to resume wherever the last run left off.
Every run begins by reading durable state from the repository and the tracker, not from anything remembered between invocations.

## Operating principles

- Treat this as one resumable pass guarded by observable artifacts on disk and in the tracker, never by memory of a previous run.
- After the first-run tracker profile is confirmed, proceed without further mid-run confirmation; only stop when this procedure says to stop.
- The memory backend is the source of truth for task state; state flows one way from it to the tracker, never the reverse.
- On an unfixable test failure, stop and hold rather than pushing partial or broken work forward.
- Tracker access goes only through the connected tracker MCP; when it is missing, stop and say so; never hunt for credentials on disk or call tracker APIs directly.

## Read first

Before doing any tracker or memory work, read:

These paths are relative to the directory containing this SKILL.md file, not the current workspace.
In a global Kiro install they resolve under `~/.kiro/skills/` (for example `~/.kiro/skills/shared/trackers.md`); in a Claude Code plugin install they resolve inside the plugin's `skills/` directory.

- `../shared/trackers.md` for the tracker contract, phase names, and first-run profile setup.
- `../shared/memory.md` for the memory contract and backend resolution rules.
- `../shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.
- `../shared/conventions.md` for staging safety, commit messages, the plan document, and progress reporting.

If any of these files cannot be found and read, stop immediately and report which paths were tried - never improvise their contracts from memory or proceed without them.

## Procedure

1. Run preflight verification as described in `../shared/trackers.md` before any other step.
   Stop here, following that section's instructions, when the tracker's MCP does not verify.
2. Run the Asana done-on-merge sweep described in `../shared/trackers/asana.md`; this sweep is itself tracker work, so it only runs once preflight has verified the MCP.
   When the invocation itself was a cleanup phrase such as "the PR for <issue> merged", "clean up merged issues", or "close out merged work", run only this sweep, report what was closed, then stop; do not continue into the rest of this procedure.
3. Resolve which tracker owns this issue and which memory backend owns its task state, following `trackers.md` and `memory.md`.
   When the repo already contains beads state but the beads tooling is unavailable on this machine, stop and say so as memory.md directs; never substitute a different backend for a repo whose state lives in another one.
   Load the existing `.workbench/config.md` tracker profile, or run first-run setup when none exists; either way, run the tracker adapter's profile-load checks and honor any one-time offers they define.
4. Determine the issue ref from the invocation argument, a pasted issue URL, or the current branch name, in that order of preference; when the argument and the branch name name different issues, stop and ask the user which one to use.
5. Call `getIssue` for that ref and save its title, description, type, URL, and existing children for the rest of this run.
6. Search the codebase and read the files that look relevant to this issue, noting existing patterns to follow during implementation.
7. Ensure a feature branch exists for this issue; when one must be created, prefix its name from the issue type (`feat/` for a feature, `fix/` for a bug, `chore/` for a chore, `docs/` for docs, `feat/` by default) followed by the issue ref and a short title slug; skip creation when a matching branch already exists.
8. Ensure the breakdown exists.
   - Skip the rest of this step when a breakdown already exists for this issue.
   - Call `init` for the issue, then call `parentTask` for it.
   - When the issue has no existing children, plan the units of work; for each one, call `createSubIssue` first, then call `createTask` with the newly created sub-issue's ref as `subIssueRef`, setting `deps` to the id of the task it builds on so tasks chain sequentially by default whenever order matters.
   - When the issue already has children, call `listSubIssues` to adopt them instead of inventing a new breakdown; for each adopted sub-issue, still call `createTask`, passing that sub-issue's existing ref as `subIssueRef` and skipping `createSubIssue` since the sub-issue already exists, and setting `deps` the same way.
   - Either way, write the resulting plan into the checklist file at `.workbench/tasks/<ISSUE-REF>.md`.
   - Also write the plan document described in `conventions.md` and commit it with the breakdown.
9. Call `updateState` to move the issue to the `inProgress` phase.
10. Run the implementation loop until it stops naturally: call `claimNext`, record the claim in the memory backend's own format at claim time, move the claimed task's linked sub-issue to `inProgress`, implement that unit of work following the codebase patterns found in step 5, then run the tests related to that unit; on a passing run, commit the change with a message referencing the issue ref and the task, call `close` on the task, record the close in the memory backend's own format at close time, and move its sub-issue to `done`; on a failure that cannot be fixed, stop and hold, leaving the change uncommitted or committed as-is, the task still in progress, and report the failure before exiting.
    Stage and word every commit per `conventions.md`; never stage with a blanket pattern and never stage a file that could carry a secret.
    Never combine multiple tasks into one commit, even when they touch the same file; each task gets its own claim, commit, and close.
    Print the per-task progress line from `conventions.md` after each close.
    Record status changes as they happen rather than summarizing them at the end of the loop.
11. Once `claimNext` returns none remaining, finish the issue: commit any leftover uncommitted change, close the parent task, push the branch, and open the pull request with the `gh` command-line tool unless one already exists, with a body containing `Closes <ref>` for a Linear issue or the task's URL for an Asana task, plus a summary, the list of completed tasks, and a test plan; call `updateState` to move the issue to the `inReview` phase; then post a completion comment on the issue, including the done-on-merge note from `asana.md` when the tracker is Asana, and commit and push any changed or new task-state files under `.beads/` (including files its own tooling creates) and `.workbench/` as a final closing commit so the branch carries the completed state.
12. Report a final summary: the issue, the pull request URL, the tracker's current phase, and the task counts from `status()`.

## Display overlay

When the running agent exposes built-in task-list capabilities, mirror progress into them for a live view; follow the display-overlay rule in `memory.md` and never treat that view as authoritative.
