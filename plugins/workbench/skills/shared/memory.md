# Task memory

Task state lives in exactly one durable backend per run.
The backend is resolved by probing, never configured.

## The contract

Use exactly these six operations.
Adapter files implement each one against a specific backend; treat the operation names as the vocabulary for every other skill and adapter in this plugin.

| Operation | Purpose |
| --- | --- |
| `init(issueRef)` | Prepare the backend for this issue's task set. |
| `createTask(title, description, subIssueRef, deps)` | Create a task, tag it with the issue ref so all tasks for one issue can be listed directly, record `subIssueRef` on the task, and return its task id. |
| `claimNext()` | Return and mark in-progress the first open task whose deps are all closed; return null when none remain. |
| `close(taskId)` | Mark a task done. |
| `status()` | Return open/done counts and the current in-progress task. |
| `parentTask(issueRef)` | Create or fetch the parent task representing the overarching issue, and make it depend on every child task so it cannot close before they do. |

## Resolution

Probe once per run, before doing any task-memory work.
Existing state wins over capability: never switch backends mid-issue just because a capability becomes available partway through.

Follow this order:

Check the issue's own state before the repository's state, because the per-issue signal decides that issue's backend.

When `.workbench/tasks/<ISSUE-REF>.md` exists and contains task checkboxes, use the checklist adapter for this issue.
Do this even when `.beads/` exists and even when `bd` is installed.
An issue whose statuses already live in checkboxes keeps that backend for its whole life; adding beads to a repository later must never move an in-flight issue, which would orphan the statuses already recorded in its checklist file.

Otherwise, when `.beads/` exists in the repo, check whether `bd --version` succeeds.
Use the beads adapter when it does.
When it does not, stop and tell the user that this repo's task state lives in beads but the `bd` binary is not available on this machine.
Ask them to install beads or continue on a machine that has it.
Do not fall back to the checklist adapter in this case: task status must never fork across two backends, per the no-dual-truth rule below.

When neither exists (a fresh run for this issue), check whether `bd --version` succeeds; use the beads adapter if it does, otherwise use the checklist adapter.

Repositories do change backends over time, and that is fine as long as it happens per issue.
When a repository gains beads while checklist-mode issues are still open, those issues stay on checklists and only issues started afterward use beads.
Do not ask the user to choose a backend; resolution is a silent probe.
Do state the resolved backend in the run summary whenever it differs from what the repository's other open issues are using, so a mixed-backend period is visible rather than surprising.

Both backends store their state inside the repo, so any later session on any machine resumes correctly by reading the repo.
Resume by reading the working tree, not the last commit.
An in-progress marker may be uncommitted when a session dies, and the file on disk is the truth, not whatever was last committed.

## Display overlay

When the agent exposes built-in task-list tools, mirror tasks into them for a live progress UI.
Rebuild the overlay from the durable backend on every resume; do not carry overlay state across sessions.
Never read the overlay as the source of truth; the durable backend answers every question about task state.
Skip the overlay silently when the agent exposes no such tools.

## No dual truth

Task status never lives in two places.
When the beads adapter is active, the checklist file at `.workbench/tasks/<ISSUE-REF>.md` contains the plan only, with no checkboxes.
When the checklist adapter is active, that same file holds both the plan and the statuses.
