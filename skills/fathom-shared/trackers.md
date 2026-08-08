# Tracker adapters

Call the tracker only through the contract below.
Resolve the correct adapter at runtime, before doing any tracker work.
Never call tracker tools directly from a core skill body; always go through the operations named here.

## The contract

Use exactly these nine operations.
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
| `listComments(ref)` | List an issue's existing comments, newest first, returning at least each comment's body text. This exists so the sweep can read markers this plugin wrote on an earlier run; it is not for summarizing discussion. When the connected MCP exposes no comment-listing tool, treat the operation as unavailable and follow the fallback the sweep section defines rather than guessing. |

### Destination resolution

Resolve a destination for a new top-level issue from only two sources: the caller-supplied hint for this invocation, or the tracker profile's configured default when no hint is given.
When neither a hint nor a profile default exists, the agent must call `listDestinations`, list the destinations to the user, and ask once which one to use.
Do not substitute any other source of truth for that question.
In particular, never infer a destination from tracker URLs found inside existing `.fathom/tasks/*.md` files, from prior issues in the repository, or from any other guess; a wrong inference silently files work in the wrong place, and even a right one takes the choice away from a user who may have several valid destinations.
The agent may inspect existing task files or prior issues to offer a suggested default inside that same question, for example "previous issues in this repo used X, use that again?".
Offering a suggestion does not replace asking; still ask the question and wait for the user's answer before creating anything.
One exception, defined in `approval.md`: in auto mode, when `listDestinations` returns exactly one destination the answer is determinate, so record it and report it instead of asking.
Any other number of destinations is ambiguous and is asked even in auto mode.

## Base branch resolution

Base branch resolution lives in `forges.md`, not here.
It is a forge concern: it decides what a review targets and what a feature branch is cut from, and nothing about it varies by tracker.

The profile's `base-branch` field is still written and read by the first-run setup below, since the profile is one file; only the resolution rules moved.

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

The forge is part of the same preflight.
Resolve the forge adapter as `forges.md` directs, then call its `verifyForge` operation, and read that adapter's declared capabilities for the rest of the run.
Run this check in the same pass as the MCP check rather than after a failed stop, so a user missing both dependencies gets one report naming everything to fix instead of discovering one failure per invocation.

An unverified forge does not stop the run.
Unlike the tracker, which has no substitute, the forge has a documented degraded path: an unverified or unresolvable forge selects a capability tier per `forges.md`, and the run continues in that tier.
A resolved adapter that fails `verifyForge` selects the manual tier for that run, per the failed-verification rule in `forges.md`; no further calls go through the failed adapter.
State the resolved tier before doing any work, along with the fix for reaching a higher one, so the user knows what this run will and will not do.

What an unverified forge must never do is provoke a workaround.
Never call a forge's HTTP API directly, never read tokens from disk or the environment, and never install or authenticate a forge CLI on the user's behalf.
Those prohibitions hold in every tier; the tier decides what the run attempts, never how it authenticates.

On re-invocation, run preflight again from the top.
A verified tracker MCP is what allows the run to begin; the forge decides in which tier it begins.

## Done-on-merge sweep

Every skill invocation in a repo must run this sweep before doing any other tracker work, and only once preflight has verified the MCP.
The sweep is tracker-agnostic: it finds issues from repository state, and only its closure action goes through the resolved tracker's adapter.

The sweep runs only when the resolved forge declares `reviewLookup: by-id`.
When it declares `none`, there is no way to observe what happened to a review, so skip the sweep and say once that it was skipped and why; never report a clean sweep that did not run.

Find the outstanding issues by searching `.fathom/` for recorded reviews.
Search the whole directory rather than only `tasks/`: depending on the resolved memory backend the per-issue record may be a plan document under `plans/` with no checklist file at all, and narrowing the search to `tasks/` silently skips those issues.

