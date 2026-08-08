# Forge adapters

Call the forge only through the contract below.
Resolve the correct adapter at runtime, before doing any forge work.
Never call forge tools directly from a core skill body; always go through the operations named here.
The forge is where reviews live: the system that hosts the remote, receives the branch, and holds the code review. It is not the tracker, and the two are resolved independently.

## The contract

Use exactly these five operations.
Adapter files implement each one against a specific forge's tools; treat the operation names as the vocabulary for every other skill and adapter in this plugin.

| Operation | Purpose |
| --- | --- |
| `verifyForge()` | Cheap read-only preflight check that the forge is reachable and authenticated; returns verified or unverified and nothing else. |
| `resolveBase(branch)` | Confirm the named base branch exists on the remote and is a valid merge target. |
| `openReview(branch, base, title, body, dependsOn?)` | Create the review for a branch against a base. Return a stable review id and the review's URL - or, on a forge where no review can be created, the manual-handoff result defined below. `dependsOn` is optional and carries the review id this one is stacked on; it is absent for a standalone review and for the first bundle of a stack. |
| `publishReview(id)` | Move a draft review to the notified-review state, where the forge distinguishes the two. A no-op everywhere else. |
| `getReviewState(id)` | Return one of `open`, `merged`, `closed-unmerged`, or `unknown`, plus a merge timestamp when merged. |

Which side performs the push that opens the review is decided by `pushesForYou`, and by nothing else.
When it is true, `openReview` owns that push and the caller must never perform it: some forges' review CLIs push the review ref themselves, and running `git push` alongside them produces a wrong branch state.
When it is false, the caller pushes the branch before calling `openReview`, which is what both bundled adapters declare and what `execute` does.
Stating this unconditionally in either direction is what makes an agent either skip the push or perform it twice.

That ownership is scoped to `openReview` and does not extend to the whole branch.
Commits the caller makes after the review is open, including the final closing commit that carries completed task state, are the caller's to push, on every adapter and whatever `pushesForYou` declares.
The contract has no operation for publishing them, and it deliberately does not need one: they are ordinary commits on a branch the forge already knows about, so an ordinary `git push` of that branch is correct.
Reading `pushesForYou: true` as "never push this branch again" is the failure this paragraph exists to prevent, because it leaves the closing commit sitting in the local clone while the review looks complete.

The review id returned by `openReview` must be something `getReviewState` can look up directly on a later run, from a different clone, without a listing call.
A branch name is not a review id.

`openReview` has one other legitimate outcome, the **manual-handoff result**: no id at all, plus the four things a human needs to open the review by hand - the pushed branch, the base, a suggested title, and a suggested body in full.
An adapter that cannot create reviews (see `generic-git.md`) returns this instead of an id, and it is a typed outcome of the contract rather than a failure.
A caller receiving it must not call `publishReview`, must not record a review id, and must say plainly that opening the review is now the user's step.

One optional operation exists beyond the five, for repairing incomplete records: `findReviewByBranch(branch)`, which finds the reviews opened from a head branch where the forge can do that (`github.md` implements it with a bounded head-branch listing).
Adapters that cannot implement it simply omit it.

**It returns a bounded list of candidate records, newest first, and each record carries three fields: the review id, the review's URL, and the base branch that review targets.**
It returns an empty list when the branch has no reviews, and it never returns a bare id.
A caller needs all three fields.
The id is what `getReviewState` and every later record are written against, the URL is what a `- Review:` line needs in order to name the review to a human, and the base is the only thing that tells apart two reviews sharing one head branch.
That last case is routine rather than exotic: bundle branches chain, so one head branch can carry a review opened against a base the caller no longer targets, and `getReviewState` reports a review's fate without reporting what it targets, so the base has to come from here or from nowhere.
The list is bounded, so treat it as a set of candidates rather than an exhaustive answer, and match within it rather than trusting it to hold exactly one review.
The bound cuts both ways, so a result carrying no matching candidate is not proof that no such review exists, and an empty list is not proof that the branch has no review at all: each says only that the operation saw none inside its window, which is a different claim from there being none.
Adapters bound this differently and a caller cannot see how, so no caller may read absence out of this operation, however the result comes back.
A caller may act on a match it finds here, since a returned record is a review that demonstrably exists.
A caller that would create something on the strength of absence must not use this result for that: it has to establish absence from evidence outside the operation, or stop and hold, and each caller below states which of those it does.

