# Generic git

The fallback adapter for a repository whose forge this plugin cannot drive.
Implements the contract in `../forges.md`; read that file first.

This adapter assumes nothing beyond git itself and a reachable remote.
It is what the manual tier runs on, and it is selected when no adapter resolved and no candidate CLI was accepted, or when the profile records `forge: none`.

It is a real adapter, not an error state.
Work still gets committed, pushed, and handed to a human in a usable form; what is missing is the plugin's ability to observe what happens after that.

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | false |
| `draftState` | false |
| `pushesForYou` | false |
| `reviewLookup` | `none` |
| `stackedReviews` | `none` |

`stackedReviews: none` is never exercised through this adapter.
This adapter is what the manual tier runs on, and `../forges.md` states that the manual tier never proposes a stack, so `openReview` here is only ever called for a standalone review.
The value is declared truthfully rather than left absent, because a repo-local adapter author reading this file as the minimum viable example needs to see every capability filled in.

`reviewLookup: none` is the consequential one.
It means the done-on-merge sweep cannot run in this repository, and every skill that would have swept must say so rather than reporting a clean sweep it never performed.

`ciHooks: false` means the merge-closer question is never asked, and the profile records `merge-closer: none (forge has no hooks)`.
Offering a GitHub Actions workflow here would write a file that never executes and record a capability that does not exist, which is worse than declining.

## `verifyForge()`

Verify only that this is a git repository with a reachable remote: `git rev-parse --git-dir`, then `git ls-remote origin >/dev/null`.

Verified when both succeed.
Ask git only whether the remote answers, never whether it advertises any particular ref.
`git ls-remote --exit-code origin HEAD` fails on a reachable remote that does not advertise `HEAD`, such as one whose default branch is unset, and a preflight that treats that as unreachable rejects a forge that works.
The branch-specific check belongs in `resolveBase`, which is where a named ref genuinely has to exist.

When the remote is unreachable, report that plainly: an unreachable remote stops the push, so it is a real failure rather than a tier selection.

This adapter never checks for, or asks about, any forge CLI.
The tier-2 probe already ran and either found nothing or was declined; re-probing here would reopen a question the user has answered.

## `resolveBase(branch)`

Confirm the branch exists on the remote with `git ls-remote --exit-code --heads origin <branch>`.

## `openReview(branch, base, title, body, dependsOn?)`

This operation does not push.
`pushesForYou` is false, so the branch has already been pushed by the caller before this runs, exactly as on any other adapter that declares false.

There is no review to create, so this operation returns the contract's manual-handoff result instead of an id.
Print what a human needs to open the review by hand:

- The branch that was pushed.
- The base branch it should target.
- The suggested title.
- The suggested body, in full, so it can be pasted rather than reconstructed.

Return no review id.
`dependsOn` is ignored here for the same reason the id is absent: there is no review object to attach a dependency to.

Say plainly, at this point, all three of these, since a partial statement is what leaves the user guessing:

- No review was opened on any forge, and opening it is now the user's step.
- The tracker issue has still been moved to the `inReview` phase, so the board and the forge disagree by design until the user opens the review.
- Closing the issue is manual, because `getReviewState` is always `unknown` here.

Do not describe the work as "in review" unqualified in the run's own reporting when no review exists yet; name the tracker phase and the missing review separately, so the phase is never read as evidence that a review exists.

## `publishReview(id)`

A no-op. `draftState` is false, and there is no review object to publish.

## `getReviewState(id)`

Always `unknown`.

There is no id to look up and no mechanism to look one up with.
A caller receiving `unknown` must not infer anything from it: `unknown` is not `open`, and it is certainly not `merged`.

## The consequence, stated to the user

Because `getReviewState` is always `unknown`, no later run will ever move an issue from `inReview` to `done` on its own.
Issues opened through this adapter accumulate in `inReview` until a human closes them in the tracker.

`../forges.md` requires this to be said out loud at handoff rather than left for the user to discover.
Say it when a review is handed off, and record it in the profile when `forge: none` is written.
An agent that quietly turns the tracker into a one-way ratchet has misled the user about the state of their work.
