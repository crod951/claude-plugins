# checklist adapter

This adapter is backed by a single markdown file, `.issue-lifecycle/tasks/<ISSUE-REF>.md`, committed inside the consumer's repo on the feature branch.
Only use this adapter once `memory.md`'s resolution procedure has already chosen the checklist for this run.
Commit the file with every change this adapter makes, including in-progress marker rewrites.
The file is the parent record for the issue and the durable store for every task under it; there is no second location for status.
Keep the file after the PR merges; it stays in the repo permanently as the record of what was done.

## File format

```markdown
# ONC-5: Add login flow

- Issue: https://linear.app/acme/issue/ONC-5
- Branch: feat/onc-5-add-login
- PR: (filled at open)

## Plan

One-paragraph approach summary.
Testing notes.

## Tasks

- [x] 1. Create login form component -> sub-issue: https://... (done 2026-07-28)
- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://...
- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://...
```

The header line names the issue.
The `Issue`, `Branch`, and `PR` lines track the record's links; fill in `PR` once the pull request opens.
The `## Plan` section holds the one-paragraph approach and testing notes written during planning.
The `## Tasks` section holds one line per task, numbered in creation order; the number is that task's id for `deps` references and for `close`.
Never renumber existing tasks when adding a new one; numbers are permanent once assigned.

## Operation mapping

| Contract operation | Checklist file mapping |
| --- | --- |
| `init(issueRef)` | Check whether `.issue-lifecycle/tasks/<ISSUE-REF>.md` exists. When it does not, create it with the header line, the `Issue`, `Branch`, and `PR` lines, an empty `## Plan` section, and an empty `## Tasks` section, then commit it. When it already exists, do nothing; never overwrite an existing file. |
| `createTask(title, description, subIssueRef, deps)` | Append a line to the `## Tasks` section: `- [ ] N. <title> (deps: <dep-ids>) -> sub-issue: <subIssueRef>`, where `N` is the next unused task number. Omit the `(deps: ...)` segment when `deps` is empty. Fold any free-text `description` into the task title or leave it out of the line entirely; the checklist format has no separate description field. Commit this line together with the scaffold commit that creates the corresponding sub-issue. Return `N` as the task id. |
| `claimNext()` | Scan the `## Tasks` section top to bottom for the first `- [ ]` line whose every listed dependency number is currently marked `- [x]` in this same file. A line with no `(deps: ...)` segment has no dependencies and is immediately eligible. Return null when no such line exists. Otherwise rewrite that line's marker from `[ ]` to `[>]`, commit the rewrite, and return the task number as the task id. |
| `close(taskId)` | Find the `## Tasks` line numbered `taskId`, rewrite its marker from `[>]` to `[x]`, and append `(done <date>)` to the end of the line. Stage this rewrite into the same commit that implements the task; the rewrite rides that single commit and never becomes a commit of its own. |
| `status()` | Count `## Tasks` lines by marker: `[ ]` and `[>]` together are the open count, `[x]` is the done count. Report the single `[>]` line, when one exists, as the current in-progress task; report none in progress when no line carries `[>]`. |
| `parentTask(issueRef)` | The file itself is the parent task; there is no separate parent record to create or fetch. Read the header line and the `Issue`/`Branch`/`PR` lines as the parent's fields. When `init` has already run for this `issueRef`, this operation is a no-op that returns the file's path as the parent id. |

## Marker legend

| Marker | Meaning |
| --- | --- |
| `[ ]` | Open: not started, waiting on its dependencies or waiting to be claimed. |
| `[>]` | In progress: claimed by `claimNext` and not yet closed. |
| `[x]` | Done: closed by `close`. |

At most one line carries `[>]` at a time; `claimNext` only ever promotes one line before the previous in-progress line closes.

## Compatibility with the done-on-merge sweep

The Asana done-on-merge sweep (see `trackers/asana.md`) appends a trailing `- Closed: <date>` line to this same file after it applies the done state, as a marker so the sweep never re-processes the same issue twice.
Treat that line as a footer outside the `## Tasks` section, not as a task line.
Never parse it for a marker, never assign it a task number, and never let its presence change the counts returned by `status()`.
When writing or rewriting this file for any other operation, leave an existing `- Closed: <date>` line exactly where it is, after the last task line.
