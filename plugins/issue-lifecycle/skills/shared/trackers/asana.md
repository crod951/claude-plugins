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
| `updateState(ref, phase)` | Apply this only to the main task, never to a subtask. Look up the tracker profile's state mapping for the given phase, then follow this fallback chain in order: (a) if the connected MCP exposes a section-move or add-to-section tool, move the main task to the mapped section; (b) else if the profile maps a status custom field and a task-update tool can set that field, set the field to the mapped value; (c) else post a comment stating the phase transition, for example "Phase: In Review - <PR url>". When the phase is `done`, always set the task's completed flag to true regardless of which branch of the chain applied. Skipping the transition silently is not allowed; the fallback comment in step (c) is the minimum required action. Never hardcode a section or status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Post a story (comment) on the task using its GID and the comment body. |

The deprecated V1 server (mcp.asana.com/sse, shutdown 2026-11-05) lacks a section-move tool, so the V2 server (mcp.asana.com/v2/mcp) is recommended for full section-move support.

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

## Merge closer (optional)

Run this check whenever the tracker profile is loaded or created for this repository, not only during first-run setup.
First-run setup triggers the same load-time check as part of creating the profile; it does not run a separate ask.
When the tracker is Asana, check the profile for a `merge-closer:` line.
When that line is absent, ask the user once whether to install the merge-closer GitHub Action for instant Asana closure on PR merge, then record the answer in the profile right away.
Ask whenever no `merge-closer:` line is on record; once one is recorded, never ask again for this repository.
When the answer is yes, write `.github/workflows/issue-lifecycle-close.yml` from the template below, record `merge-closer: installed` in the tracker profile, and commit both together.
Tell the user to add an `ASANA_TOKEN` repository secret, an Asana personal access token, since the workflow cannot post to the Asana API without it.
When the answer is no, record `merge-closer: declined` in the tracker profile.
The passive sweep and the on-demand cleanup trigger described in the issue-lifecycle skill keep working either way; this Action is an additive fast path, not a replacement.
The curl call to the Asana API in the template below exists exclusively for this GitHub Action running in CI, authenticated with its own repository secret.
The agent must never run that curl call, or any other direct call to the Asana API, interactively.
The agent must never borrow the `ASANA_TOKEN` secret or any other token from disk to reach the Asana API itself; the connected Asana MCP is the only channel the agent uses at runtime.

```yaml
name: issue-lifecycle-close

on:
  pull_request:
    types: [closed]

jobs:
  close-asana-task:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Close Asana task for merged branch
        env:
          ASANA_TOKEN: ${{ secrets.ASANA_TOKEN }}
        run: |
          if [ -z "$ASANA_TOKEN" ]; then
            echo "No ASANA_TOKEN secret set, skipping."
            exit 0
          fi

          BRANCH="${{ github.event.pull_request.head.ref }}"
          TASK_FILE=$(grep -rl "$BRANCH" .issue-lifecycle/tasks/ 2>/dev/null | head -n 1)

          if [ -z "$TASK_FILE" ]; then
            echo "No checklist file references branch $BRANCH, skipping."
            exit 0
          fi

          TASK_URL=$(grep -oE 'https://app\.asana\.com/[^ )>]+' "$TASK_FILE" | head -n 1)

          if [ -z "$TASK_URL" ]; then
            echo "No Asana task URL found in $TASK_FILE, skipping."
            exit 0
          fi

          TASK_GID=$(echo "$TASK_URL" | grep -oE '[0-9]+$')

          if [ -z "$TASK_GID" ]; then
            echo "Could not extract a task GID from $TASK_URL, skipping."
            exit 0
          fi

          curl -s -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
            -H "Authorization: Bearer $ASANA_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"data":{"completed":true}}'
```

The Action closes the task by setting the completed flag directly through the Asana API.
Section moves at other phases still follow the `updateState` fallback chain described above; this Action only ever sets completed on merge, it never moves sections.
