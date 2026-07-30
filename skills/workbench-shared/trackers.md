# Tracker adapters

Call the tracker only through the contract below.
Resolve the correct adapter at runtime, before doing any tracker work.
Never call tracker tools directly from a core skill body; always go through the operations named here.

## The contract

Use exactly these eight operations.
Adapter files implement each one against a specific tracker's tools; treat the operation names as the vocabulary for every other skill and adapter in this plugin.

| Operation | Purpose |
| --- | --- |
| `getIssue(ref)` | Fetch one issue's title, description, type/labels, URL, native id, current state, and existing children. |
| `listSubIssues(ref)` | List an issue's existing child issues, each with id, title, and state; use this when adopting an issue that may already have children. |
| `listDestinations()` | List where a new top-level issue can be created (Asana projects, Linear teams), each as a stable destination value paired with a display name. |
| `resolveDestination(hint?)` | Turn a caller-supplied hint, or the tracker profile's configured default when no hint is given, into one destination value; return null when the result is ambiguous. |
| `createIssue(title, description, type, destination)` | Create a new top-level issue in the given destination; return its ref and URL. |

The destination value is adapter-owned and opaque to the skills: they only pass it between these three operations and store it in the profile, never inspect it.
It may bundle more than one native id when the tracker needs that; Linear's carries the team UUID plus an optional project id, while Asana's is a single project GID.
| `createSubIssue(parentRef, title, description)` | Create a new child issue under an existing parent; return its ref and URL. Do not attempt to record the paired task id during this call; the task does not exist yet. The execute skill writes it back after `createTask` returns, using `comment` so no additional contract operation is needed. |
| `updateState(ref, phase)` | Move an issue to the given phase, where phase is one of `inProgress`, `inReview`, or `done`; apply it through the tracker profile's state mapping rather than a hardcoded status name. |
| `comment(ref, body)` | Post a comment on an issue. |

### Destination resolution

Resolve a destination for a new top-level issue from only two sources: the caller-supplied hint for this invocation, or the tracker profile's configured default when no hint is given.
When neither a hint nor a profile default exists, the agent must call `listDestinations`, list the destinations to the user, and ask once which one to use.
Do not substitute any other source of truth for that question.
In particular, never infer a destination from tracker URLs found inside existing `.workbench/tasks/*.md` files, from prior issues in the repository, or from any other guess; a wrong inference silently files work in the wrong place, and even a right one takes the choice away from a user who may have several valid destinations.
The agent may inspect existing task files or prior issues to offer a suggested default inside that same question, for example "previous issues in this repo used X, use that again?".
Offering a suggestion does not replace asking; still ask the question and wait for the user's answer before creating anything.
One exception, defined in `approval.md`: in auto mode, when `listDestinations` returns exactly one destination the answer is determinate, so record it and report it instead of asking.
Any other number of destinations is ambiguous and is asked even in auto mode.

## Base branch resolution

Feature branches start from, and pull requests target, one base branch.
Resolve it in this order, first match winning.

Use the base branch named in the invocation when the request specifies one, and treat that as applying to this run only.
Otherwise use the profile's `base-branch` when it records one.
Otherwise use the repository's current branch, and say which branch you resolved so the choice is visible.

Guard against one trap: when the current branch is itself a workbench feature branch, meaning its name carries an issue ref and one of the branch prefixes, do not silently use it as a base.
Building one issue's work on top of another's unmerged branch entangles two pull requests, so ask which base to use instead.

Fetch the resolved base branch before creating anything from it, and create the new branch from the fetched remote copy rather than from a local copy that may be behind.

## Preflight verification

Run this before any other tracker operation, on every invocation.
Do not skip it because a previous run in this session already verified the MCP; verify again each time.

