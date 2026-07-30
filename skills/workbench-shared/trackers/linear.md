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
| `resolveDestination(hint?)` | Match a given hint against a team's key or name to resolve its native UUID. When the hint also names a project, validate that the project exists under the resolved team before returning it. When no hint is given, resolve the tracker profile's configured default destination the same way. Return the team UUID and any resolved project id together as this adapter's one destination value, per the contract's adapter-owned destination rule. Return null when the hint matches more than one team or project ambiguously. |
| `createIssue(title, description, type, destination)` | Create the issue with the resolved team UUID, the title, and the description. When a project was also resolved, add it to the create call so the issue lands in that project. Capture the created issue's key (for example `ONC-5`) and its URL from the tool response, and return both to the caller. |
| `createSubIssue(parentRef, title, description)` | Create the issue with the parent's native id set as its parent; do not pass a team, since Linear inherits the team from the parent issue. Capture the created issue's key and its URL from the tool response, and return both to the caller. |
| `updateState(ref, phase)` | Look up the workflow state name saved in the tracker profile's state mapping for the given phase, then update the issue's state to that name. When the profile explicitly records this phase as unmapped, a decision first-run setup captured from the user, skip the state mutation as a documented no-op rather than guessing a state. Never hardcode a status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Create a comment using the issue's native id and the comment body. |

## Notes

Linear issue refs are native keys shaped like `ONC-5`, a short uppercase team prefix, a dash, and digits.
Lowercase the key when building a branch name from it.
Linear's GitHub integration automatically closes an issue when a pull request whose body contains `Closes ONC-5` (or `Fixes`, using the issue's own key) merges into the default branch.
That integration is not present by default, and a fresh workspace has none until someone connects it.
Verified live: a pull request whose body contained `Closes TES-5` merged into the default branch and the issue stayed in review, with an empty attachments list on the issue confirming no integration had linked the pull request.
So do not assume it exists.

During first-run setup, establish which arrangement this workspace uses and record it in the profile as `merge-closer`.
Ask the user which arrangement applies; that answer is authoritative.
An empty `attachments` field on an issue whose pull request already merged is a useful hint that no integration is linking pull requests, and that was how a missing integration was detected during testing.
Treat the reverse as unverified: a populated `attachments` field has not been confirmed to mean the integration is connected, so never conclude `native` from attachments alone.
When the integration is connected, record `native` and do not force a `done` transition at merge time, because the integration handles it.
Let the sweep still run as the backstop, exactly as it does for Asana's native arrangement: Linear's integration reacts to merges into the default branch, so an issue whose pull request targeted a configured `base-branch` other than the default will not be closed by it, and only the sweep will catch that.
When it is not connected, record `installed` after adding the Action below, or `declined` when the user declines it, matching the values the Asana adapter uses so the profile field means one thing across trackers; in either case treat Linear exactly like Asana: the done-on-merge sweep applies the mapped `done` state itself and stamps the issue's file.
A merge-closer Action is also available for Linear, using the template below rather than the Asana one, since the two APIs differ.
Never leave the question unanswered, since an unanswered assumption is what leaves issues parked in review indefinitely.
Still use `updateState` to move the issue into `inProgress` and `inReview` at the appropriate points, since those transitions are not handled by the GitHub integration.

That integration only reacts to a merge, so a pull request closed without merging leaves the issue parked in review here exactly as it does on Asana.
Apply the rule described under "Pull requests closed without merging" in `../trackers.md`: never mark the issue done, never silently change its phase, tell the user which issue and which pull request were abandoned, and record the observation once in that issue's file under `.workbench/`, committing and pushing that record before the sweep returns exactly as `asana.md` requires, since an unpersisted marker re-reports the same abandoned pull request on every later run.

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

## Merge closer for Linear (optional)

Offer this only when the workspace has no GitHub integration, since a connected integration already does the job and the profile would record `native`.
When the user accepts, record `installed`; when they decline, record `declined` and let the sweep handle closure.
It needs a `LINEAR_API_KEY` repository secret, a personal API key from Linear's settings, and the workflow state id that the profile maps to the `done` phase.
Read that state id from the same list-issue-statuses call used during first-run setup, and substitute it into the template before writing the file.

