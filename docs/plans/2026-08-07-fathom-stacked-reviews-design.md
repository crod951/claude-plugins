# Fathom stacked reviews design

Date: 2026-08-07

## Problem

Fathom's `execute` skill drives one tracker issue to exactly one code review.
The breakdown at `execute/SKILL.md:73-97` plans three to seven sub-issues and commits one change per task, then `execute/SKILL.md:99-117` opens a single review covering all of them.

For a large issue that produces a review that is too big to review well.
The units of work are already sequential and independently verifiable, so they could reach reviewers as a stack of smaller reviews instead.

The forge contract anticipated this.
`forges.md:54` declares a `stackedReviews` capability with values `retarget`, `declared-dependency`, and `none`, and `forges.md:59-60` records that it is declared but drives no behavior, precisely so that adding it later would not mean revisiting every adapter file.
This design gives that capability its behavior.

Two forge models are already documented and both must work.
On a `retarget` forge such as GitHub, stacking is branch retargeting, and the forge retargets a dependent review automatically when its upstream merges.
On a `declared-dependency` forge, stacking is an explicit dependency plus a manually scoped commit range, with no automatic rebase.
On a `none` forge there is no forge-level stacking at all, but chaining the branches in git is still useful, so the agent targets the previous bundle's branch and declares the relationship in prose.

## Goals

Let one issue produce a short stack of dependent reviews when the work is large enough to warrant it.
Keep the existing single-review behavior as the default for every repository, forge, and issue that does not opt in, where opting in means writing `stacking: propose` into the repository's profile.
Make the split a decision the user can see, override, and pin, rather than something the agent does silently.

## Non-goals

No change to the `scaffold` skill.
Bundling is decided at `execute` time, after the sub-issues exist.

No size estimation before the breakdown.
The threshold reads the breakdown that already exists at step 8, rather than adding a second and less accurate estimator for the same question.

No stacks in the manual tier.
No new forge operation beyond one optional argument.

## Design

### 1. The bundle

A bundle is a contiguous run of the sub-issue dependency chain that `execute/SKILL.md:76` already builds.
Bundles inherit the chain's ordering rather than inventing an ordering of their own.
Each bundle maps to one branch and one review.

A bundle boundary may fall only where the planned units up to that point form a self-contained change: the units after the boundary build on the units before it and not the reverse, and the earlier units together deliver something that stands on its own rather than half of one thing.
When no such point exists there is no valid split, and the run proceeds as a single review.

This criterion is deliberately about the plan rather than about the repository.
The decision happens at breakdown time, before any of the work is written, so the agent cannot build the repository at a candidate boundary or run that bundle's tests: neither exists yet.
An earlier version of this design asked for exactly that, and it was undecidable at the only moment it could be applied.

So the agent is predicting reviewability, not verifying it, and two things catch a wrong prediction.
The confirmation stop shows the proposed boundaries to the user before anything is built, which is the cheap correction.
The per-bundle finish routine then reconciles and runs that bundle's tests for real, and its existing stop-and-hold fires when they fail, which is the expensive one.
A boundary that looked self-contained in the plan and turns out not to be is therefore caught before its review opens, rather than silently shipped.

### 2. When a split is proposed

Both conditions must hold before the agent proposes a split at all:

- the breakdown produced five or more sub-issues, and
- at least one valid cut point exists.

At most three bundles, and every bundle holds at least two sub-issues.
Both constraints apply together, so a five sub-issue breakdown can produce at most two bundles and a six sub-issue breakdown is the smallest that can produce three.
The cap is deliberate.
Sub-issues are sized commit-sized rather than review-sized, so one review per sub-issue would turn an ordinary issue into a stack of five to seven tiny reviews, and multiple reviews are a real cost for some teams and workflows.
An explicit user request may exceed the cap; the heuristic never does.

The manual tier does not propose a split.
A tier-3 forge (`forges.md:123-126`) cannot create reviews, so a three-bundle stack would become three separate sets of instructions for a human to follow by hand.
In tier 3 the agent says the split was not offered and why.
Tier 1 and tier 2 both propose.

This makes the `none` behavior in section 10 reachable only through a tier-1 repo-local adapter at `.fathom/forge.md` that creates real reviews but has no stacking model of its own.
No bundled adapter reaches it, because `generic-git.md` is the only bundled adapter declaring `none` and it is exactly what the manual tier runs on.

### 3. The split proposal stop