Infer the intended tracker first, one precedence for every skill.
When the invocation names a tracker explicitly, that wins over everything else; profile inference must never override what the user just said.
Otherwise, when a reference already exists in the invocation, a pasted URL, or the current branch name, infer the tracker from the reference shape: a Linear key like `ABC-123`, or an Asana URL or GID.
Otherwise infer it from the tracker profile's `tracker` field, then from which tracker MCPs are connected.
This is the same precedence the skills use to resolve the tracker for the run, so preflight and the run always verify and work against the same tracker.

Verify the inferred tracker's MCP with one cheap read-only call, the current-user or workspace-list operation that tracker's adapter file names.
Treat any failure, any absence of the expected tools, or a disabled server the same way: unverified.

When verification fails, do not start tracker work and do not attempt any workaround.
Instead, output the setup instructions from that tracker's adapter file, tell the user to connect the MCP and re-invoke the skill, then stop.
When the MCP is unverified, delivering setup instructions is the task; that is a genuinely helpful, complete action, not a fallback, and it is what keeps this procedure from improvising a bypass.

The GitHub CLI is part of the same preflight.
Verify it with one cheap read-only call, `gh auth status`, and treat a missing binary and an unauthenticated one the same way: unverified.
Run this check in the same pass as the MCP check rather than after a failed stop, so a user missing both dependencies gets one stop naming everything to fix instead of discovering one failure per invocation.

When `gh` does not verify, do not start the run and do not attempt any workaround: never call the GitHub HTTP API directly, and never read tokens from disk or the environment.
Output the fix instead: install the CLI with `brew install gh` on macOS or the platform package listed at https://github.com/cli/cli#installation, authenticate with `gh auth login`, then re-invoke the skill.
As with an unverified MCP, delivering these instructions is the task, not a fallback.

On re-invocation, run preflight again from the top.
Only a verified MCP and a verified `gh` allow the run to begin.

## Done-on-merge sweep

Every skill invocation in a repo must run this sweep before doing any other tracker work, and only once preflight has verified the MCP.
The sweep is tracker-agnostic: it finds issues from repository state, and only its closure action goes through the resolved tracker's adapter.

The sweep checks whether any file under `.workbench/` references an issue whose pull request has since merged, using `gh pr view <branch> --json state,mergedAt` for each recorded branch; when several issues are outstanding, one `gh pr list --state all --json headRefName,state,mergedAt` call matched locally against the recorded branch names is cheaper than one call per issue; pass `--limit` with a value comfortably above the repository's total pull request count, since the default caps at 30 and a capped listing would silently skip older recorded branches.
Search the whole directory rather than only `tasks/`: depending on the resolved memory backend the per-issue record may be a plan document under `plans/` with no checklist file at all, and narrowing the search to `tasks/` silently skips those issues.
When the sweep finds a merged pull request for an issue, read the issue's current state before writing to the tracker.
When the issue is already complete, for example because a merge-closer Action or a native integration already closed it, skip the tracker write and apply only the stamp described below.
Otherwise apply the mapped `done` state through `updateState`, plus any closure action the adapter defines for the merged path, before proceeding with the rest of the run.

For idempotency, append a `- Closed: <date>` line to that issue's file under `.workbench/`, whichever file the search found, since a beads-mode issue has a plan document and no checklist file, commit the file, and push that commit to the branch the merged pull request targeted, which is the resolved base branch and is not necessarily the repository's default branch once `base-branch` is configured.
A stamp commit that is only made locally does not propagate: it never reaches the base branch, so the merge check runs at most once per issue only when the commit is pushed to that base branch.
When the current checkout is on a feature branch, the stamp still must land on that base branch, not on a feature branch.
Do not switch branches to place it while the run has uncommitted task state in the working tree, since a checkout or a stash can lose the in-progress marker that the memory contract treats as the truth.
Apply the stamp before any task work begins, or from a separate clone or worktree, or defer it to the next invocation and say plainly that the stamp is pending.
When the push fails, for example because of missing permission, a protected branch, or being offline, report the failure to the user and continue the run.
A failed stamp push must not abort the sweep, and it must not be retried silently in a loop.
The sweep skips any issue whose `.workbench/` file already carries a Closed line, so the merge check runs at most once per issue.

