# beads adapter

This adapter is backed by the `bd` CLI, a local dependency-aware task tracker that stores its state in `.beads/` inside the consumer's repo.
Only use this adapter once `memory.md`'s resolution procedure has already chosen beads for this run.
The flags below were verified against `bd version 0.49.0` (Homebrew) using `bd --help` and `bd <subcommand> --help`.
When a later `bd` upgrade renames or removes a flag used here, re-run those same help commands and update this mapping before trusting it again.

## Operation mapping

| Contract operation | beads CLI mapping |
| --- | --- |
| `init(issueRef)` | Check whether `.beads/` exists in the repo root. Run `bd init` only when it is absent, passing a short prefix of three or four characters abbreviated from the project directory name and the flag that skips git hook installation. The short prefix keeps task ids readable, and skipping hooks avoids installing pre-commit and post-merge hooks that block branch switching and interfere with unrelated commits. Do nothing when `.beads/` already exists; never re-run `bd init` on an existing database. |
| `createTask(title, description, subIssueRef, deps)` | Run `bd create "<title>" -d "<description>" -l "<issueRef>" --silent`, tagging the task with the issue ref so every task for one issue can be listed directly with `bd list -l "<issueRef>"` instead of matching on titles. Continue with the same call shape: and capture the single line of output as the new task id; `--silent` makes `bd create` print only the issue id, which this adapter always needs for its return value. When `subIssueRef` is given, run `bd update <id> --external-ref "<subIssueRef>"` to store it on the task. For each blocker id in `deps`, run `bd dep add <id> <depId>` so the new task depends on that blocker and stays excluded from `claimNext` until the blocker closes. Use the title and description exactly as passed in; embedding the issue ref into the title (the `<issueRef>: <task title>` naming convention) is the caller's responsibility, not this adapter's. |
| `claimNext()` | Run `bd ready --json` to get the tasks that genuinely have no open blockers, then take the oldest task-type entry from that list. Do not use `bd list --ready` for this: despite the name, that flag only filters by stored status and ignores the dependency graph, so it returns tasks whose blockers are still open and would claim work out of order. Verified against bd 0.49.0: with a two-task chain plus a blocked parent epic, `bd list --ready` returned all three while `bd ready` returned only the one unblocked task. When the result is empty, return null; no claimable task remains. Otherwise run `bd update <id> --claim` on the chosen id to atomically set its status to `in_progress` and its assignee to the current actor, then return that id. Use `bd blocked` when you need to explain to the user why nothing is claimable. |
| `close(taskId)` | Run `bd close <taskId>` to mark the task done. Record the short hash of the commit that implemented the task as well, per the commit-verification rules in `../conventions.md`; attach it with `bd update <taskId> --notes` when that flag exists on the installed version, and otherwise state the hash in the progress line. Verify the flag with `bd update --help` rather than assuming it. |
| `status()` | Run `bd count --type task --by-status --json` to get counts grouped by status (`open`, `in_progress`, `blocked`, `deferred`, `closed`) scoped to task-type items, excluding the parent epic created by `parentTask`. Compute this operation's open count as the sum of the `open`, `blocked`, and `deferred` buckets from that output, never the raw `open` bucket alone; a task with an open dependency reports as `blocked`, not `open`, and dropping it from the total would undercount pending work. Compute this operation's done count as the `closed` bucket. Run `bd list --type task --status in_progress --limit 1 --json` to identify the current in-progress task by id and title. When that second command returns no rows, report that no task is currently in progress. |
| `parentTask(issueRef)` | First try to fetch it: run `bd list -l "<issueRef>" --type epic --json` to get a candidate list, then filter those candidates client-side and keep only the row whose `external_ref` field equals `<issueRef>` exactly. Reuse that row's id when one is found this way. Never treat the first row of the raw `--title-contains` results as a match; `--title-contains` is a substring filter, so looking up `ONC-1` also returns `ONC-10`, and taking the first hit would silently attach new child tasks to the wrong parent epic. When no exact `external_ref` match exists, create it: run `bd create "<issueRef>" --type epic --external-ref "<issueRef>" --silent` and capture the printed id. Add a dependency edge making the parent depend on every child, so the parent cannot close until all children close and "no open children" becomes a machine-checkable rollup signal rather than an inference from the loop ending. Never add the reverse edge, from a child to the parent, which would deadlock both. |

## Notes

Beads exposes five status values: `open`, `in_progress`, `blocked`, `deferred`, and `closed`.
The memory contract only ever needs this adapter to move a task through `open` then `in_progress` then `closed`.
Never set `blocked` or `deferred` directly.
Beads does not rewrite a task's stored status when a dependency is added; an unmet dependency keeps the task at `open` while `bd ready` and `bd blocked` compute blocking from the dependency graph at query time.
That is why claim decisions must come from `bd ready` rather than from a status filter.
`bd update <id> --claim` resolves the current actor from `--actor`, then `$BD_ACTOR`, then git's `user.name`, then `$USER`, in that order.
Do not pass a separate `--assignee` flag unless multiple agents share one checkout and need distinct identities.
Prefer `--json` on every read command (`bd list`, `bd count`) when parsing output programmatically, since plain output is meant for a human terminal and can change formatting across versions.
`bd create` also accepts `--external-ref` and `--deps` directly at creation time; this adapter still issues them as separate `bd update` and `bd dep add` calls after `bd create` so each step maps to exactly one contract input and stays easy to verify independently.

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

