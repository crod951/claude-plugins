# beads adapter

This adapter is backed by the `bd` CLI, a local dependency-aware task tracker that stores its state in `.beads/` inside the consumer's repo.
Only use this adapter once `memory.md`'s resolution procedure has already chosen beads for this run.
The flags below were verified against `bd version 0.49.0` (Homebrew) using `bd --help` and `bd <subcommand> --help`.
When a later `bd` upgrade renames or removes a flag used here, re-run those same help commands and update this mapping before trusting it again.

## Operation mapping

| Contract operation | beads CLI mapping |
| --- | --- |
| `init(issueRef)` | Check whether `.beads/` exists in the repo root. Run `bd init` only when it is absent, passing a short prefix of three or four characters abbreviated from the project directory name and the flag that skips git hook installation. The short prefix keeps task ids readable, and skipping hooks avoids installing pre-commit and post-merge hooks that block branch switching and interfere with unrelated commits. Do nothing when `.beads/` already exists; never re-run `bd init` on an existing database. |
| `createTask(title, description, subIssueRef, deps)` | Run one `bd create "<title>" -d "<description>" -l "<issueRef>" --external-ref "<subIssueRef>" --deps "<comma-separated blocker ids>" --silent` and capture the single line of output as the new task id. Do it in that one call rather than as a create followed by separate writes, for the durability reason in the notes below. Tagging the task with the issue ref lets every task for one issue be listed directly with `bd list -l "<issueRef>"` instead of matching on titles, and `--silent` makes `bd create` print only the issue id, which this adapter always needs for its return value. Omit `--external-ref` entirely when no `subIssueRef` was passed, and omit `--deps` entirely when `deps` is empty, rather than passing an empty value to either. Each id in `--deps` makes the new task depend on that blocker, so it stays excluded from `claimNext` until the blocker closes. Use the title and description exactly as passed in; embedding the issue ref into the title (the `<issueRef>: <task title>` naming convention) is the caller's responsibility, not this adapter's. |
| `claimNext()` | Run `bd ready -l "<issueRef>" --type task --limit 50 --json` to get this issue's tasks that have no open blockers. The label filter is not optional: `bd ready` without it returns ready work from the whole repository, so an unscoped call will hand back another issue's task and the loop will implement it on this issue's branch and close the wrong sub-issue. The explicit limit matters too, since `bd ready` defaults to showing only ten. Note that `bd ready` includes tasks already `in_progress`, so inspect status before claiming: when a returned task is already `in_progress` from an interrupted run, resume that task and do not call `--claim` on it, because `bd update --claim` fails when the task is already claimed. Otherwise take the oldest still-open task and run `bd update <id> --claim` to set it to `in_progress` atomically, then return that id. Return null only when the scoped result contains no open and no in-progress task. |
| `close(taskId)` | Run `bd close <taskId>` to mark the task done. Record the short hash of the commit that implemented the task as well, per the commit-verification rules in `../conventions.md`; attach it with `bd update <taskId> --notes` when that flag exists on the installed version, and otherwise state the hash in the progress line. Verify the flag with `bd update --help` rather than assuming it. |
| `status()` | Run `bd count -l "<issueRef>" --type task --by-status --json` to get counts for this issue's tasks only, grouped by status; the label filter is required here for the same reason as `claimNext`, since an unscoped count reports the whole repository. Compute the open count as the sum of the `open`, `blocked`, `deferred`, and `in_progress` buckets, never the raw `open` bucket alone: a task with an open dependency reports as `blocked`, the claimed task reports as `in_progress`, and dropping either would undercount pending work; this matches the checklist adapter, whose open count also includes the in-progress line. Compute the done count as the `closed` bucket. Run `bd list -l "<issueRef>" --type task --status in_progress --limit 1 --json` to identify the current in-progress task; when it returns no rows, report that none is in progress. |
| `parentTask(issueRef)` | Fetch first: run `bd list -l "<issueRef>" --type epic --json` and reuse the returned epic's id when one exists. Create it otherwise: `bd create "<issueRef>" --type epic --external-ref "<issueRef>" -l "<issueRef>" -p 1 --silent`, capturing the printed id. Do not attempt to add child dependency edges here; at the time `parentTask` runs the children do not exist yet. After every child task has been created, add one edge per child with `bd dep add <parentId> <childId>` so the parent depends on all of them and cannot close first. Never add the reverse edge, from a child to the parent, which would deadlock both. |

## Notes

Beads exposes five status values: `open`, `in_progress`, `blocked`, `deferred`, and `closed`.
The memory contract only ever needs this adapter to move a task through `open` then `in_progress` then `closed`.
Never set `blocked` or `deferred` directly.
Beads does not rewrite a task's stored status when a dependency is added; an unmet dependency keeps the task at `open` while `bd ready` and `bd blocked` compute blocking from the dependency graph at query time.
That is why claim decisions must come from `bd ready` rather than from a status filter.
`bd update <id> --claim` resolves the current actor from `--actor`, then `$BD_ACTOR`, then git's `user.name`, then `$USER`, in that order.
Do not pass a separate `--assignee` flag unless multiple agents share one checkout and need distinct identities.
Prefer `--json` on every read command (`bd list`, `bd count`) when parsing output programmatically, since plain output is meant for a human terminal and can change formatting across versions.
`createTask` is one `bd create` call rather than a create followed by `bd update --external-ref` and one `bd dep add` per blocker, because those are three writes that can fail apart.
A run interrupted between them leaves a task carrying no external ref and no dependency edges, and nothing on that orphan identifies which sub-issue it belongs to, so the retry cannot recognize it and creates a second task for the same sub-issue.
One call either produces a complete task or produces nothing, which makes a retry safe.
The flags were verified equivalent on 0.49.0: a task created with `--deps <blockerId>` is excluded from `bd ready` until that blocker closes and appears once it does, exactly as one given the same edge by `bd dep add`.
`parentTask` still adds its edges with `bd dep add` afterwards, which is unavoidable, since the children do not exist when the parent is created.

## Repository hygiene

The beads tooling handles its own ignore rules and merge setup during `init`; verify rather than duplicate.

After `init`, confirm two files exist and keep them: `.beads/.gitignore`, which excludes the database, write-ahead and shared-memory files, daemon runtime files, merge artifacts, and per-machine sync state, and `.gitattributes`, which registers the beads merge driver for the JSONL export.
Do not add a second copy of those rules at the repository root.
A duplicate block drifts from what the tooling actually ignores, and one earlier hand-written version wrongly ignored `metadata.json`, which beads intends to be tracked alongside the JSONL exports.

Ignore rules cannot rescue a file that is already tracked.
The dirty-working-tree and failed-branch-switch problems that look like ignore-rule gaps are almost always caused by blanket staging having committed runtime files before any rule existed.
Follow the staging rules in `../conventions.md`: stage named paths only, never `git add -A` or `git add .`.
When runtime files are already tracked in a repository, stop staging them and untrack them once with an explicit cached removal, then commit that removal.

Long-lived parallel branches that both write task state will conflict on the JSONL export.
The merge driver registered by `.gitattributes` is what resolves those conflicts, so keep that file when beads creates it.
Resolve a JSONL conflict by letting beads regenerate the export from its database rather than hand-merging the JSON lines.

Commit the JSONL export with each task's commit, not only at the end of the run.
The database itself is ignored by design, so an export left uncommitted means a task closed on this machine is invisible to any other clone, which breaks resume on a different machine.
