# Linear adapter

This adapter is backed by the Linear MCP.
Before calling any tool, verify the connected server's actual tool names; do not hardcode a specific build's tool names.
Create and update tools are commonly consolidated into a single save-style tool that takes an id to update an existing issue or omits it to create a new one; confirm which shape the connected server uses before calling it.
Fetch, list, and current-user tools are comparatively stable across builds, but still confirm their names exist on the connected server before the first call.
When a tool name assumed below does not exist on the connected server, list the server's available tools and re-map each operation to the closest match before proceeding.

## Operation mapping

| Contract operation | Linear MCP behavior |
| --- | --- |
| `getIssue(ref)` | Fetch the issue by its key (for example `ONC-5`) using a get-issue-style tool. Save the native UUID, the issue URL, its labels, and its current workflow state from the response; later operations that need the native id should reuse the saved UUID rather than re-fetching. When the response carries the issue's comments, save their bodies in the order returned as well, since on builds with no separate comment-listing tool `listComments` reads from this saved response. |
| `listSubIssues(ref)` | List issues filtered by parent, using the native UUID or key of the issue from `getIssue`. Return each child's id, title, and state. |
| `listDestinations()` | List the viewer's team memberships using the current-user tool, not a full workspace team list. For each team the viewer belongs to, list that team's projects when a destination narrower than the team is needed. Never call a tool that lists every team in the workspace. |
| `resolveDestination(hint?)` | Match a given hint against a team's key or name to resolve its native UUID. When the hint also names a project, validate that the project exists under the resolved team before returning it. When no hint is given, resolve the tracker profile's configured default destination the same way. Return the team UUID and any resolved project id together as this adapter's one destination value, per the contract's adapter-owned destination rule. Return null when the hint matches more than one team or project ambiguously. |
| `createIssue(title, description, type, destination)` | Create the issue with the resolved team UUID, the title, and the description. When a project was also resolved, add it to the create call so the issue lands in that project. Capture the created issue's key (for example `ONC-5`) and its URL from the tool response, and return both to the caller. |
| `createSubIssue(parentRef, title, description)` | Create the issue with the parent's native id set as its parent; do not pass a team, since Linear inherits the team from the parent issue. Capture the created issue's key and its URL from the tool response, and return both to the caller. |
| `updateState(ref, phase)` | Look up the workflow state name saved in the tracker profile's state mapping for the given phase, then update the issue's state to that name. When the profile explicitly records this phase as unmapped, a decision first-run setup captured from the user, skip the state mutation as a documented no-op rather than guessing a state. Never hardcode a status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Create a comment using the issue's native id and the comment body. |
| `listComments(ref)` | List the issue's comments using a list-comments-style tool scoped to the issue's native UUID or key, and return each comment's body, newest first. Some builds return comments as part of a get-issue call rather than exposing a separate tool; when they do, read them from the response already saved by `getIssue` instead of making a second call. When neither path is available, treat this operation as unavailable and report that. |

## Notes

Linear issue refs are native keys shaped like `ONC-5`, a short uppercase team prefix, a dash, and digits.
Lowercase the key when building a branch name from it.
Everything in this section about automatic closure assumes the resolved forge is GitHub.
Linear's integration is a GitHub integration; it observes GitHub pull requests and nothing else.
When the resolved forge is not GitHub, skip the whole arrangement question regardless of what `ciHooks` declares - the integration and the Action template below are both GitHub-specific - record `merge-closer: none (forge is not GitHub)`, and let the sweep close issues through `updateState` as the sole mechanism.

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
When it is not connected, record `installed` after adding the Action below, or `declined` when the user declines it, matching the values the Asana adapter uses so the profile field means one thing across trackers; in either case treat Linear exactly like Asana: the done-on-merge sweep applies the mapped `done` state itself.
A merge-closer Action is also available for Linear, using the template below rather than the Asana one, since the two APIs differ.
Never leave the question unanswered, since an unanswered assumption is what leaves issues parked in review indefinitely.
Still use `updateState` to move the issue into `inProgress` and `inReview` at the appropriate points, since those transitions are not handled by the GitHub integration.

That integration only reacts to a merge, so a review closed without merging leaves the issue parked in review here exactly as it does on Asana.
Apply the rule described under "Reviews closed without merging" in `../trackers.md`: never mark the issue done, never silently change its phase, tell the user which issue and which review were abandoned, and record the observation once as a sentinel comment on the issue, since an unrecorded marker re-reports the same abandoned review on every later run.

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

Write it to `.github/workflows/fathom-close.yml`, commit it with the profile, and record `merge-closer: installed` so the sweep knows the Action owns the closure and only backstops it.

Never asking again applies to the question, not to the file.
When the profile records `merge-closer: installed` and does not record a declined template rewrite, compare the repository's `.github/workflows/fathom-close.yml` against the template below on profile load, and when the file-discovery block differs, offer once to rewrite the file from the current template.
An installed workflow is a copy taken at install time, so a repository that accepted it before a template fix keeps running the old copy forever and never benefits from the fix.
State what differs and that the rewrite only replaces the workflow file.
On a yes, rewrite it and leave `merge-closer: installed` as it stands.
On a no, record `merge-closer: installed (template-rewrite declined)`, so the offer is not repeated on every later load, and treat that value exactly like `installed` everywhere else.
Recording the decline is what makes this a one-time offer rather than a prompt on every run, matching how every other question here is asked once and answered in the profile.