For each issue the search finds, read every review id recorded for it and call `getReviewState` on each one before deciding anything about that issue.
A single-review issue records one id; an issue split into a stack records one per bundle, in the plan document's `Bundles` section described in `conventions.md`.
Read the records rather than assuming a count: acting on the first id found would decide a stacked issue's fate from one bundle's result while the rest of its work was still open, which is the early close the `Merge-closer: suppressed` marker exists to prevent.
A stack's records are spread across its bundle branches rather than gathered in one place.
Each bundle's `- Review:` line is committed on that bundle's own branch as that bundle's review publishes, so a checkout of the base branch carries the records of the bundles that have merged into it and none of the records above them.
Collect the missing ones before judging anything: read the branch names from the plan document's `Bundles` section, fetch each of those branches, and read each fetched branch's own copy of the plan document for that bundle's `- Review:` line.
A bundle branch is created from the branch below it, so the highest one that still exists carries every record beneath it, and fetching all of them costs nothing beyond that.
Prefer this to mirroring the ids into a store the base branch can read directly, such as a tracker comment or a second file: fetching is read-only git work that needs no write anywhere and cannot drift, whereas a second record of the same fact is a second thing that can disagree with the plan document.
When a bundle's branch is absent from the remote and its record is not on the current branch either, that bundle simply has no record, and case 2 below decides what happens then.

An issue none of whose bundles have merged has no record on the base branch at all, since the plan document itself is committed on bundle 1's branch, so from a base checkout that issue is not found by the search above.
That is exactly how an unmerged single-review issue behaves, and it is correct: nothing has merged, so there is nothing to close.

Look each id up directly; never list a forge's reviews and match them locally.
A listing has to be bounded, and any bound silently drops the oldest records once a repository has more reviews than the bound allows, which is a defect that grows quietly with the repository's age.

Records written before review ids were recorded carry a branch name and no id.
For those, fall back to the optional `findReviewByBranch` operation defined in `forges.md`, which returns bounded candidate records carrying each review's id, its URL, and its base.
Treat such a record as resolved only when exactly one candidate comes back, since a legacy record names a branch and nothing else and so carries nothing to tell two candidates apart; two or more candidates leave it unresolved rather than presenting a choice to make.

Resolution is not complete at the id.
Add the resolved id to that issue's set of review ids and call `getReviewState` on it, and do both before any of the ordered cases below are evaluated for that issue, so every case judges the issue on its whole set rather than on the subset that already carried ids.
Doing this after the cases, or not at all, would let the completeness requirement and the aggregate cases run against an incomplete set: an issue whose only unresolved record is the branch-only one would read as fully recorded, and case 3 would close it on the strength of the reviews that happened to have ids.
Then rewrite the record with the id, so the fallback path drains over time rather than becoming permanent.

When resolution fails, and when the resolved adapter does not implement that operation at all, that record yields no id and no state: report that once, naming the record, rather than guessing or treating a branch name as a review id.
Leave the issue incomplete in that case, exactly as a missing `- Review:` record leaves it, so case 2 below blocks closure on it instead of the aggregate cases deciding the issue on partial data.

Judge each issue on all of its results together, in the order below, letting the first case that applies decide that issue.
An issue can satisfy more than one case at once, and a stack holding a merged bundle, an open bundle, and an abandoned one routinely does.

1. Any recorded review reports `closed-unmerged`.
   Apply the closed-without-merging path below for that review, and, when the issue is a stack, name which bundles above it are now orphaned by it.
   Close nothing for that issue, and do not read its merged reviews as progress toward closure.
   This case is checked first and is terminal, however many of the issue's other reviews merged or stayed open, because whether to retry, rescope, or drop the orphaned work is the user's decision and nothing should be built on top of work that may be about to be discarded.
2. Any recorded review reports `unknown`, or some bundle between 1 and N has no `- Review:` record at all, or a branch-only record could not be resolved to a review id, and none reported `closed-unmerged`.
   `getReviewState` returns `unknown` when it could not determine the review's fate, which is not a state the review is in but an answer the sweep did not get.
   A missing record is the same kind of gap: the `Bundles` section says how many bundles the issue has, so N is known even when a record is not, and an issue judged on fewer records than N is judged on an incomplete set.
   An unresolved branch-only record is that same gap in a third shape: the record is there, but nothing behind it can be looked up, so the review it stands for is exactly as unobserved as one whose record is missing.
   With N of 3 and only two records collected, the cases below would read a partly recorded three-bundle stack as a complete two-bundle one, and case 3 would then close a half-merged issue.
   So require a record for every bundle from 1 to N, and a `getReviewState` result for every one of those records, before evaluating cases 3, 4, and 5 at all, and take this case whenever that requirement is unmet.
   Change nothing about the issue: close nothing, report nothing about its progress, and leave it exactly as it stands for a later sweep to decide.
   Name the review ids that came back `unknown`, the bundles whose records are missing, and the branch-only records that could not be resolved, and say that this issue was left undecided because of them.
   Never fold an `unknown` result, a missing record, or an unresolved branch-only record into `merged`, `open`, or "still entirely in review": each of those is a specific claim about work the sweep cannot actually see, and the later cases would otherwise absorb it and make that claim anyway.
   This case sits below case 1 because a `closed-unmerged` result is a fact the sweep did observe, and its outcome does not depend on the undetermined or unrecorded ones: it closes nothing, restacks nothing, and hands the decision to the user, which is already the safest thing an incomplete picture could ask for.
   It sits above every case below because those judge the issue on all of its results at once, and neither an undetermined result nor a missing one can carry its share of such a judgment.