### Pull requests closed without merging

A merged pull request is not the only way a pull request ends, and the other way is silent by default.
A merge-closer Action or native integration deliberately ignores a pull request that was closed without merging, since the work was not delivered, and the merged path above also ignores it because `mergedAt` is null.
That combination leaves the issue parked in the `inReview` phase forever while the branch is abandoned, so the tracker misstates reality and nobody is told.

During the sweep, treat a referenced pull request whose state is closed with a null `mergedAt` as an abandoned attempt, and handle it as follows.
Never mark the issue done, because nothing shipped.
Never silently move the phase back either, because whether to retry, rescope, or drop the work is the user's decision, not an inference from a closed pull request.
Report it instead: name the issue, name the pull request, say it was closed without merging, and ask whether to resume the work on a fresh branch or move the issue back to the `inProgress` phase.

Record the observation in that issue's file under `.workbench/` as a line such as `- PR closed unmerged: <date> <pr url>` so the same abandoned pull request is reported once rather than on every later run.
Commit that recorded line and push it before the sweep returns, under the same branch-placement and uncommitted-state cautions as the Closed stamp above: a marker that exists only in a working tree, or only in a local commit, does not survive to other clones or later runs, and the same abandoned pull request would be re-reported every time.
When the push fails, report the failure and continue, exactly as a failed stamp push is handled, and expect the pull request to be reported again until a push succeeds; that repetition is the honest outcome of unpersisted state, not a bug to suppress.
Report it again when a different pull request for the same issue is later closed unmerged, since that is new information.
A recorded abandonment does not close the issue and does not stop a later merge from closing it normally; when a fresh pull request for the same issue merges, apply the usual done state and Closed stamp.

## Runtime resolution

Follow this procedure to decide which tracker owns a given reference, and to fail safely when that cannot be determined.

Treat a reference shaped like `ABC-123` (a short uppercase prefix, a dash, and digits) as Linear.
Treat an Asana URL or a bare numeric GID as Asana.
When the reference's shape does not clearly indicate a tracker, check which tracker MCP is connected.
When exactly one tracker MCP is connected, use that tracker.
When both tracker MCPs are connected and the reference is still ambiguous, ask the user once which tracker they mean; do not guess.
When the reference is ambiguous and neither tracker MCP is connected, stop immediately and report a clear message naming both supported trackers, Asana and Linear, and telling the user to connect one before retrying.
Never guess a tracker for an ambiguous reference when no tracker MCP is connected, and never proceed as if one were resolved.
Once a tracker is chosen, discover that connected MCP's actual tool names at runtime rather than assuming fixed names.
Adapter files list the typical tool names for each tracker, but real builds vary, so treat those names as a starting hint, not a guarantee.
When the resolved tracker's MCP is not connected, stop immediately and report a clear message naming the specific missing MCP.
Never fall back to the other tracker when the resolved tracker's MCP is unavailable; a Linear reference must never be silently handled by Asana, and vice versa.
Never search the filesystem, environment variables, config files, or token caches for tracker credentials, whether the MCP is connected or not.
Never call the tracker's HTTP API directly, with a scavenged credential or any other credential.
Never modify the agent's or the user's MCP configuration to enable, add, or reconfigure a tracker server.
A disabled or missing tracker server is the user's decision, and only the user changes it.
The connected tracker MCP is the only permitted channel for tracker operations at runtime; when it is not connected, there is no other channel, so stop.

## First-run tracker profile

Run this setup procedure once per repository, then reuse its output on every later run.

Trigger setup when the repository has no `.workbench/config.md`.
Before prompting the user, check other local branches for a newer `.workbench/config.md` and offer to reuse it instead of starting over.

