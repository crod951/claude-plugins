# Task memory

Task state lives in exactly one durable backend per run.
The backend is resolved by probing, never configured.

## The contract

Use exactly these six operations.
Adapter files implement each one against a specific backend; treat the operation names as the vocabulary for every other skill and adapter in this plugin.

| Operation | Purpose |
| --- | --- |
| `init(issueRef)` | Prepare the backend for this issue's task set. |
| `createTask(title, description, subIssueRef, deps)` | Create a task and return its task id. |
| `claimNext()` | Return and mark in-progress the first open task whose deps are all closed; return null when none remain. |
| `close(taskId)` | Mark a task done. |
| `status()` | Return open/done counts and the current in-progress task. |
| `parentTask(issueRef)` | Create or fetch the parent task representing the overarching issue. |

## Resolution

Probe once per run, before doing any task-memory work.
Existing state wins over capability: never switch backends mid-issue just because a capability becomes available partway through.

Follow this order:

When `.beads/` exists in the repo, use the beads adapter.
When `.issue-lifecycle/tasks/<ISSUE-REF>.md` exists and contains task checkboxes, use the checklist adapter, even when `bd` is installed; never switch backends mid-issue.
When neither exists (a fresh run for this issue), check whether `bd --version` succeeds; use the beads adapter if it does, otherwise use the checklist adapter.

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
When the beads adapter is active, the checklist file at `.issue-lifecycle/tasks/<ISSUE-REF>.md` contains the plan only, with no checkboxes.
When the checklist adapter is active, that same file holds both the plan and the statuses.