3. Every recorded review reports `merged`.
   Apply the merged path below.
   For a single-review issue that is its one review, and for a stack it is every bundle, which is what keeps a stack from being closed by its first merge.
4. Some reviews merged and others still open.
   Close nothing, and report the partial progress, naming which bundles merged.
5. None merged and none closed without merging.
   The work is still entirely in review, so close nothing and say so plainly rather than reporting nothing at all.
   Every result reaching this case is `open`, since an `unknown` one was already decided by case 2.

Cases 2, 4, and 5 leave the issue's phase exactly where it is.
The branches a partially merged stack leaves behind may still need restacking, but that is git and forge work rather than tracker work, so it belongs to the skill running the sweep; this section decides only what is written to the tracker.

On the merged path, read the issue's current state before writing to the tracker.
When the issue is already complete, for example because a merge-closer Action or a native integration already closed it, do nothing further for that issue.
Otherwise apply the mapped `done` state through `updateState`, plus any closure action the adapter defines for the merged path, before proceeding with the rest of the run.
An issue whose record carries `- Merge-closer: suppressed`, which is how a stacked issue is recorded per `conventions.md`, was deliberately left for this sweep to close: the Action takes no action for it, so the sweep is its only closure mechanism and reaching `done` requires a run of this sweep.
The state read above still applies to it unchanged, since a user may have closed such an issue by hand.

That state read is the whole idempotency mechanism for the merged path.
An issue that is already `done` produces no write on any later run, so nothing needs to be recorded anywhere and nothing needs to be pushed.
Do not write a stamp, a marker, or any other file to record a merge.

### Reviews closed without merging

A merged review is not the only way a review ends, and the other way is silent by default.
A merge-closer Action or native integration deliberately ignores a review that was closed without merging, since the work was not delivered, and the merged path above ignores it too.
That combination leaves the issue parked in the `inReview` phase forever while the branch is abandoned, so the tracker misstates reality and nobody is told.

During the sweep, treat a `closed-unmerged` result as an abandoned attempt, and handle it as follows.
Never mark the issue done, because nothing shipped.
Never silently move the phase back either, because whether to retry, rescope, or drop the work is the user's decision, not an inference from a closed review.
Report it instead: name the issue, name the review, say it was closed without merging, and ask whether to resume the work on a fresh branch or move the issue back to the `inProgress` phase.

Unlike the merged path, this one has no tracker state to key on: the issue sits in `inReview` whether or not it has already been reported, so without a marker the same dead review is reported on every later run.
Record the observation as a comment on the issue through `comment`, carrying a sentinel line such as:

```
fathom: review-closed-unmerged <review url> <date>
```

Before reporting, call `listComments` and skip any issue whose comments already contain the sentinel for that review.
Match the sentinel as a substring anywhere in the comment stream, not by inspecting only the newest comment; users reply in comment threads, and a later reply must not hide the marker.
Treat the legacy sentinel `workbench: review-closed-unmerged` as valid for the same purpose when matching, since sentinels written before the rename live on the tracker rather than in the repository and no file rename reaches them; only ever write the current one.

The tracker holds this marker rather than a file for one reason: the marker has to survive to other clones and later runs, and a file-based marker only does that when it is pushed to the base branch.
Most shared repositories protect that branch, so the push fails, the marker never lands, and the report repeats forever as a stop that fires in both approval modes.
A comment needs no branch write access and is visible from every clone.

When the resolved tracker cannot list comments, fall back to recording `- Review closed unmerged: <date> <review url>` in that issue's file under `.fathom/`, committed and pushed to the base branch.
Say plainly, when taking that fallback, that the marker depends on write access to the base branch and that the review will be re-reported on every run if the push fails.
Keep reading legacy `- PR closed unmerged:` lines as valid markers, so records written before this change are not re-reported.

