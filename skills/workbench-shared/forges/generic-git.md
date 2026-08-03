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

`reviewLookup: none` is the consequential one.
It means the done-on-merge sweep cannot run in this repository, and every skill that would have swept must say so rather than reporting a clean sweep it never performed.

`ciHooks: false` means the merge-closer question is never asked, and the profile records `merge-closer: none (forge has no hooks)`.
Offering a GitHub Actions workflow here would write a file that never executes and record a capability that does not exist, which is worse than declining.

## `verifyForge()`

Verify only that this is a git repository with a reachable remote: `git rev-parse --git-dir`, then `git ls-remote --exit-code origin HEAD`.

Verified when both succeed.
When the remote is unreachable, report that plainly — an unreachable remote stops the push, so it is a real failure rather than a tier selection.

This adapter never checks for, or asks about, any forge CLI.
The tier-2 probe already ran and either found nothing or was declined; re-probing here would reopen a question the user has answered.

## `resolveBase(branch)`

Confirm the branch exists on the remote with `git ls-remote --exit-code --heads origin <branch>`.

## `openReview(branch, base, title, body)`

Push the branch; `pushesForYou` is false, so the caller performs the push, exactly as it does on any other adapter.

There is no review to create, so this operation produces a handoff instead.
Print what a human needs to open the review by hand:

- The branch that was pushed.
- The base branch it should target.
- The suggested title.
- The suggested body, in full, so it can be pasted rather than reconstructed.

Return no review id.

Say plainly, at this point, that no review was opened and that opening it is now the user's step.
Do not describe the work as "in review" in the run's own reporting when no review exists yet.

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
