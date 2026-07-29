# Working conventions

Cross-cutting rules for staging, commits, the plan document, and progress reporting.
These apply to every run regardless of tracker or task-memory backend.

## Staging safety

Never stage a file that could carry a secret.
Treat these as always forbidden: environment files such as `.env` and any `.env.*` variant, anything whose name contains `credential` or `secret`, private keys and certificates such as `*.pem` and `*.key`, and framework credential stores such as `config/master.key` and `config/credentials.yml.enc`.
When a change genuinely requires touching one of those paths, stop and ask the user to stage it themselves.

Never stage with a blanket pattern.
Do not use `git add -A`, `git add .`, or `git add --all`, because they sweep in unrelated working-tree churn, editor droppings, and local runtime files that no one reviewed.
Stage the specific files this task changed, by path.

Before committing, list what is staged and confirm every path belongs to the task at hand.
When something unexpected appears, unstage it rather than committing it and cleaning up later.

## Commit messages

Use a conventional-commit subject scoped by the issue ref: `type(<issue-ref>): summary`.
Omit the scope only when the work genuinely has no issue.

Pick exactly one type, choosing the most specific that fits:

| Type | Use for |
| --- | --- |
| `feat` | new user-facing behavior |
| `fix` | a bug fix |
| `refactor` | restructuring with no behavior change |
| `test` | tests only |
| `docs` | documentation only |
| `chore` | build, tooling, dependencies, task-state bookkeeping |
| `perf` | a performance improvement |
| `style` | formatting or whitespace only |

When torn between `feat` and `refactor`, choose `feat` if any user-visible behavior changed.
When torn between `fix` and `feat`, choose `fix` if the change restores intended behavior rather than adding to it.

Write the summary in lowercase imperative mood, describing the change rather than the activity.
Keep the subject under 72 characters, with no trailing period.
Name the task in the body so the commit ties back to task memory.

## The plan document

During breakdown, write a human-readable plan for the issue at `.workbench/plans/<ISSUE-REF>.md`, and commit it with the breakdown.
This document is a reference artifact for people, never resume state; task status always lives in the resolved memory backend.

Include these sections:

- **Issue** - the title, the tracker URL, the ref, and the branch.
- **Issue description** - what the issue asks for, in your own words.
- **Codebase context** - the files, modules, and existing patterns this work touches, with paths.
- **Implementation approach** - how the change will be made, including anything deliberately out of scope.
- **Tasks** - the planned units of work with their sub-issue links.
- **Testing strategy** - which tests will prove the work, and which existing tests could regress.
- **Notes** - open questions, risks, and decisions taken during the run.

Keep it current as the run proceeds when something material changes, but do not mirror task status into it.

## Commit verification

A task's close must carry the hash of the commit that implemented it.
Read the short hash from the repository after committing, then record it with the close: in checklist mode append it to that task's line, and in beads attach it to the task using whatever note or comment field the backend offers.
When a backend cannot store it, state the hash in the progress line instead.

The point is structural rather than cosmetic.
Recording a real hash is impossible when no commit was made, so this converts a rule that can be narrated into a step that fails loudly when skipped.
A progress line describes repository state, so never name a commit that does not exist in the log.

Reconcile before finishing.
Count the task commits on the branch and compare that count to the number of tasks closed for this issue.
When the counts disagree, stop and report the discrepancy rather than opening a pull request: either a commit is missing, or tasks were combined into one commit, and both contradict the one-commit-per-task rule.

## Progress reporting

After each task closes, print one line so a long autonomous run stays legible: the task position in the queue, its id, the commit subject, the test result, and how many tasks remain.
Report the resolved tracker and memory backend once at the start of the run, and state the backend explicitly whenever it differs from what other open issues in this repository are using.
