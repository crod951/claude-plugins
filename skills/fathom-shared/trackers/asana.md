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
| `listDestinations()` | Prefer the per-team path: resolve the viewer's teams with a teams-for-user style tool, then list projects per team, and return each project as its GID paired with its display name. Treat a workspace-wide project listing as a fallback only, because on at least one connected build it never returns. |
| `resolveDestination(hint?)` | Match a given hint against a project's name or GID to resolve its native GID. When no hint is given, resolve the tracker profile's configured default destination the same way. Return null when the hint matches more than one project ambiguously. |
| `createIssue(title, description, type, destination)` | Create the task with the resolved project GID, the title, and the description. Capture the created task's GID and its permalink URL from the tool response, and return both to the caller. |
| `createSubIssue(parentRef, title, description)` | Create the task with the parent's GID set as its parent; do not pass a project, since Asana inherits project membership from the parent task. Capture the created subtask's GID and its permalink URL from the tool response, and return both to the caller. |
| `updateState(ref, phase)` | Apply this only to the main task, never to a subtask. Look up the tracker profile's state mapping for the given phase, then follow this fallback chain in order: (a) if the connected MCP exposes a section-move or add-to-section tool, move the main task to the mapped section; (b) else if the profile maps a status custom field and a task-update tool can set that field, set the field to the mapped value; (c) else post a comment stating the phase transition, for example "Phase: In Review - <PR url>". When the phase is `done`, always set the task's completed flag to true regardless of which branch of the chain applied. Skipping the transition silently is not allowed; the fallback comment in step (c) is the minimum required action. The chain handles missing tools, not missing mappings: when the profile explicitly records this phase as unmapped, a decision first-run setup captured from the user, treat the transition as a documented no-op instead of running the chain, and still set the completed flag when the phase is `done`. Never hardcode a section or status name here; always go through the mapping saved during first-run setup. |
| `comment(ref, body)` | Post a story (comment) on the task using its GID and the comment body. |
| `listComments(ref)` | List the task's stories using a list-stories-style tool scoped to the task GID, and return each story's text, newest first. Asana calls comments "stories", and the same endpoint also returns system-generated stories for field changes and section moves, so filter to comment-type stories rather than treating every story as a comment. When the connected server exposes no story-listing tool, treat this operation as unavailable and report that; do not substitute a task fetch, since the task body does not contain its comments. |

The deprecated V1 server (mcp.asana.com/sse, shutdown 2026-11-05) lacks a section-move tool, so the V2 server (mcp.asana.com/v2/mcp) is recommended for full section-move support.

Two listing tools stalled rather than errored on one connected build: a workspace-wide project listing and a typeahead search each returned nothing for 300 seconds before being aborted, while listing projects per team returned instantly.
When a listing call stalls instead of failing, stop waiting on it, tell the user which call stalled, and use the per-team path instead.
Argument names differ across builds: some expect GID-suffixed names such as `user_gid` and `team_gid` rather than `user_id` and `team_id`, so treat an argument-validation error as a signal to retry with the other spelling rather than abandoning the tool.

Section-move fidelity depends on which Asana MCP the agent has connected.
A V2 server reached through the mcp-remote proxy exposed a section-move tool and really moved the task between board sections.
A different build exposed no section-move tool at all, so `updateState` correctly fell through to the phase comment.
Both outcomes are expected and already covered by the fallback chain; never treat the missing tool as an error.
A team that wants true section moves should connect a server that exposes one.

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

Asana has no review-merge integration comparable to Linear's GitHub integration.
At review open, move the main task to the mapped `inReview` state and post a comment stating that the task will be closed by the next skill run after the review merges.
When the resolved forge declares `reviewLookup: none`, no later run can detect the merge, so say instead that closing the task is a manual step; promising a sweep that cannot run would misstate what happens next.
The done-on-merge sweep itself, including its handling of reviews closed without merging, is tracker-agnostic and defined in `../trackers.md`; run it exactly as written there.
This adapter's closure action for the sweep's merged path: apply the mapped `done` state and set the task's completed flag.

## Closing on merge without any Fathom machinery