It is used only where a review may exist while nothing in the repository records its id: the sweep repairs records written before review ids were recorded, and `execute` recovers a bundle whose review opened before its `- Review:` line was committed.
When the resolved adapter omits the operation entirely, no lookup is possible at all and such a record cannot be repaired.
Each caller says that once, names the record, and then takes the path its own procedure defines for an unrepairable record rather than guessing: the sweep leaves that issue undecided and closes nothing, per `trackers.md`, and `execute` opens a review for a bundle only where its own plan document records no attempt for that bundle at all, which is evidence of absence that owes nothing to this operation, and otherwise holds rather than risk opening a second review, per `execute/SKILL.md`.
Those two differ because the costs differ, and each file states its own; neither is licensed to invent the other's.

## Declared capabilities

Every adapter file declares this table.
Capabilities are static facts about a forge rather than a runtime question, so they are read from the adapter file and never probed.
An absent capability means false.

| Capability | Values | Drives |
| --- | --- | --- |
| `ciHooks` | true / false | Whether the merge-closer question is asked at all. |
| `draftState` | true / false | Whether `publishReview` is meaningful, and when the `inReview` phase is applied. |
| `pushesForYou` | true / false | Whether `openReview` owns the push, or the calling skill pushes the branch first. |
| `reviewLookup` | `by-id` / `none` | Whether the done-on-merge sweep can run at all. |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | How this adapter expresses that one review is stacked on another, in `openReview`. |

Forges differ in kind, not only in command names, which is the same lesson `agents.md:23-31` already records for tracker MCP builds whose tool coverage varies.
A capability that is false is a fact to design around, not a gap to work around.

`stackedReviews` decides what an adapter does with `openReview`'s optional `dependsOn` argument.

| Value | What `openReview` does with `dependsOn` |
| --- | --- |
| `retarget` | Ignore it. Passing the previous bundle's branch as `base` is the whole mechanism, and the forge retargets the dependent review automatically when its upstream merges. |
| `declared-dependency` | Pass it to the forge's own dependency mechanism, and scope the review's commit range to this bundle's commits only. Nothing is retargeted automatically. |
| `none` | Ignore it. The `base` argument still chains the branches in git, and the calling skill writes the relationship into the review body in prose. |

A `none` adapter is still stackable in the only sense that matters to a reader: the branches chain, each review shows one bundle's diff, and the body says what it depends on.
What it lacks is any forge-side record of the relationship, so nothing retargets and nothing warns when the stack is merged out of order.

Only a repo-local adapter reaches the `none` row in practice.
The one bundled adapter that declares `none` is `generic-git.md`, which is what the manual tier runs on, and the manual tier never proposes a stack.

## Adapter resolution

Resolution and detection are different things, and conflating them is the trap this section exists to prevent.
**Explicit configuration resolves the adapter. Detection only seeds an answer to a question the user is asked.**
An internal forge on an unrecognized host matches no bundled adapter, so remote-URL parsing can never be the primary mechanism; at best it recognizes a forge this plugin already ships.

Resolve in this order, first match winning.

Use `.fathom/forge.md` when the repository contains one; a repo-local adapter wins over everything.
Otherwise, when the profile records `forge: local`, stop.
`local` names the repo-local adapter and nothing else, so a profile that says `local` with no `.fathom/forge.md` present describes an adapter that is missing rather than one to go looking for.
Say which file is absent, that the profile points at it, and that the fix is to restore `.fathom/forge.md` from `forges/TEMPLATE.md` or to change the profile's `forge` field to a bundled adapter or to `none`.
Never resolve `local` to a bundled adapter file, since `forges/local.md` does not exist and treating the field as a filename would look up a path that never resolves.
Otherwise, when the profile records `forge: none`, run in the manual tier described below and make no offers.
Otherwise use the bundled adapter named by the profile's `forge` field, for example `forges/github.md` for `forge: github`.
Stop the same way when that named file does not exist: report the missing adapter and the profile field that named it rather than continuing with no adapter resolved.
Otherwise the repository has no forge answer yet, so run the first-run forge question.

Never infer a forge from the presence of a CLI on `PATH` alone, and never infer one from another repository's profile.
A wrong inference here pushes code to the wrong place.

### The repo-local adapter

`.fathom/forge.md` is how a team supports a forge this plugin has never heard of.
They write one file describing the five operations and the capability table against their own forge's CLI, commit it to their own repository, and every later run resolves it.
No fork of this plugin, and no change to any shared contract, is required.

`forges/TEMPLATE.md` is the annotated skeleton to copy.
A partial adapter is legitimate and useful: an adapter that implements `verifyForge` and `openReview` and declares `reviewLookup: none` is better than no adapter, because it still opens reviews correctly and simply leaves the sweep unavailable.

### First-run forge question

Ask once per repository, and record the answer as `forge` in `.fathom/config.md`.
Use the agent's structured question mechanism named in `agents.md`, as every other first-run question does.

