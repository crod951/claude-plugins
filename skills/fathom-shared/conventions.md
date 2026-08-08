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

During breakdown, write a human-readable plan for the issue at `.fathom/plans/<ISSUE-REF>.md`, and commit it with the breakdown.
This document is a reference artifact for people, never resume state; task status always lives in the resolved memory backend.

Include these sections:

- **Issue** - the title, the tracker URL, the ref, and the branch, each on its own labeled line.
  Use these exact labels: `- Issue: <tracker url>`, `- Ref: <issue ref>`, and `- Branch: <branch>`.
  The labels are load-bearing rather than cosmetic.
  The merge-closer Action finds this issue's record by matching the `Branch` line exactly, then reads the tracker id only from a line labeled `Tracker`, `Issue`, or `Ref`.
  A label that reads more naturally, such as `Issue link` or `Tracker URL`, matches neither, and the Action then exits successfully having closed nothing.
  This matters most on a beads-backed issue, where the plan document is the only record the Action has, since no checklist file exists.
- **Issue description** - what the issue asks for, in your own words.
- **Codebase context** - the files, modules, and existing patterns this work touches, with paths.
- **Implementation approach** - how the change will be made, including anything deliberately out of scope.
- **Tasks** - the planned units of work with their sub-issue links.
- **Bundles** - present only when this issue was split into a stack, and omitted entirely otherwise.
  One line per bundle, in stack order, each reading `- Bundle <k>/<N>: <branch> - <sub-issue refs, comma separated>`.
  Add a `- Review: <id> <url>` line beneath a bundle once its review exists.
  This section is the durable record a resumed run reads to recover the stack, so write it when the split is confirmed rather than when the first review opens.
- **Testing strategy** - which tests will prove the work, and which existing tests could regress.
- **Notes** - open questions, risks, and decisions taken during the run.

Keep it current as the run proceeds when something material changes, but do not mirror task status into it.

## Commit verification

A task's close must carry the hash of the commit that implemented it.
Read the short hash from the repository after committing, then record it with the close.
In beads, attach it to the task with the backend's note field, which is a separate store and needs no further commit.
In checklist mode the hash belongs on the task's line, but a file staged into a commit cannot contain that commit's own final hash, and amending the commit to add it changes the hash again, leaving a stale value; so write the hash into the file after committing and let that edit ride the next commit that touches the file, which is the next task's close or the run's final closing commit, while stating the hash in the progress line immediately.
When a backend cannot store it, state the hash in the progress line instead.

The point is structural rather than cosmetic.
Recording a real hash is impossible when no commit was made, so this converts a rule that can be narrated into a step that fails loudly when skipped.
A progress line describes repository state, so never name a commit that does not exist in the log.

Reconcile before finishing.
A task commit is one whose subject is scoped to this issue's ref and which implements a task; the breakdown commit, the plan document commit, and any task-state bookkeeping commit are not task commits.
Count them over the range from the resolved base branch to the current head, not over all history, since a branch inherits its base's commits.
Compare that count to the number of tasks closed for this issue.
Check the recorded hashes as well: every hash recorded at close must name a commit inside that same range, and each closed task's hash must be distinct, which catches a mismatch that subject-line counting can misclassify.
When the counts disagree, stop and report the discrepancy rather than opening a review: either a commit is missing, or tasks were combined into one commit, and both contradict the one-commit-per-task rule.

When the issue was split into a stack, reconcile once per bundle rather than once per issue, and do it before that bundle's review opens rather than at the end of the run.
Count over the range from that bundle's own base to that bundle's head: the resolved base branch for bundle 1, and branch k-1 for bundle k.
Compare that count to the number of tasks closed for that bundle only.
A stack-wide count over the whole range would pass even when one bundle carried another bundle's commits, which is exactly the mistake the check exists to catch.
Stop on a mismatch the same way, and do not open that bundle's review.

This check guards a hazard that is universal across forges rather than specific to any one of them: every forge reviews committed work only, so anything left staged or uncommitted is silently absent from the review, with no error raised anywhere.

## Review test plan

Give every review a test plan with the same shape, so a reviewer reads the same structure each time.

State the command a reviewer runs, in a fenced block.
State the observed result as counts, for example how many tests passed and how the total changed.
State what the new tests cover, one line per behavior rather than one line per file.
State anything deliberately not covered, and why.

Never describe a test plan you did not run.
When the project cannot run tests at all, say that plainly here rather than leaving the section implying verification happened.

## Progress reporting

After each task closes, print one line so a long autonomous run stays legible: the task position in the queue, its id, the commit subject, the test result, and how many tasks remain.
Report the resolved tracker and memory backend once at the start of the run, and state the backend explicitly whenever it differs from what other open issues in this repository are using.

## Review bodies in a stack

When one issue produced a stack of reviews, the issue-closing reference goes in the last bundle's review body only.

`execute` puts `Closes <ref>` in the body for a Linear issue, or the task's URL for an Asana task, and both are read by the forge's tracker integration on merge.
Repeating either in every bundle means the first bundle's merge closes the issue while most of the work is still open and unreviewed.

Every bundle's body carries two additional lines instead:

- `Part <k> of <N>` so a reviewer knows this diff is a slice rather than the whole change.
- `Depends on <previous review url>`, omitted for bundle 1, which depends on nothing.

Earlier bundles still name the issue for context, as a plain link with no closing keyword.
The distinction is between referencing an issue and instructing the forge to close it, and only the last bundle does the second one.