The stop fires at step 8, after the breakdown exists and before any task, commit, or review is created.
It shows the proposed bundles, which sub-issues fall in each, and the resolved forge's stacking behavior.

It goes on the skip list in `approval.md`, not the never-skip list.
It fires before any commit or review exists, so being wrong destroys nothing and misdirects nothing.
Bundle 1's branch does exist by then, because step 7 creates it before step 8 runs, but that branch is the one a single-review run needs anyway, so declining the split wastes nothing and leaves nothing to clean up.
That is the shape of every existing skip-list item, and unlike every never-skip item it destroys nothing and misdirects nothing.
In `ask` mode the run waits for an answer; in `auto` mode it applies the split and reports it.

`approval.md:69` requires every new stop to be classified explicitly, so this classification is recorded there alongside the existing entries.

### 4. The profile field

`.fathom/config.md` gains `stacking`, with two values.

`propose` means the agent may propose a split, with the approval mode deciding whether that is a question or a report.
`never` makes single-review behavior permanent for the repository, in the same spirit as `forge: none`.

`never` is the default, so an absent field means the repository never splits an issue and a repository opts in by writing `stacking: propose`.
A `propose` default would silently change behavior for every existing repository, most sharply for one running `approval: auto`, where the split is applied and reported rather than asked about, so its next large issue would arrive as a stack without anyone having asked for stacking.
An opt-in feature must not do that, which is what makes `never` the only default consistent with the goal above of preserving single-review behavior for every repository that does not opt in.

The field has two values rather than three on purpose.
An `ask` or `auto` value here would duplicate the `approval` field two lines above it in the same file, and two fields that can disagree about the same question is a defect waiting to be filed.

### 5. Branch naming

Bundle 1 keeps today's name unchanged, for example `feat/ONC-5-add-webhooks`.
Bundles 2 and 3 append their index: `feat/ONC-5-add-webhooks-2` and `-3`.

The pattern is predictable and matchable, which is what lets a resumed run find the stack it already built.

### 6. Ordering is enforced in data

The split is decided before any task is created, not after.
The bundling proposal and its confirmation happen once the sub-issues are planned and before the `createTask` calls, so every task is created with its final deps in a single pass.

This ordering is load-bearing rather than tidy.
`createTask` takes `deps` at creation, and the memory contract has exactly six operations with no way to add a dependency to a task that already exists.
Deciding the split after the tasks exist would leave the chain unbuildable, which would silently reinstate the out-of-order hazard this section exists to close.

When a split is confirmed, every task takes a dependency on its predecessor, so the whole issue becomes one sequential chain across bundles as well as within them.

`claimNext` returns the first open task whose deps are all closed, so a single chain means it structurally cannot hand out a later bundle's task while any earlier task is still open.
The implementation loop therefore needs no bundle-ordering logic of its own.

A boundary-only edge, from the first task of bundle k+1 to the last task of bundle k, is not sufficient and was rejected for that reason.
`execute/SKILL.md:76` sets `deps` so tasks chain sequentially "whenever order matters", which leaves tasks with no deps at all legal.
Such a task sitting anywhere in bundle k+1 other than its first position has all of its deps trivially closed, so `claimNext` would hand it out while bundle k was still open, and the branch chain would then be built on unfinished work.

Requiring the full chain is not a patch on that hole.
It makes the design's own premise explicit: section 1 defines a bundle as a contiguous run of the dependency chain, and if tasks are parallel-claimable there is no chain to cut into contiguous runs in the first place.
Full sequential chaining applies only when a split is confirmed; an ordinary single-review run keeps today's conditional chaining unchanged.

### 7. Durable record

Bundle membership is written at step 8 to exactly one place, the plan document's `Bundles` section.
It records, for each bundle, its index, the sub-issue refs and task ids it contains, and its branch name.
One record is deliberate: a second copy elsewhere under `.fathom/` would be a second version of the same fact, and two records of one fact can disagree.

This is required rather than optional.
`execute/SKILL.md:22` states that every run begins by reading durable state from the repository and the tracker, never from memory of a previous run.
A resumed run recovers the whole stack from this record.

### 8. Reviews open incrementally

Step 11 splits into a per-bundle finish routine and a smaller issue-level close.

The per-bundle routine runs when the last task of bundle k closes:

