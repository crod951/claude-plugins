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
| `claimNext()` | Run `bd list --ready --type task --sort created --limit 1 --json` to find the oldest still-open task with no open blockers. `--ready` already restricts results to `status=open` with every dependency closed, so no manual blocked/unblocked filtering is needed here, and `--type task` excludes the parent epic created by `parentTask` from consideration. When the result is empty, return null; no open task remains. Otherwise run `bd update <id> --claim` on the returned id to atomically set its status to `in_progress` and its assignee to the current actor, then return that id. If the installed version's default sort order surfaces the newest task first instead of the oldest, add `-r`/`--reverse` to the `bd list` call above so the oldest ready task is claimed first. |
| `close(taskId)` | Run `bd close <taskId>` to mark the task done. |
| `status()` | Run `bd count --type task --by-status --json` to get counts grouped by status (`open`, `in_progress`, `blocked`, `deferred`, `closed`) scoped to task-type items, excluding the parent epic created by `parentTask`. Compute this operation's open count as the sum of the `open`, `blocked`, and `deferred` buckets from that output, never the raw `open` bucket alone; a task with an open dependency reports as `blocked`, not `open`, and dropping it from the total would undercount pending work. Compute this operation's done count as the `closed` bucket. Run `bd list --type task --status in_progress --limit 1 --json` to identify the current in-progress task by id and title. When that second command returns no rows, report that no task is currently in progress. |
| `parentTask(issueRef)` | First try to fetch it: run `bd list -l "<issueRef>" --type epic --json` to get a candidate list, then filter those candidates client-side and keep only the row whose `external_ref` field equals `<issueRef>` exactly. Reuse that row's id when one is found this way. Never treat the first row of the raw `--title-contains` results as a match; `--title-contains` is a substring filter, so looking up `ONC-1` also returns `ONC-10`, and taking the first hit would silently attach new child tasks to the wrong parent epic. When no exact `external_ref` match exists, create it: run `bd create "<issueRef>" --type epic --external-ref "<issueRef>" --silent` and capture the printed id. Add a dependency edge making the parent depend on every child, so the parent cannot close until all children close and "no open children" becomes a machine-checkable rollup signal rather than an inference from the loop ending. Never add the reverse edge, from a child to the parent, which would deadlock both. |

## Notes

Beads exposes five status values: `open`, `in_progress`, `blocked`, `deferred`, and `closed`.
The memory contract only ever needs this adapter to move a task through `open` then `in_progress` then `closed`.
Never set `blocked` or `deferred` directly; beads derives `blocked` itself from open dependencies added through `bd dep add`.
`bd update <id> --claim` resolves the current actor from `--actor`, then `$BD_ACTOR`, then git's `user.name`, then `$USER`, in that order.
Do not pass a separate `--assignee` flag unless multiple agents share one checkout and need distinct identities.
Prefer `--json` on every read command (`bd list`, `bd count`) when parsing output programmatically, since plain output is meant for a human terminal and can change formatting across versions.
`bd create` also accepts `--external-ref` and `--deps` directly at creation time; this adapter still issues them as separate `bd update` and `bd dep add` calls after `bd create` so each step maps to exactly one contract input and stays easy to verify independently.

## Repository hygiene

Beads keeps its durable shared state in the JSONL export inside `.beads/`.
Everything else it writes there is local runtime state that must never be committed: the SQLite database, its write-ahead and shared-memory files, the daemon log, the daemon pid and lock, the sync-state file, the metadata file, and the local version marker.

Right after `init` creates `.beads/`, ensure the repository's `.gitignore` excludes those runtime files while leaving the JSONL export tracked, and commit that `.gitignore` change together with the init commit.

```gitignore
.beads/*.db
.beads/*.db-wal
.beads/*.db-shm
.beads/daemon.log
.beads/daemon.pid
.beads/daemon.lock
.beads/last-touched
.beads/sync-state.json
.beads/metadata.json
.beads/.local_version
```

Without this, the working tree stays permanently dirty, `git checkout` between branches fails because the database and log files would be overwritten, and later runs trip over uncommitted database churn that has nothing to do with their own work.

Long-lived parallel branches that both write task state will conflict on the JSONL export.
Beads installs a `.gitattributes` merge driver to handle exactly that, so keep that file when beads creates it.
Resolve a JSONL conflict by letting beads regenerate the export from its database rather than hand-merging the JSON lines.
A hand-edited `.gitignore` can also conflict when two branches add the same runtime-file rules independently; resolve that by keeping one deduplicated copy of the rules, never both copies.
