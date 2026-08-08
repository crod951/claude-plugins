# GitHub

The forge adapter for GitHub, driven entirely through the GitHub CLI, `gh`.
Implements the contract in `../forges.md`; read that file first for the operation and capability definitions this one fills in.

GitHub's own vocabulary is used throughout this file, so a review is a pull request and a review id is a pull request number.
Shared contracts outside this file say "review"; that difference is deliberate, not drift.

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | true |
| `draftState` | true |
| `pushesForYou` | false |
| `reviewLookup` | `by-id` |
| `stackedReviews` | `retarget` |

`ciHooks` is true because GitHub Actions can run a merge-closer workflow in the user's repository; the tracker adapters' merge-closer offers are gated on this.
`pushesForYou` is false because `gh pr create` does not push the branch, so the calling skill pushes first.
`stackedReviews` is `retarget` because GitHub stacking is branch retargeting, and GitHub retargets a dependent pull request automatically when its upstream merges.
That automatic retarget is real but partial, and the gap matters to the caller.
When the upstream pull request is **squash-merged**, the squash commit is not an ancestor of the dependent branch, so the dependent pull request retargets to the base and then redisplays the upstream bundle's changes as if they were new.
The dependent branch has to be rebased for its diff to be honest again, which is why the calling skill's rebase rule is keyed on commit ancestry rather than on this capability value.

## Absolute boundary

The GitHub HTTP API is not a fallback for any operation here.
When `gh` is missing or unauthenticated, that is the answer, and it selects a tier per `../forges.md`.

Never call the GitHub HTTP API directly.
Never read tokens from disk or from the environment, including `GITHUB_TOKEN` and `GH_TOKEN`.
Never modify the user's `gh` configuration, and never run `gh auth login` on the user's behalf.
Authentication is the user's to perform.

## `verifyForge()`

Run `gh auth status`.

Treat a missing binary and an unauthenticated one identically: unverified.
Do not distinguish them in the outcome, only in the fix text below.

When it does not verify, report the fix rather than working around it:

- Install the CLI with `brew install gh` on macOS, or the platform package listed at https://github.com/cli/cli#installation.
- Authenticate with `gh auth login`.
- Re-invoke the skill.

Delivering these instructions is a complete, useful action, not a fallback.

## `resolveBase(branch)`

Confirm the branch exists on the remote with `git ls-remote --exit-code --heads origin <branch>`.
A base branch that exists only locally is not a valid merge target, because the pull request is created against the remote.

## `openReview(branch, base, title, body, dependsOn?)`

Push the branch first; `pushesForYou` is false, so the push is the caller's and this operation does not perform it.

Create the pull request with `gh pr create --base <base> --head <branch> --title <title> --body <body>`.
Skip creation when a pull request already exists for the branch, and return the existing one; re-running the skill on the same issue must not open a second pull request.

Return the pull request number as the review id, and the pull request URL.
The number is what `getReviewState` looks up, and it resolves from any clone without a listing call.
Ignore `dependsOn` when it is supplied.
`stackedReviews` is `retarget`, so passing the previous bundle's branch as `base` is the entire mechanism, and GitHub needs no separate dependency declaration.
Never encode the dependency a second way, such as by adding a label or an extra API call; the base branch already carries it and a second representation can disagree with the first.
The `Depends on <url>` line in a review body is prose for a human reviewer and carries no machine meaning, so it is not a second representation of the dependency; the prohibition is on machine-readable representations such as a label or an extra API call.
Nothing on GitHub reads that line, which is why the calling skill writes it into every bundle after the first while this operation still ignores `dependsOn`.

Two body conventions matter on GitHub specifically, and the calling skill supplies them:

- `Closes <ref>` is a GitHub issue-closing keyword, and Linear's GitHub integration keys on the same line to close a Linear issue when the pull request merges into the default branch.
- An Asana task URL in the body is what Asana's native GitHub integration attaches to.

Neither is this adapter's decision; both are recorded here because they are GitHub-specific behavior that would be wrong to carry into another adapter.

## `publishReview(id)`

A deliberate no-op.

GitHub distinguishes draft from ready-for-review pull requests, so `draftState` is true, but the current skill flow opens pull requests ready for review and never opens drafts.
`publishReview` therefore has nothing to do, and this adapter preserves that existing behavior exactly.

Driving the `inReview` phase off publication rather than off creation, so that a draft pull request no longer moves an issue to `inReview`, is a known and deliberate follow-up.
Do not fix it here; changing GitHub's behavior inside the portability change would make that change unreviewable.

## `getReviewState(id)`

Run `gh pr view <id> --json state,mergedAt`.

Map the result:

- `mergedAt` is non-null → `merged`, with `mergedAt` as the merge timestamp.
- state is closed and `mergedAt` is null → `closed-unmerged`.
- otherwise → `open`.

Look up each recorded id directly.
Do not list pull requests to find one.
An earlier version of the sweep matched `gh pr list --state all --json headRefName,state,mergedAt` against recorded branch names, which silently skipped older branches whenever the listing hit its default cap of 30; per-id lookup removes that hazard entirely and is the reason the sweep is keyed on ids.

## `findReviewByBranch(branch)` - optional, record repair only

Run `gh pr list --state all --head <branch> --json number,url,baseRefName --limit 10`.

Return one candidate record per pull request the listing returned, newest first, each carrying the pull request number as the review id, its URL, and `baseRefName` as its base.
Return an empty list when the listing is empty.
Never collapse the list to the newest entry here: a head branch can carry more than one pull request, and which of them the caller wants is the caller's question to answer from the base, per the contract in `../forges.md`.

This is the one sanctioned listing call, and it exists only so an incomplete record can be repaired: the sweep repairs a record written before review ids were recorded, and `execute` recovers a bundle whose pull request opened before its `- Review:` line was committed.
Scoping the list to one head branch keeps it bounded regardless of repository age, which is what the unscoped listing above could not guarantee.
Never use it for records that already carry an id.
