# Linear adapter

This adapter is backed by the Linear MCP.
Before calling any tool, verify the connected server's actual tool names; do not hardcode a specific build's tool names.
Create and update tools are commonly consolidated into a single save-style tool that takes an id to update an existing issue or omits it to create a new one; confirm which shape the connected server uses before calling it.
Fetch, list, and current-user tools are comparatively stable across builds, but still confirm their names exist on the connected server before the first call.
When a tool name assumed below does not exist on the connected server, list the server's available tools and re-map each operation to the closest match before proceeding.

## Operation mapping

| Contract operation | Linear MCP behavior |
| --- | --- |
| `getIssue(ref)` | Fetch the issue by its key (for example `ONC-5`) using a get-issue-style tool. Save the native UUID, the issue URL, its labels, and its current workflow state from the response; later operations that need the native id should reuse the saved UUID rather than re-fetching. |
| `listSubIssues(ref)` | List issues filtered by parent, using the native UUID or key of the issue from `getIssue`. Return each child's id, title, and state. |
| `listDestinations()` | List the viewer's team memberships using the current-user tool, not a full workspace team list. For each team the viewer belongs to, list that team's projects when a destination narrower than the team is needed. Never call a tool that lists every team in the workspace. |
| `resolveDestination(hint?)` | Match a given hint against a team's key or name to resolve its native UUID. When the hint also names a project, validate that the project exists under the resolved team before returning it. When no hint is given, resolve the tracker profile's configured default destination the same way. Return null when the hint matches more than one team or project ambiguously. |
| `createIssue(title, description, type, destination)` | Create the issue with the resolved team UUID, the title, and the description. When a project was also resolved, add it to the create call so the issue lands in that project. Capture the created issue's key (for example `ONC-5`) and its URL from the tool response, and return both to the caller. |
| `createSubIssue(parentRef, title, description)` | Create the issue with the parent's native id set as its parent; do not pass a team, since Linear inherits the team from the parent issue. Capture the created issue's key and its URL from the tool response, and return both to the caller. |
| `updateState(ref, phase)` | Look up the workflow state name saved in the tracker profile's state mapping for the given phase, then update the issue's state to that name. Never hardcode a status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Create a comment using the issue's native id and the comment body. |

## Notes

Linear issue refs are native keys shaped like `ONC-5`, a short uppercase team prefix, a dash, and digits.
Lowercase the key when building a branch name from it.
Linear's GitHub integration automatically closes an issue when a pull request whose body contains `Closes ONC-5` (or `Fixes`, using the issue's own key) merges into the default branch.
That integration is not present by default, and a fresh workspace has none until someone connects it.
Verified live: a pull request whose body contained `Closes TES-5` merged into the default branch and the issue stayed in review, with an empty attachments list on the issue confirming no integration had linked the pull request.
So do not assume it exists.

During first-run setup, establish which arrangement this workspace uses and record it in the profile as `merge-closer`.
Read the issue's `attachments` field after any prior merge, or simply ask: when the GitHub integration is connected, record `native` and do not force a `done` transition at merge time, because the integration handles it.
When it is not connected, record `sweep` and treat Linear exactly like Asana: the done-on-merge sweep applies the mapped `done` state itself and stamps the issue's file, and the merge-closer Action is an option here too since the Linear API can set an issue's state.
Never leave the question unanswered, since an unanswered assumption is what leaves issues parked in review indefinitely.
Still use `updateState` to move the issue into `inProgress` and `inReview` at the appropriate points, since those transitions are not handled by the GitHub integration.

That integration only reacts to a merge, so a pull request closed without merging leaves the issue parked in review here exactly as it does on Asana.
Apply the same rule described under "Pull requests closed without merging" in `asana.md`: never mark the issue done, never silently change its phase, tell the user which issue and which pull request were abandoned, and record the observation once in that issue's file under `.workbench/`.

## First-run profile for Linear

During first-run tracker profile setup, list the target team's workflow states using a list-issue-statuses-style tool scoped to that team.
Propose the closest matching state name for each of the three phases, `inProgress`, `inReview`, and `done`.
Favor states whose names or categories obviously correspond, for example a state named "In Progress" or categorized as started for the `inProgress` phase, a state named "In Review" for the `inReview` phase, and a state named "Done" or categorized as completed for the `done` phase.
Show the proposed mapping to the user and let them confirm or correct it before saving the profile, following the procedure in `trackers.md`.

## Setup instructions

Use the current-user tool as the preflight verification call for Linear.
A successful, error-free response from that call is what confirms the MCP is connected and usable; anything else, including no matching tool being available, counts as unverified.

Linear's MCP is installed as a connector or plugin in the agent, not configured by hand with a raw server URL.
Do not invent a specific Linear MCP endpoint; point the user at Linear's own official MCP documentation for the current endpoint and setup steps, since that detail changes over time and an invented URL would be worse than no URL.

For Claude Code, tell the user to install the Linear MCP connector or plugin and authenticate through it.
For Kiro, tell the user to add a Linear MCP server entry to `mcp.json`, using the endpoint from Linear's documented setup for that agent.

Either way, tell the user to check for a `disabled` flag on an existing entry before assuming the server needs to be added from scratch; a disabled server presents to preflight the same as a missing one.
The current-user verification call above, not the setup steps themselves, is what confirms the connection actually succeeded.
