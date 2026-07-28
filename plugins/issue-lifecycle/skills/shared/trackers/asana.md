# Asana adapter

This adapter is backed by the Asana MCP.
Before calling any tool, verify the connected server's actual tool names.
Do not hardcode a specific build's tool names.
Create-task and create-subtask tools are typically distinct from a single generic save-style tool.
Confirm which shape the connected server offers before calling it.
Fetch, list, and search tools tend to stay stable across builds, but still confirm their names exist on the connected server before the first call.
When an assumed tool name below does not exist on the connected server, list the server's available tools and re-map each operation to the closest match before proceeding.

## Operation mapping

| Contract operation | Asana MCP behavior |
| --- | --- |
| `getIssue(ref)` | Fetch the task by its GID, parsed from a pasted task URL, using a get-task-style tool. When no URL or GID is available, fall back to a name-search tool and confirm the single best match with the user before proceeding. Save the task's GID, its permalink URL, its completed flag, and its memberships (the project and section it currently sits in) from the response; later operations that need the native id should reuse the saved GID rather than re-fetching. |
| `listSubIssues(ref)` | List the task's subtasks using a list-subtasks-style tool scoped to the parent GID. Return each subtask's GID, title, and completed flag. |
| `listDestinations()` | List the projects in the workspace that the user can access, using a list-projects-style tool. Return each project as its GID paired with its display name. |
| `resolveDestination(hint?)` | Match a given hint against a project's name or GID to resolve its native GID. When no hint is given, resolve the tracker profile's configured default destination the same way. Return null when the hint matches more than one project ambiguously. |
| `createIssue(title, description, type, destination)` | Create the task with the resolved project GID, the title, and the description. Capture the created task's GID and its permalink URL from the tool response, and return both to the caller. |
| `createSubIssue(parentRef, title, description)` | Create the task with the parent's GID set as its parent; do not pass a project, since Asana inherits project membership from the parent task. Capture the created subtask's GID and its permalink URL from the tool response, and return both to the caller. |
| `updateState(ref, phase)` | Apply this only to the main task, never to a subtask. Look up the tracker profile's state mapping for the given phase, then either move the task to the mapped section or set the mapped status custom field, whichever the profile records. When the phase is `done`, additionally set the task's completed flag to true. Never hardcode a section or status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Post a story (comment) on the task using its GID and the comment body. |

## Issue references

Asana has no human-readable issue key equivalent to Linear's `ONC-5`.
Invocation is by a pasted task URL.
When no URL is available, fall back to a name search and confirm the match with the user before proceeding.
The ref used in branch names and checklist filenames is `asana-<last 6 digits of the task GID>`.
Branches append a title slug to that ref, for example `feat/asana-482913-add-login`.
Record the full task URL in the checklist file, in the tracker profile, and in the PR body.
That URL is what lets a resumed session find the task again.

## Subtask limitation

Subtasks do not appear in board sections unless a person explicitly adds them there.
Because of that, the profile's section and status-custom-field mapping applies to the main task only.
Never apply that mapping to a subtask.
Sub-issue state transitions degrade to the completed flag instead: moving a subtask to `inProgress` is a no-op, or at most an optional comment noting that work has started, and moving a subtask to `done` sets its completed flag to true.

## Done on merge

Asana has no PR-merge integration comparable to Linear's GitHub integration.
At PR open, move the main task to the mapped `inReview` state and post a comment stating that the task will be closed by the next skill run after the PR merges.
Every skill invocation in a repo must run a merge sweep before doing any other tracker work.
The sweep checks whether any `.issue-lifecycle/tasks/*.md` file references an Asana task whose PR has since merged, using `gh pr view <branch> --json state,mergedAt`.
When the sweep finds a merged PR for an Asana task, apply the mapped `done` state and set the completed flag before proceeding with the rest of the run.
For idempotency, append a `- Closed: <date>` line to that checklist file immediately after closing the task, and commit the file to the default branch.
The sweep skips any checklist file that already carries a Closed line, so the merge check runs at most once per issue.
