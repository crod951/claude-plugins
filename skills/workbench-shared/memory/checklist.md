# checklist adapter

This adapter is backed by a single markdown file, `.workbench/tasks/<ISSUE-REF>.md`, committed inside the consumer's repo on the feature branch.
Only use this adapter once `memory.md`'s resolution procedure has already chosen the checklist for this run.
Commit the file with every change this adapter makes, except the in-progress marker and the deferred hash append described under `close`, which stay uncommitted until they ride a later commit.
The file is the parent record for the issue and the durable store for every task under it; there is no second location for status.
Keep the file after the review merges; it stays in the repo permanently as the record of what was done.

## File format

```markdown
# ONC-5: Add login flow

- Issue: https://linear.app/acme/issue/ONC-5
- Branch: feat/onc-5-add-login
- Review: (id and url, filled at open)
- PR: (legacy, read but no longer written)

## Plan

One-paragraph approach summary.
Testing notes.

## Tasks

- [x] 1. Create login form component -> sub-issue: https://... (done 2026-07-28, a1b2c3d)
- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://...
- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://...
```

The header line names the issue.
The `Issue`, `Branch`, and `Review` lines track the record's links; fill in `Review` with the id and URL that `openReview` returns.
The id is what the done-on-merge sweep looks the review up by, so record it even when the URL alone would read more naturally.
`PR` is the legacy form of that line, carrying a URL and no id.
Keep reading it on records written before this format, and fall back to branch matching for those, but never write a new one.
The `## Plan` section holds the one-paragraph approach and testing notes written during planning.
The `## Tasks` section holds one line per task, numbered in creation order; the number is that task's id for `deps` references and for `close`.
Never renumber existing tasks when adding a new one; numbers are permanent once assigned.

## Operation mapping

| Contract operation | Checklist file mapping |
| --- | --- |
| `init(issueRef)` | Check whether `.workbench/tasks/<ISSUE-REF>.md` exists. When it does not, create it with the header line, the `Issue`, `Branch`, and `Review` lines, an empty `## Plan` section, and an empty `## Tasks` section, then commit it. When it already exists, do nothing; never overwrite an existing file. |
| `createTask(title, description, subIssueRef, deps)` | Append a line to the `## Tasks` section: `- [ ] N. <title> (deps: <dep-ids>) -> sub-issue: <subIssueRef>`, where `N` is the next unused task number. Omit the `(deps: ...)` segment when `deps` is empty. Fold any free-text `description` into the task title or leave it out of the line entirely; the checklist format has no separate description field. Commit this line together with the scaffold commit that creates the corresponding sub-issue; when the sub-issue already existed and was adopted rather than created, there is no scaffold commit, so commit the line with the breakdown commit instead. Return `N` as the task id. |
| `claimNext()` | Read the file from the working tree and take the first `- [ ]` line whose listed deps are all `- [x]`, then rewrite that line's marker to `- [>]`. Leave the rewrite uncommitted: it rides the task's implementation commit later, so it never becomes a commit of its own. An uncommitted `- [>]` marker in the working tree is the resume signal, which is why resume reads the tree rather than the last commit. When a `- [>]` line already exists, return that task to be resumed instead of claiming a new one. This adapter assumes exactly one active runner per issue branch; it has no lock, so two concurrent runners could both claim or both resume the same task. When the file changes underfoot between reading and rewriting it, or the working tree shows commits this runner did not make, treat that as evidence of a second runner: stop and report rather than claim, since the resumable-single-pass contract makes concurrent runners out of scope by design. |
| `close(taskId)` | Rewrite that task's `- [>]` marker to `- [x]` and append the ISO done date. Commit the implementation together with this rewrite as one commit. Then read that commit's short hash, state it in the progress line immediately, and append it to the closed task's line in the working tree, leaving that hash edit uncommitted so it rides the next commit that touches this file, which is the next task's close or the run's final closing commit. Never amend the closing commit to add its own hash: a file staged into a commit cannot contain that commit's final hash, and amending changes the hash again, so the recorded value would name a commit that no longer exists. Never create a separate commit just to carry the hash. |
| `status()` | Count `## Tasks` lines by marker: `[ ]` and `[>]` together are the open count, `[x]` is the done count. Report the single `[>]` line, when one exists, as the current in-progress task; report none in progress when no line carries `[>]`. |
| `parentTask(issueRef)` | The file itself is the parent task; there is no separate parent record to create or fetch. Read the header line and the `Issue`/`Branch`/`PR` lines as the parent's fields. When `init` has already run for this `issueRef`, this operation is a no-op that returns the file's path as the parent id. Closing the parent at finish is likewise a no-op in this adapter: the file is the parent record, and it counts as closed once every task line is `- [x]`. |

## Marker legend

| Marker | Meaning |
| --- | --- |
| `[ ]` | Open: not started, waiting on its dependencies or waiting to be claimed. |
| `[>]` | In progress: claimed by `claimNext` and not yet closed. |
| `[x]` | Done: closed by `close`. |

At most one line carries `[>]` at a time; `claimNext` only ever promotes one line before the previous in-progress line closes.

## Compatibility with the done-on-merge sweep

The done-on-merge sweep (see `../trackers.md`) appends a trailing `- Closed: <date>` line to this same file after it applies the done state, as a marker so the sweep never re-processes the same issue twice.
Treat that line as a footer outside the `## Tasks` section, not as a task line.
Never parse it for a marker, never assign it a task number, and never let its presence change the counts returned by `status()`.
When writing or rewriting this file for any other operation, leave an existing `- Closed: <date>` line exactly where it is, after the last task line.

When closing a task, append the short hash of its implementing commit to that task's line alongside the done date, as the commit-verification rules in `../conventions.md` require; that appended hash stays uncommitted until the next commit touching this file carries it.
A line that records a hash cannot be written before the commit exists, which is what makes the one-commit-per-task rule checkable rather than merely stated.

Write multiple dependencies as a comma-separated list inside one parenthesis, for example `(deps: 1, 2)`.
Write the done date in ISO form, `YYYY-MM-DD`, so lines sort and parse predictably.
