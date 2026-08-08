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
This document is a reference artifact for people, and it never carries task status; status always lives in the resolved memory backend, so nothing here is ever consulted to learn what is done.
It does carry structure, which is a different thing: the branch, the review ids, and the bundles of a stacked issue are recorded here, and a resumed run reads them back rather than remembering them from a previous invocation.
`memory.md` draws the same line, and it is what keeps this from being dual truth: structure is decided once and does not change as the work proceeds, while status changes with every task and lives in exactly one place.

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
  Add a `- Review: pending (bundle k/N)` marker beneath a bundle before its review is attempted, then replace that marker with a `- Review: <id> <url> (bundle k/N)` line once its review exists.
  The suffix is redundant with the nesting on purpose: the sweep reads these lines individually, and a self-describing record survives being read out of its surrounding context.
  The marker means only that a run reached the point of calling `openReview` for that bundle: it is committed before the call, so the call may or may not have started and a review may or may not exist.
  Its job is to force the next run to look the review up rather than to prove that any review was created.
  It names no id, so nothing can be looked up from the marker itself, and every reader collecting review ids treats a bundle carrying only the marker as carrying no record at all.
  The done-on-merge sweep therefore counts such a bundle among the missing records and leaves the whole issue undecided, and `execute` holds on it rather than opening a review that may duplicate one.
  What the marker separates is a bundle no run has ever tried to open a review for, which carries no line at all, from a bundle where a review may exist and no record names it, which carries the marker.
  Branch absence cannot make that distinction, because a forge retains a review after its head branch is deleted, so a bundle branch deleted or reused before its record was durable leaves a review that no branch and no record names; that is why the marker is written ahead of the call rather than inferred afterwards.
  When the lookup cannot settle whether a review exists, the run holds and reports the marker, and the user confirms whether one exists.
  Record a confirmation that none exists by replacing that bundle's marker with a `- Review: none confirmed (bundle k/N)` line, committed and pushed on that bundle's branch as the same kind of bookkeeping commit, so the next run opens that bundle's review instead of holding again.
  Every reader that treats the bare marker as no record treats a `none confirmed` line the same way, since neither names an id.
  A hold that recorded nothing would stop every later run identically, which is why the confirmation lands in this section rather than staying in the conversation that produced it.
  Each of those lines, the marker included, is committed and pushed as soon as it is written rather than riding the run's final closing commit, so that both the intent and the review id are durable and visible from another clone the moment each is written; `execute` describes exactly where in its per-bundle routine that happens.
  Each one lands on its own bundle's branch, though, because that is the branch the run is on when it writes the line.
  So a checkout of the base branch carries the records of the bundles that have already merged into it and none of the records above them, and reading only what that checkout holds would judge a three-bundle stack on one bundle's record.
  The branch name on each `- Bundle` line is what makes the rest reachable: the done-on-merge sweep fetches every branch named in this section and reads that branch's own copy of this document to collect the `- Review:` lines it cannot see locally, as `trackers.md` describes.
  Those branch names are therefore load-bearing for the sweep as well as for a resumed run, and a bundle line without one leaves that bundle's record unreachable.
  Collecting the records this way is what keeps them in one place: the alternative is mirroring every review id into a second store that the sweep can read directly, and two records of the same fact can disagree, while a fetch is read-only git work that needs no write anywhere.
  This section is the durable record a resumed run reads to recover the stack, so write it when the split is confirmed rather than when the first review opens.
- **Merge-closer** - present only when this issue was split into a stack, and omitted entirely otherwise.
  One line reading `- Merge-closer: suppressed`, written when the split is confirmed, alongside the `Bundles` section.
  The merge-closer Action matches a merged branch against the records under `.fathom/` and knows nothing about stacks, and every bundle's branch is recorded there, so without this line the first bundle to merge closes the whole issue while most of the work is still open and unreviewed.
  That close is also permanent and silent, because the next sweep reads the issue as already complete and does nothing.
  The Action reads this line and takes no action for the issue, which leaves closure to the sweep, and the sweep already waits for every bundle to report merged.
  One mechanism closes a stacked issue rather than two that disagree.
- **Finalization** - one line reading `- Finalization: complete`, absent until every one of the issue's closing actions has run.
  The last of those actions writes it, so it rides the run's final closing commit and becomes durable at the same moment the completed task state does.
  This is the one durable record that an issue's one-time closing actions have happened, and `execute` consults it before finalizing and stops immediately when it is present.
  A stacked issue needs that: its last bundle finalizes the issue directly as it finishes, and the implementation loop then drains and reaches the finalizing step again, so without one recorded fact to consult the closing actions can run twice.
  This is not task status and does not belong in the memory backend, which knows which tasks are closed and nothing about whether the completion comment was posted or the closing commit pushed.
  It is the same kind of line as `Merge-closer` above: a fact about this issue that another mechanism reads later.
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
A task commit is one whose subject is scoped to this issue's ref and which implements a task; the breakdown commit, every plan document commit including the per-bundle one that records a bundle's review id, and any task-state bookkeeping commit are not task commits.
Those bookkeeping commits are recognizable rather than a matter of judgment: each is typed `chore`, touches only records under `.fathom/`, and names no task, so none of them can be counted as the commit that implemented one.
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

`forges/github.md` forbids encoding a stack dependency a second way, and this body line is not that.
The `Depends on <url>` line in a review body is prose for a human reviewer and carries no machine meaning, so it is not a second representation of the dependency; the prohibition is on machine-readable representations such as a label or an extra API call.
The machine-readable representation is whatever the resolved forge declares: the `dependsOn` argument to `openReview` on a forge with a dependency mechanism of its own, and the base branch alone on a `retarget` forge, whose adapter ignores that argument.

Earlier bundles still name the issue for context, as a plain link with no closing keyword.
The distinction is between referencing an issue and instructing the forge to close it, and only the last bundle does the second one.