Everything in this section and the next assumes the resolved forge is GitHub.
Both arrangements below are GitHub-specific: one is a GitHub App, the other is a GitHub Actions workflow.
When the resolved forge is not GitHub, skip both regardless of what `ciHooks` declares, record `merge-closer: none (forge is not GitHub)`, and let the sweep be the sole closure mechanism; a non-GitHub forge with CI hooks still cannot run a GitHub App or reach these templates' assumptions.
When the resolved forge declares no `ciHooks`, skip both, record `merge-closer: none (forge has no hooks)`, and let the sweep be the sole closure mechanism, exactly as `../trackers.md` directs.

Asana ships a free native GitHub integration, a GitHub App, that links a pull request to a task when the PR body contains the task URL or the branch name contains the task id.
Paired with an Asana rule of the form "when a GitHub pull request is merged, mark the task complete", that combination closes the task server-side with no Action from this plugin, no sweep, and no agent involved.
It is the closest equivalent to Linear's native GitHub integration, and it is the recommended arrangement when the team can install the app and add the rule.

Prefer that arrangement when it is available.
Mention it before offering the merge-closer Action below, since it needs no workflow file and no repository secret, which matters in organizations that restrict either.
Record the choice in the tracker profile the same way, as `merge-closer: native` when the team relies on the Asana app and rule.
Treat `native` exactly like `installed` afterwards: never ask again, and let the sweep stay as a backstop that will find anything the integration misses.

## Merge closer (optional)

Run this check whenever the tracker profile is loaded or created for this repository, not only during first-run setup.
First-run setup triggers the same load-time check as part of creating the profile; it does not run a separate ask.
When the tracker is Asana, check the profile for a `merge-closer:` line.

Before asking anything, read the resolved forge's declared `ciHooks` capability.
When it is false, do not ask: record `merge-closer: none (forge has no hooks)` and stop here.
Asking anyway is worse than skipping, because a yes writes a workflow file that will never execute and records `installed`, which tells the sweep that something else owns closure when nothing does.

When that line is absent and the forge declares `ciHooks`, ask the user once whether to install the merge-closer GitHub Action for instant Asana closure on review merge, then record the answer in the profile right away.
Ask whenever no `merge-closer:` line is on record; once one is recorded, never ask again for this repository.
When the answer is yes, write `.github/workflows/fathom-close.yml` from the template below, record `merge-closer: installed` in the tracker profile, and commit both together.
Tell the user to add an `ASANA_TOKEN` repository secret, an Asana personal access token, since the workflow cannot post to the Asana API without it.
When the answer is no, record `merge-closer: declined` in the tracker profile.
The passive sweep and the on-demand cleanup trigger described in the execute skill keep working either way; this Action is an additive fast path, not a replacement.

Never asking again applies to the question, not to the file.
When the profile records `merge-closer: installed` and does not record a declined template rewrite, compare the repository's `.github/workflows/fathom-close.yml` against the template below on profile load, and when the file-discovery block differs, offer once to rewrite the file from the current template.
An installed workflow is a copy taken at install time, so a repository that accepted it before a template fix keeps running the old copy forever and never benefits from the fix.
State what differs and that the rewrite only replaces the workflow file.
On a yes, rewrite it and leave `merge-closer: installed` as it stands.
On a no, record `merge-closer: installed (template-rewrite declined)`, so the offer is not repeated on every later load, and treat that value exactly like `installed` everywhere else.
Recording the decline is what makes this a one-time offer rather than a prompt on every run, matching how every other question here is asked once and answered in the profile.
The curl call to the Asana API in the template below exists exclusively for this GitHub Action running in CI, authenticated with its own repository secret.
The agent must never run that curl call, or any other direct call to the Asana API, interactively.
The agent must never borrow the `ASANA_TOKEN` secret or any other token from disk to reach the Asana API itself; the connected Asana MCP is the only channel the agent uses at runtime.
The file-discovery and ref-extraction block in this template is intentionally identical to the one in `linear.md`'s template; a change to either copy must be applied to both.
Four differences are expected and not drift: the marker comment names the other file, the leading comment says task and wrong issue in one copy and issue and wrong one in the other, this copy names its selected file `TASK_FILE` where `linear.md` names it `FILE`, and the leading comment says task where the other says issue.