The file-discovery and ref-extraction block in this template is intentionally identical to the one in `asana.md`'s template; a change to either copy must be applied to both.
Four differences are expected and not drift: the marker comment names the other file, the leading comment says task and wrong issue in one copy and issue and wrong one in the other, this copy names its selected file `FILE` where `asana.md` names it `TASK_FILE`, and the leading comment says issue where the other says task.

```yaml
name: fathom-close

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

          # fathom:discovery-block start
          # Everything between these markers is shared verbatim with asana.md.
          # A branch must map to exactly one record; closing an issue picked
          # arbitrarily from several matches could complete the wrong one.
          # Only a labeled Branch line is trusted, and it must equal the branch
          # exactly. An unanchored search also hits the branch name quoted in
          # another issue's prose, and a bare substring makes feat/tes-5 match
          # feat/tes-50; either one yields a false multi-match that refuses to
          # close anything, or picks the wrong record.
          BRANCH_RE=$(printf '%s' "$BRANCH" | sed 's/[][\^$.*+?(){}|]/\\&/g')
          LABELED='^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Bb]ranch(\*\*)?[[:space:]]*[:-][[:space:]]*`?'
          MATCHES=$(grep -rlE "${LABELED}${BRANCH_RE}\`?[[:space:]]*$" .fathom/ 2>/dev/null | sort || true)
          MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)

          # Records written before the labeled Branch line was required still
          # resolve through the original unanchored search, so upgrading does
          # not silently stop closing issues that were already in flight.
          if [ "$MATCH_COUNT" -eq 0 ]; then
            MATCHES=$(grep -rlF "$BRANCH" .fathom/ 2>/dev/null | sort || true)
            MATCH_COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
            if [ "$MATCH_COUNT" -gt 0 ]; then
              echo "No labeled Branch line matched $BRANCH; using the legacy unanchored search over:"
              echo "$MATCHES"
              # This fallback is deliberately the pre-fix unanchored search, so
              # it still substring-matches feat/tes-50 for branch feat/tes-5.
              # Migrate legacy records to a labeled Branch line rather than
              # relying on it.
            fi
          fi

          if [ "$MATCH_COUNT" -eq 0 ]; then
            echo "No file under .fathom/ references branch $BRANCH, skipping."
            exit 0
          fi

          # One issue legitimately has two records: the plan document under
          # plans/ and, in checklist mode, the task file under tasks/. Both are
          # named <ISSUE-REF>.md, so collapse on the file name before judging
          # ambiguity. Counting files instead would refuse every checklist-mode
          # merge, since both records carry the same labeled Branch line.
          STEMS=$(printf '%s\n' "$MATCHES" | sed 's#.*/##' | sort -u)
          STEM_COUNT=$(printf '%s' "$STEMS" | grep -c . || true)
          if [ "$STEM_COUNT" -gt 1 ]; then
            echo "Files under .fathom/ for branch $BRANCH name different issues; refusing to guess:"
            echo "$MATCHES"
            exit 1
          fi

          # A stacked issue records one branch per bundle, so any one bundle's
          # merge reaches this Action while the rest of the work is still open.
          # Such an issue records a suppression marker and is closed by fathom's
          # own sweep once every bundle reports merged. Check every matching
          # record rather than the one selected below: in checklist mode the
          # marker lives in the plan document while the task file is preferred.
          # Read the list the same way everything above does, through
          # printf and a quoted read: an unquoted for loop word-splits and
          # glob-expands the path, so one record named with a space or a
          # bracket would silently fail the grep and close a stacked issue.
          SUPPRESSED=$(printf '%s\n' "$MATCHES" | while IFS= read -r RECORD; do
            [ -n "$RECORD" ] || continue
            if grep -qE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?[Mm]erge-closer(\*\*)?[[:space:]]*[:-][[:space:]]*(\*\*)?[Ss]uppressed' "$RECORD"; then
              printf '%s\n' "$RECORD"
              break
            fi
          done) || true
          if [ -n "$SUPPRESSED" ]; then
            echo "$SUPPRESSED records merge-closer: suppressed, so this issue is a stack that closes only once every bundle merges. Taking no action for $BRANCH."
            exit 0
          fi

          # Prefer the task file when both exist; it also carries the review id.
          # Anchor the prefix rather than matching /tasks/ anywhere: grep -r
          # descends into dot-directories, so a repo left holding a nested
          # .fathom/.workbench/tasks/ from a botched rename would otherwise sort
          # ahead of the live record and select the stale copy.
          # Every grep above that can legitimately match nothing ends in
          # || true. Actions' default shell is bash -e with pipefail OFF, but a
          # consumer who adds shell: bash or a defaults.run block gets pipefail,
          # and there a no-match grep would abort the job instead of taking the
          # skip path: a red check that closes nothing.
          FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/tasks/' | head -n 1 || true)
          [ -n "$FILE" ] || FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/plans/' | head -n 1 || true)
          [ -n "$FILE" ] || FILE=$(printf '%s\n' "$MATCHES" | head -n 1)
          # fathom:discovery-block end

          # Only a labeled line is trusted. Matching any uppercase-dash-digits
          # token anywhere would also match RFC-7231, ISO-8601, SHA-1 and the
          # like, which appear legitimately in a plan document.
          KEY=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?(tracker|issue|ref)(\*\*)?[[:space:]]*[:-]' "$FILE" \
            | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true)

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