When no existing profile is found anywhere, the agent must run these five steps in order and must not skip any of them.
Each step must get the user's answer before the next step starts, and the profile must not be written until every step has an answer.
Ask one question at a time; never present a later step's question, or any other pending question such as the issue draft, alongside an unanswered step from this sequence.
Prefer the agent's structured question mechanism named in `agents.md` over free prose for each of these questions, since a list of concrete choices is harder to answer ambiguously.
When a user's reply could answer more than one pending question, or its target is unclear, stop and ask which question it answered; never guess, and never treat an ambiguous or negative reply as approval to create anything.

1. Confirm the destination.
   Call `listDestinations`, list the available destinations to the user, and let them pick the one to save as the profile's default.
2. Confirm the three-phase state mapping.
   Inspect what the connected tracker actually offers: for Linear, list the team's workflow states; for Asana, list the project's board sections and any status custom fields.
   Propose a mapping from those tracker-specific states to the three phases (`inProgress`, `inReview`, `done`).
   Show the proposed mapping to the user and let them confirm it or correct it.

   A tracker may have no state for a phase at all, which is common for `inReview`: a default Linear team ships without a review state, and an Asana project may have no matching section.
   Do not silently pick the nearest state, and do not fabricate one.
   Say which phase has nothing to map to, then offer the real choices: the user adds a state in the tracker and you re-read the states afterwards, or the phase maps onto another state with the loss of distinction stated plainly, or the phase stays unmapped so the skill skips that transition entirely.
   Record an unmapped phase in the profile as `unmapped` rather than omitting the line, so a later run knows the phase was considered and skipped rather than forgotten.
   Creating tracker states is the user's job; no adapter operation defines a workflow state, so never claim to have added one.
3. Run the resolved tracker adapter's profile-load offers.
   Each adapter defines its own; for Asana and for Linear alike this is the merge-closer question described in that tracker's adapter file, since both need to know what closes an issue when a pull request merges.
   Ask it and record the answer in the profile as `merge-closer`.
   Run this check whenever the profile is loaded, not only during first-run setup, so a profile written before this question existed gets repaired rather than staying silent.
4. Confirm the base branch that feature branches should start from and merge into.
   Offer the repository's current branch as the default, since that is usually the integration branch the user is working from, and offer the repository's default branch as the alternative.
   Do not offer the current branch when it is itself a workbench feature branch, meaning its name carries an issue ref and one of the branch prefixes.
   Recording that as the profile's base would make every future issue in the repository, and every teammate who clones it, branch from and target one issue's unmerged work, and the resolution-time guard would never fire because the profile now holds an explicit answer.
   Offer the default branch in that case, and say why the current branch was excluded.
   Record the answer as `base-branch` in the profile.
5. Confirm the approval mode.
   Ask whether future runs should stop for approval at the usual points, or run straight through without asking.
   Record the answer as `approval: ask` or `approval: auto` per `approval.md`, and say that the safety stops listed there fire either way, so choosing auto does not mean unattended risk.

Save the confirmed profile to `.workbench/config.md` and commit that file only once all five steps above have an answer; include the confirmed default destination.
Never announce that setup will happen and then write a profile without having asked each of these questions.
A profile written without confirmed answers for every step is a defect, not a shortcut.
A per-invocation destination hint applies only to that invocation; change the profile's `default-destination` only when it is absent or when the user explicitly asks to change it.

Use this format for the profile:

```markdown
# workbench tracker profile
tracker: asana
default-destination: Prototypes (1209000000000001)  # add "# auto-accepted" when auto mode chose it
base-branch: main
approval: ask
state-mapping:
  inProgress: section "In Progress"
  inReview: section "Review"
  done: section "Done" + completed
```

On every subsequent run, read the existing profile silently and use it without re-prompting.
Re-run setup when a mapped state no longer exists in the tracker, or when the user explicitly asks to redo it.
Re-run setup to resolve merge conflicts in `.workbench/config.md`; do not attempt to hand-merge the conflicting mapping.
