# Forge adapter template

Copy this file to `.fathom/forge.md` in your repository, fill it in for your forge, and commit it.
A repo-local adapter wins over every bundled one, so nothing else needs to change and this plugin does not need to be forked.

Read `../forges.md` for the contract these operations implement.
Read `github.md` for a complete worked example, and `generic-git.md` for the minimum viable one.
Those three references resolve inside the plugin's `skills/fathom-shared/forges/` directory, so read them before copying this file; from the copy at `.fathom/forge.md` they will not resolve, which is fine because the finished adapter needs none of them at runtime.

Guidance is in `>` blockquotes throughout. Delete the blockquotes as you fill each section in.

> **Write for an agent, not a human reader.** An agent reads this file at runtime and does what it says. Prefer exact commands over descriptions of commands. When a command's output needs interpreting, say which field to read and what each value means.

> **A partial adapter is legitimate.** Implementing `verifyForge` and `openReview` and declaring `reviewLookup: none` is a good adapter. It opens reviews correctly and leaves the sweep unavailable, which is honest. Do not stub an operation with a guess to make the table look complete - a wrong `getReviewState` closes issues that never shipped.

---

# <Forge name>

<One or two sentences: what this forge is, and which CLI or tool drives it.>

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | true / false |
| `draftState` | true / false |
| `pushesForYou` | true / false |
| `reviewLookup` | `by-id` / `none` |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` |

> `ciHooks` - can a workflow run in your repository on merge, the way GitHub Actions does? If not, false, and the merge-closer question is skipped rather than asked and answered wrongly.
>
> `draftState` - does your forge distinguish a draft review from one that has notified reviewers? If it creates reviews as drafts by default, this is true and `publishReview` must do real work.
>
> `pushesForYou` - **get this one right.** If your review CLI pushes the review ref itself, set true, and the calling skill will not push. Setting it false when your CLI does push produces a wrong branch state, and on some forges a manual push is explicitly discouraged for exactly this reason.
>
> `reviewLookup` - `by-id` only if you can look up one review's state directly, from any clone, given the id `openReview` returned. If reviews can only be found by listing, or not found at all, this is `none`.
>
> `stackedReviews` - how your forge expresses that one review is stacked on another, which decides what your `openReview` does with the optional `dependsOn` argument. `retarget` if stacking is just pointing a review at the previous branch, and your forge retargets automatically when the upstream merges. `declared-dependency` if stacking means declaring an explicit dependency and scoping the commit range yourself, with no automatic retarget. `none` if your forge has no stacking model at all, which is a fine answer: the calling skill still chains the branches in git and writes the relationship into the review body.

## Absolute boundary

> Restate the boundary for your forge. This is not boilerplate - it is what stops an agent from routing around a missing credential.

Never call this forge's HTTP API directly.
Never read tokens from disk or from the environment.
Never modify the user's CLI configuration, and never authenticate on the user's behalf.
When the CLI is missing or unauthenticated, that is the answer; report the fix and stop.

## `verifyForge()`

<The one cheap, read-only command that proves the CLI is present and authenticated.>

> Must be read-only and fast - it runs on every invocation. An auth-status subcommand is ideal. Do not use a command that creates, modifies, or lists large amounts of data.

Treat a missing binary and an unauthenticated one identically: unverified.

When it does not verify, report the fix:

- <How to install the CLI.>
- <How to authenticate.>
- Re-invoke the skill.

## `resolveBase(branch)`

<How to confirm the named base branch exists on the remote and can be merged into.>

> `git ls-remote --exit-code --heads origin <branch>` works on most forges and is a fine answer. Use something forge-specific only if your forge has merge targets that are not plain branches.

## `openReview(branch, base, title, body, dependsOn?)`

<The command that creates the review.>

> State explicitly whether this pushes. If `pushesForYou` is true, say that the caller must not push separately to open the review, and why. Scope that to opening the review: commits the caller makes afterwards, including the final closing commit, stay the caller's to push, as `../forges.md` states.
>
> **Make it idempotent.** Skip creation and return the existing review when one already exists for this branch or change. Skills re-run on the same issue to resume, and a second review opened on a resume is a real failure.
>
> **Say how to extract the review id from the command's output**, exactly - which field, which format. This id is written to disk and looked up on later runs from possibly a different clone, so it must be stable. A branch name is not a review id.

> **Say what you do with `dependsOn`, explicitly, even when the answer is nothing.** It arrives holding the review id this one is stacked on, and it is absent for a standalone review and for the first review in a stack. If you declared `retarget` or `none`, write "Ignore `dependsOn`" and say that the `base` argument carries the relationship. If you declared `declared-dependency`, give the exact command that records the dependency, and say how you scope the review to this bundle's commits only - a declared dependency with an unscoped range shows the upstream bundle's changes twice.

Return the review id and the review's URL.

<Note any body conventions your forge interprets - issue-closing keywords, trailers, required footers.>

## `publishReview(id)`

<The command that moves a draft review to notified-review state.>

> If `draftState` is false, write "A no-op." and nothing else.
>
> If your forge creates reviews as drafts by default, this operation is load-bearing: without it the tracker will say "in review" while no reviewer has been notified and the diff is still mutable.

## `getReviewState(id)`

<The command that reads one review's state by id, and how to map its output.>

Map the result to exactly one of:

- `merged` - the change landed. <Which field proves this, and where the merge timestamp comes from.>
- `closed-unmerged` - the review ended without landing. <Which field distinguishes this from merged.>
- `open` - still in flight.
- `unknown` - cannot be determined.

> **The merged/closed-unmerged distinction is the one to be careful about.** `merged` closes the tracker issue. A forge that reports both as simply "closed" must map to `closed-unmerged` unless something positively proves the change landed. Guessing `merged` marks work as shipped when it was abandoned.
>
> If you cannot look up a single review by id, do not improvise a listing-based version here. Declare `reviewLookup: none`, write "Always `unknown`." in this section, and let the sweep stay unavailable. An unavailable sweep is a stated limitation; a wrong sweep is a silent data problem in the user's tracker.

> **If `reviewLookup` is `none`,** also state plainly that no later run will move an issue from `inReview` to `done` on its own, and that closing issues is a manual step in this repository. `../forges.md` requires that to be said at handoff rather than left for the user to discover.