Seed the question with whatever detection can offer, in this order.
Match the `origin` remote's host against the bundled adapters, and suggest a match when one exists.
Otherwise probe `PATH` for candidate forge CLIs and name what was found, as a suggestion the user confirms or rejects.
Otherwise offer the manual tier.

Detection never answers the question by itself.
Report what was found, then let the user choose.

## Capability tiers

Every run operates in exactly one of three tiers, decided by what resolution produced.
The tier is stated at the start of a run so the user knows what will and will not happen.

**Tier 1, adapter.**
An adapter resolved, bundled or repo-local, and `verifyForge()` passed.
All five operations are available, and the declared capability table governs which paths run.

A resolved adapter whose `verifyForge()` fails is not tier 1 and does not stay ambiguous: that run operates in the manual tier.
Make no further calls through the failed adapter, hand the review off exactly as tier 3 does, and name the failed check plus its fix so the user can restore tier 1 for the next run.
Do not drop to tier 2 instead; the tier-2 offers presume no adapter exists, and driving a resolved-but-unverified adapter risks half-authenticated operations against the user's server.

**Tier 2, assisted.**
No adapter resolved, but a candidate forge CLI was found on `PATH`.
Push the branch, then offer three choices: use the candidate for this run only, write `.fathom/forge.md` now so later runs are tier 1, or fall through to the manual tier.
The best outcome is the committed adapter, because it is reviewable by the team and durable across runs.

**Tier 3, manual.**
No adapter, no candidate, the user declined the tier-2 offer, or the profile records `forge: none`.
Push the branch, then print what a human needs in order to open the review by hand: the branch, the base, a suggested title, and a suggested body.
`getReviewState` is unavailable, so the done-on-merge sweep does not run.
A stack is never proposed in this tier: with no review object to create, a three-bundle stack would become three separate sets of open-this-by-hand instructions, which is worse for the user than one review.

`forge: none` is not a fourth tier.
It is the manual tier made permanent, so a repository that will never have an automatable forge stops being offered one on every invocation.

### Adapter or nothing

The tier-2 probe sits close to a boundary this plugin does not cross, so state the rule plainly.

**Anything the agent executes against a forge is authorized by a written adapter file, or by the user's explicit acceptance at this stop of a named candidate for a single run. Never by an inference made in the moment.**

The probe produces a suggestion, not an execution path.
An agent that discovers an unfamiliar CLI and drives it unattended can push the wrong ref, publish a draft to a reviewer group before the work is ready, or file a review in the wrong project, and it does all of that with the user's credentials against the user's server.
So the probe reports what it found and stops, and the user's answer is what authorizes anything further.
Accepting a candidate for one run is a stop that fires in both approval modes; auto mode removes questions, never safety stops.
That acceptance covers exactly the run it was given in, with the CLI named at the stop; anything durable, and anything unattended, requires the written adapter file.

Everything the Absolute boundary in `execute/SKILL.md:9-18` already forbids continues to apply here without exception.
Never search for or read forge credentials in files, environment variables, or token caches.
Never call a forge's HTTP API directly, with a scavenged credential or any other credential.
Never modify the agent's or the user's configuration to install, enable, or authenticate a forge CLI.
A missing or unauthenticated forge CLI is the user's decision; it selects a tier, and it is never an obstacle to route around.

### Tier 3 and issues that never close

In the manual tier nothing can observe review state, so the done-on-merge sweep can never fire and issues stay in the `inReview` phase indefinitely.

Still apply `inReview` when the run hands off a review to the user: a human really does open one, and the phase is accurate at the moment it is set.
But say so at handoff, in plain words, that no later run will move the issue to `done` on its own and that closing it is now a manual step.
Record the same fact in the profile when `forge: none` is written.

Silence here would be the worst available outcome.
An agent that quietly turns the tracker into a one-way ratchet, in exactly the restricted environments this contract exists to serve, has misled the user about the state of their work.

## Base branch resolution

Feature branches start from, and reviews target, one base branch.
Resolve it in this order, first match winning.

Use the base branch named in the invocation when the request specifies one, and treat that as applying to this run only.
Otherwise use the profile's `base-branch` when it records one.
Otherwise use the repository's current branch, and say which branch you resolved so the choice is visible.

Guard against one trap: when the current branch is itself a Fathom feature branch, meaning its name carries an issue ref and one of the branch prefixes, do not silently use it as a base.
Building one issue's work on top of another's unmerged branch entangles two reviews, so ask which base to use instead.

Fetch the resolved base branch before creating anything from it, and create the new branch from the fetched remote copy rather than from a local copy that may be behind.

Confirm the resolved base with `resolveBase` before opening a review against it.