Write it to `.github/workflows/workbench-close.yml`, commit it with the profile, and record `merge-closer: installed` so the sweep knows the Action owns the closure and only backstops it.
The file-discovery and ref-extraction block in this template is intentionally identical to the one in `asana.md`'s template; a change to either copy must be applied to both.

```yaml
name: workbench-close

on:
  pull_request:
    types: [closed]

jobs:
  close-linear-issue:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Close the Linear issue for the merged branch
        env:
          LINEAR_API_KEY: ${{ secrets.LINEAR_API_KEY }}
          DONE_STATE_ID: REPLACE_WITH_DONE_STATE_ID
          # Pass the branch through env, never into the script text: branch
          # names may contain shell metacharacters, which would run as code.
          BRANCH: ${{ github.event.pull_request.head.ref }}
        run: |
          if [ -z "$LINEAR_API_KEY" ]; then
            echo "No LINEAR_API_KEY secret set, skipping."
            exit 0
          fi

          if [ "$DONE_STATE_ID" = "REPLACE_WITH_DONE_STATE_ID" ]; then
            echo "DONE_STATE_ID was never substituted; refusing to run with a placeholder."
            exit 1
          fi

          # A branch must map to exactly one record; closing an issue picked
          # arbitrarily from several matches could complete the wrong one.
          MATCHES=$(grep -rlF "$BRANCH" .workbench/ 2>/dev/null | sort)
          MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)

          if [ "$MATCH_COUNT" -eq 0 ]; then
            echo "No file under .workbench/ references branch $BRANCH, skipping."
            exit 0
          fi
          if [ "$MATCH_COUNT" -gt 1 ]; then
            echo "Multiple files under .workbench/ reference branch $BRANCH; refusing to guess:"
            echo "$MATCHES"
            exit 1
          fi
          FILE="$MATCHES"

          # Only a labeled line is trusted. Matching any uppercase-dash-digits
          # token anywhere would also match RFC-7231, ISO-8601, SHA-1 and the
          # like, which appear legitimately in a plan document.
          KEY=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?(tracker|issue|ref)(\*\*)?[[:space:]]*[:-]' "$FILE" \
            | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1)

          if [ -z "$KEY" ]; then
            echo "No labeled Tracker, Issue, or Ref line carrying a Linear key in $FILE, skipping."
            exit 0
          fi

          RESPONSE=$(curl -sf https://api.linear.app/graphql \
            -H "Authorization: $LINEAR_API_KEY" \
            -H 'Content-Type: application/json' \
            -d "{\"query\":\"mutation { issueUpdate(id: \\\"$KEY\\\", input: { stateId: \\\"$DONE_STATE_ID\\\" }) { success } }\"}") \
            || { echo "Linear API call failed for $KEY"; exit 1; }

          # A GraphQL error arrives with HTTP 200, so -f alone is not enough;
          # parse the JSON instead of pattern-matching the raw text, which
          # would misread payloads that merely contain those substrings.
          if ! printf '%s' "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "Unexpected (non-JSON) Linear response for $KEY: $RESPONSE"
            exit 1
          fi
          if printf '%s' "$RESPONSE" | jq -e '(.errors // []) | length > 0' >/dev/null; then
            echo "Linear returned an error for $KEY: $RESPONSE"
            exit 1
          fi
          if [ "$(printf '%s' "$RESPONSE" | jq -r '.data.issueUpdate.success // false')" = "true" ]; then
            echo "Closed $KEY."
          else
            echo "Unexpected Linear response for $KEY: $RESPONSE"
            exit 1
          fi
```

This template has not been run end to end; the Asana template has.
It also assumes Linear's `issueUpdate` accepts a human key such as `TES-5` for its `id` argument; confirm that on the first run, and resolve the key to a UUID with a query first if it does not.
Say so when offering it, and suggest verifying the first merge rather than assuming it worked.
The `curl` usage here belongs to the Action running in CI with its own repository secret; it is never a licence for the agent to call the Linear API directly, which the absolute boundary forbids.