Report it again when a different review for the same issue is later closed unmerged, since that is new information.
A recorded abandonment does not close the issue and does not stop a later merge from closing it normally; when a fresh review for the same issue merges, apply the usual done state.

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

Trigger setup when the repository has no `.fathom/config.md`.
Before prompting the user, check other local branches for a newer `.fathom/config.md` and offer to reuse it instead of starting over.

When no existing profile is found anywhere, the agent must run these six steps in order and must not skip any of them.
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
3. Confirm the forge.
   Ask which forge hosts this repository's reviews, following the first-run forge question in `forges.md`, and record the answer as `forge` in the profile.
   Seed the question from the `origin` remote's host and then from a `PATH` probe, but never let detection answer it by itself.
   Ask this before the next step, since what the next step may offer depends on the resolved forge's declared capabilities.
   Run this check whenever the profile is loaded, not only during first-run setup, so a profile written before this question existed gets repaired rather than staying silent.
4. Run the resolved tracker adapter's profile-load offers.
   Each adapter defines its own; for Asana and for Linear alike this is the merge-closer question described in that tracker's adapter file, since both need to know what closes an issue when a review merges.
   Ask it only when the resolved forge declares `ciHooks` and the closure arrangements that adapter file offers actually apply to the resolved forge; both trackers' native integrations and Action templates are GitHub-specific, so on any other forge offer only what that adapter documents as working there, and record `merge-closer: none` naming the reason when nothing does.
   When the forge declares no CI hooks there is nothing to install, so skip the question entirely and record `merge-closer: none (forge has no hooks)`.
   Asking it anyway would be worse than skipping it: accepting the offer writes a workflow file that never executes and records `installed`, which tells the sweep that something else owns closure when nothing does.
   Otherwise ask it and record the answer in the profile as `merge-closer`.
   Run this check whenever the profile is loaded, not only during first-run setup, so a profile written before this question existed gets repaired rather than staying silent.
5. Confirm the base branch that feature branches should start from and merge into.
   Offer the repository's current branch as the default, since that is usually the integration branch the user is working from, and offer the repository's default branch as the alternative.
   Do not offer the current branch when it is itself a Fathom feature branch, meaning its name carries an issue ref and one of the branch prefixes.
   Recording that as the profile's base would make every future issue in the repository, and every teammate who clones it, branch from and target one issue's unmerged work, and the resolution-time guard would never fire because the profile now holds an explicit answer.
   Offer the default branch in that case, and say why the current branch was excluded.
   Record the answer as `base-branch` in the profile.
6. Confirm the approval mode.
   Ask whether future runs should stop for approval at the usual points, or run straight through without asking.
   Record the answer as `approval: ask` or `approval: auto` per `approval.md`, and say that the safety stops listed there fire either way, so choosing auto does not mean unattended risk.

Save the confirmed profile to `.fathom/config.md` and commit that file only once all six steps above have an answer; include the confirmed default destination.
Never announce that setup will happen and then write a profile without having asked each of these questions.
A profile written without confirmed answers for every step is a defect, not a shortcut.
A per-invocation destination hint applies only to that invocation; change the profile's `default-destination` only when it is absent or when the user explicitly asks to change it.

Use this format for the profile:

```markdown
# fathom tracker profile
tracker: asana
forge: github          # a bundled adapter name, "local" for .fathom/forge.md, or "none"
default-destination: Prototypes (1209000000000001)  # add "# auto-accepted" when auto mode chose it
base-branch: main
approval: ask
stacking: propose      # write this to let the repository split an issue into a stack; "never" or absent keeps it on one review per issue
merge-closer: native   # "none (forge has no hooks)" when the forge declares no ciHooks
state-mapping:
  inProgress: section "In Progress"
  inReview: section "Review"
  done: section "Done" + completed
```

The `stacking` line is optional and is not one of the six setup questions above, so first-run setup neither asks for it nor writes it.
Write it only when the user asks for a repository-wide answer, and treat its absence as `never` exactly as `approval.md` states.
Leaving it out of setup therefore means a freshly set up repository produces one review per issue and never proposes a split, which is the opt-in behavior stacking is meant to have; a repository that wants stacking adds the line itself.

On every subsequent run, read the existing profile silently and use it without re-prompting.
Re-run setup when a mapped state no longer exists in the tracker, or when the user explicitly asks to redo it.
Re-run setup to resolve merge conflicts in `.fathom/config.md`; do not attempt to hand-merge the conflicting mapping.