1. Reconcile bundle k's task count against the commits on branch k, and stop hard on a mismatch, as the single-review flow does today.
2. Call `resolveBase`. Bundle 1's base is the resolved base branch; bundle k's base is branch k-1.
3. Push branch k, unless the adapter declares `pushesForYou`.
4. Call `openReview`, then `publishReview`.
5. Record `- Review: <id> <url> (bundle k/N)` beneath that bundle's line in the plan document's `Bundles` section, which is the one place bundle records live.
6. When another bundle remains, create branch k+1 from branch k and continue the implementation loop. When bundle k was the last one, fall through to the issue-level close instead.

The issue-level close runs once, after the last bundle.
It closes the parent task, posts the completion comment listing all N reviews, and commits the run's task state onto branch N, which is the stack tip.

The `inReview` phase is applied once, when the first bundle's review publishes, and is not re-applied per bundle.
The issue genuinely is in review from that moment.

Opening incrementally rather than at the end avoids retroactive history surgery.
Building each bundle on the correct branch from the start is free, whereas committing everything to one branch and later cherry-picking commit ranges onto a chain of branches is the failure-prone path.
The bundle boundary is known at claim time, and `execute/SKILL.md:97` guarantees one commit per task, so no reconstruction is needed.

Opening incrementally also preserves the one-resumable-pass property stated in `execute/SKILL.md:20-21`.
Requiring one invocation per bundle would contradict it by design.

A useful side effect: when bundle 2 hits an unfixable test failure, bundle 1's review is already open and reviewable.

### 9. The closing keyword

`execute/SKILL.md:107` puts `Closes <ref>` in the review body for a Linear issue, or the task's URL for an Asana task.

In a stack that closing keyword appears in the last bundle's review only.
Earlier bundles reference the issue without a closing keyword and carry two additional lines: `Part k of N`, and `Depends on <previous review url>`.

Without this rule the first bundle's merge closes the issue while most of the work is still open.

That rule alone is not sufficient, because it only governs the forge's own keyword integration.
The merge-closer GitHub Action closes an issue by matching the merged branch name against records under `.fathom/`, so it never reads the keyword at all, and every bundle's branch is recorded there.
Under it, merging any bundle in any order closes the issue, and the next sweep then reads that issue as already complete and does nothing, making the early close permanent and silent.

So a stacked issue suppresses the merge-closer entirely and leaves closure to the sweep, which already waits for every bundle to report `merged`.
The run records a marker on the issue that tells the Action to take no action for it.

One mechanism closes a stacked issue, not two that disagree.
The cost is real and is stated at handoff: on a repository that relies on the Action for closure, a stacked issue now needs a later sweep run to reach `done`, where a single-review issue still closes on merge without one.

### 10. Forge contract change

`openReview` gains one optional fifth argument, `dependsOn`, holding the previous bundle's review id.
The other four operations are unchanged, and no operation is added.

Adapters key their behavior off their declared `stackedReviews` value:

| `stackedReviews` | Behavior |
| --- | --- |
| `retarget` | Ignore `dependsOn`. The `base` argument does the work, and the forge retargets on upstream merge. |
| `declared-dependency` | Pass `dependsOn` to the forge's dependency mechanism and scope the commit range. |
| `none` | Ignore `dependsOn`. The `base` argument gives git-level chaining, and the body's `Depends on` line carries the rest. Reachable only from a tier-1 repo-local adapter, per section 2. |

`forges.md:59-60` stops saying the capability is declared and unused.

### 11. The rebase obligation

After an upstream bundle merges, the remaining stack may need rebasing.

The test is forge-agnostic rather than capability-keyed: check whether the merged content is an ancestor of each remaining stack branch, and rebase only when it is not.

This is deliberately not keyed on `stackedReviews`.
A squash-merge on a `retarget` forge produces exactly the same problem as a merge on a `none` forge, because the squash commit is not an ancestor of the dependent branch and the dependent review then redisplays the upstream bundle's changes.
The ancestry check catches both cases with one rule, which is the evidence that it is the right check.

Rebasing pushes with `--force-with-lease`, never a bare force push.

### 12. The sweep

The done-on-merge sweep (`execute/SKILL.md:56`) reads every `- Review:` line recorded for the issue rather than one, and calls `getReviewState` on each.

- All bundles `merged`: move the issue to `done`, as today.
- Some merged and some open: do not close the issue. Report progress, for example `bundle 1/3 merged`, then run the ancestry check from section 11 and rebase the remaining branches bottom-up when needed.
- Any bundle `closed-unmerged`: fire the existing never-skip stop from `approval.md:48`, and name which bundles above it are now orphaned. Close nothing and rebase nothing.
- `reviewLookup: none`: the sweep is unavailable, exactly as today.