```yaml
name: fathom-close

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
          # Pass the branch through env, never into the script text: branch
          # names may contain shell metacharacters, which would run as code.
          BRANCH: ${{ github.event.pull_request.head.ref }}
        run: |
          if [ -z "$ASANA_TOKEN" ]; then
            echo "No ASANA_TOKEN secret set, skipping."
            exit 0
          fi

          # fathom:discovery-block start
          # Everything between these markers is shared verbatim with linear.md.
          # A branch must map to exactly one record; closing a task picked
          # arbitrarily from several matches could complete the wrong issue.
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
          TASK_FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/tasks/' | head -n 1 || true)
          [ -n "$TASK_FILE" ] || TASK_FILE=$(printf '%s\n' "$MATCHES" | grep '^\.fathom/plans/' | head -n 1 || true)
          [ -n "$TASK_FILE" ] || TASK_FILE=$(printf '%s\n' "$MATCHES" | head -n 1)
          # fathom:discovery-block end

          # Only a labeled line is trusted, so a URL sitting in prose cannot
          # make this close the wrong task. Matches "- Ref: <url>" and
          # "- **Issue** - <url>" style lines alike.
          TASK_URL=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?(tracker|issue|ref)(\*\*)?[[:space:]]*[:-]' "$TASK_FILE" \
            | grep -oE 'https://app\.asana\.com/[^ )>]+' | head -n 1 || true)

          if [ -z "$TASK_URL" ]; then
            echo "No labeled Tracker, Issue, or Ref line carrying an Asana URL in $TASK_FILE, skipping."
            exit 0
          fi

          # Anchor on the task segment: copy-link and focus URLs end in /f or
          # ?focus=true, so matching trailing digits alone finds nothing.
          TASK_GID=$(printf '%s' "$TASK_URL" | sed -nE 's#.*/task/([0-9]+).*#\1#p')
          if [ -z "$TASK_GID" ]; then
            TASK_GID=$(printf '%s' "$TASK_URL" | sed -nE 's#.*/([0-9]+)/?(f/?)?(\?.*)?$#\1#p')
          fi

          if [ -z "$TASK_GID" ]; then
            echo "Could not extract a task GID from $TASK_URL, skipping."
            exit 0
          fi

          # -f so an auth or not-found error fails the job, instead of the job
          # going green while the task stays open.
          curl -sf -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
            -H "Authorization: Bearer $ASANA_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"data":{"completed":true}}' \
            || { echo "Asana API call failed for GID $TASK_GID"; exit 1; }
```

The Action closes the task by setting the completed flag directly through the Asana API.
Section moves at other phases still follow the `updateState` fallback chain described above; this Action only ever sets completed on merge, it never moves sections.

## Setup instructions

Use the workspace-list or current-user tool as the preflight verification call for Asana.
A successful, error-free response from that call is what confirms the MCP is connected and usable; anything else, including no matching tool being available, counts as unverified.

The V1 server (`https://mcp.asana.com/sse`) is deprecated, with shutdown scheduled for 2026-11-05.
Point new setups at the V2 server, `https://mcp.asana.com/v2/mcp`.
V2 requires an app registered at `app.asana.com/0/my-apps`, which provides a client id and a client secret.

For Claude Code, run:

```bash
claude mcp add --transport http --client-id YOUR_CLIENT_ID --client-secret --callback-port 8080 asana https://mcp.asana.com/v2/mcp
```

Register the redirect URL `http://localhost:8080/callback` in the Asana app before running this command.

For Kiro, add an entry to `~/.kiro/settings/mcp.json` (user level) or `.kiro/settings/mcp.json` (workspace level) that runs the `mcp-remote` proxy:

```json
{
  "mcpServers": {
    "asana": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "https://mcp.asana.com/v2/mcp",
        "3334",
        "--static-oauth-client-info",
        "{\"client_id\":\"YOUR_CLIENT_ID\",\"client_secret\":\"YOUR_CLIENT_SECRET\"}"
      ]
    }
  }
}
```

Register the redirect URL `http://localhost:3334/oauth/callback` in the Asana app before running this command.
Note that `mcp-remote` is community software, not an official Asana or Anthropic package.

Either way, tell the user to check for a `disabled` flag on an existing entry before assuming the server needs to be added from scratch; a disabled server presents to preflight the same as a missing one.