### 13. Failure handling

Three hold conditions are added, each matching existing precedent rather than introducing a new kind of stop.

| Condition | Behavior |
| --- | --- |
| `--force-with-lease` rejected during a stack rebase | Stop and hold. Someone else's commits are on that branch, and force-pushing over them is the discarding-someone's-changes hazard that `approval.md:46` already names. |
| Rebase conflict while restacking | Stop and hold, naming the conflicting files, exactly as `execute/SKILL.md:72` does for a base-branch update conflict. |
| Unfixable test failure in bundle k | The existing stop, with an added reporting requirement: name which bundles have open reviews and which were never built. |

### 14. Resume

A re-invoked run recovers the stack from the record in `.fathom/`, matches existing branches by the naming pattern from section 5, and reads the recorded review ids.

The existing rule at `execute/SKILL.md:108`, skip when a review already exists for the branch and reuse that one, becomes per-bundle.
A resumed run must never open a second review for a bundle that already has one.

### 15. Tier drop mid-stack

When a later run's `verifyForge()` fails, bundles whose reviews are already open stay as they are, and the remaining bundles are handed off manually per `forges.md:114-116`.

Say this plainly at handoff, including the consequence already documented in `forges.md:149-158`: no later run will move the issue to `done` on its own, so closing it becomes a manual step.

## Files touched

All changes are prose in skill files. No code changes.

- `skills/fathom-shared/forges.md`: the `dependsOn` argument, the per-capability behavior table, removal of the declared-and-unused paragraph, and the tier-3 no-stack rule.
- `skills/fathom-shared/forges/github.md`: stacking behavior for `retarget`, including the squash-merge caveat.
- `skills/fathom-shared/forges/generic-git.md`: stacking behavior for `none`.
- `skills/fathom-shared/forges/TEMPLATE.md`: guidance for an adapter author implementing `dependsOn`.
- `skills/fathom-shared/approval.md`: the split proposal on the skip list, and the `stacking: propose | never` profile field.
- `skills/fathom-shared/conventions.md`: bundle membership in the plan document, and per-bundle commit reconciliation.
- `skills/fathom-shared/memory.md`: the cross-bundle dependency edge, where the backends need it spelled out.
- `skills/execute/SKILL.md`: steps 7, 8, 10, and 11, plus the sweep in step 2.

## Verification

This repository has no unit tests, so verification is what it already runs:

- `bin/scan-skills.sh` clean against `.skillspector-baseline.yaml`, with any new baseline entry carrying a written reason.
- `bin/sync-versions.sh` for version consistency.
- The `.github/workflows/skillspector.yml` CI workflow.

Internal consistency is checked by reading the changed files together: every `execute/SKILL.md` step that references a review must be unambiguous about whether it means one review or one bundle's review.

## Decisions and rationale

| Decision | Alternative rejected | Why |
| --- | --- | --- |
| Bundles of sub-issues | One review per sub-issue | Sub-issues are sized commit-sized by `execute/SKILL.md:76`, so one review each produces a five to seven review stack of trivial reviews. |
| Single review stays the default | Stack whenever possible | Keeps every existing repository, forge, and tier behaving exactly as today unless something opts in. |
| Agent proposes, user confirms | Agent decides silently | The structural shape of a change's review is a judgment call with real cost to reviewers. |
| Skip-list stop | Never-skip stop | It fires before any branch, commit, or review exists, so being wrong costs nothing. |
| `stacking` with two values | `stacking` with `ask`, `auto`, and `never` | Three values would duplicate the `approval` field in the same profile and could disagree with it. |
| Incremental review opening | All reviews at the end | Opening at the end requires cherry-picking commit ranges onto a chain of branches after the fact. |
| Full sequential chain when stacked | A single edge at each bundle boundary | A boundary edge leaves a dep-free task inside a later bundle claimable while an earlier bundle is open, so it does not deliver the ordering it claims. |
| Ancestry check for rebase | Rebase keyed on `stackedReviews` | A squash-merge on a `retarget` forge has the same problem as a merge on a `none` forge, and one rule covers both. |
| All bundles merged closes the issue | Top of stack merged closes it | Cheaper, but wrong when someone merges out of order or squashes the stack by hand. |
| No stacks in tier 3 | Stacks with N manual handoffs | Three sets of hand-open-this instructions is worse than one review. |
