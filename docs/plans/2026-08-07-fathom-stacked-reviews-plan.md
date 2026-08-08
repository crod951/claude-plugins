# Fathom stacked reviews implementation plan

## Status: completed historical record

This document is a historical execution record of how the stacked-reviews change was implemented.
Every task in it has been completed.
It is a point-in-time record rather than current guidance, and it is deliberately left as it was written rather than rewritten to track later corrections.

The skill files under `skills/` are authoritative wherever this document disagrees with them.
Several skill files have been corrected past what this plan describes, so a difference between the two means the skill file is right and this record is simply older.

The current specification is `docs/plans/2026-08-07-fathom-stacked-reviews-design.md`.
Read that document, and the skill files themselves, for how the feature behaves today.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the reserved `stackedReviews` forge capability real behavior, so one tracker issue can produce a short stack of dependent code reviews when its breakdown is large enough, with the split proposed at breakdown time.

**Architecture:** Every change is prose in skill markdown files that an agent reads at runtime. There is no source code, no test framework, and no build. The contract files (`forges.md`, `approval.md`, `conventions.md`, `memory.md`) are edited before the adapter files that implement them and before `execute/SKILL.md`, which consumes all of them, so each task lands on top of vocabulary that already exists.

**Tech Stack:** Markdown skill files under `skills/`. Verification is NVIDIA SkillSpector v2.5.0 via `bin/scan-skills.sh`, version propagation via `bin/sync-versions.sh`, and grep-based cross-file consistency checks.

**Design document:** `docs/plans/2026-08-07-fathom-stacked-reviews-design.md`

## Global constraints

- Never use the em dash character. Use a plain hyphen instead. This applies to every file you touch.
- Put each full sentence on its own physical line in markdown prose. Preserve normal markdown structure otherwise.
- Never write `TODO`, `TBD`, or a placeholder into a skill file. These files are read by an agent at runtime, and a placeholder becomes agent behavior.
- Never stage with `git add -A`, `git add .`, or `git add --all`. Stage the exact paths the task changed. This is the repository's own rule, recorded in `skills/fathom-shared/conventions.md:12-14`.
- Commit subjects follow `type(scope): summary`, lowercase imperative, under 72 characters, no trailing period. Scope is `fathom`.
- Do not add a co-author trailer to any commit.
- Work on the branch `feat/stacked-reviews`, which already exists and already holds the design commit.
- The three values of `stackedReviews` are exactly `retarget`, `declared-dependency`, and `none`. Never invent a fourth.
- The two values of the new `stacking` profile field are exactly `propose` and `never`.
- The bundle cap is at most 3 bundles, each holding at least 2 sub-issues, proposed only when the breakdown has 5 or more sub-issues.

## Verification model for this repository

This repository has no unit tests and no test framework, so the ordinary write-a-failing-test cycle does not apply. Do not invent one. Each task below instead ends with two real checks and a commit:

1. **Scanner check.** `bin/scan-skills.sh` runs NVIDIA SkillSpector against every skill and exits non-zero on any finding not suppressed in `.skillspector-baseline.yaml`. SkillSpector v2.5.0 is already installed at `~/.local/bin/skillspector` and matches the SHA pinned in `.github/workflows/skillspector.yml`. This checks for prompt-injection and unsafe-instruction patterns. It does **not** check that your prose is correct, which is why every task also has check 2.
2. **Consistency check.** A concrete `grep` whose expected output is stated in the step. These exist because the real failure mode for this change is two skill files disagreeing about the same rule, and no tool in this repository catches that.

If `bin/scan-skills.sh` reports a new finding, do not add a baseline suppression to silence it without reading the finding first. A suppression requires a written reason in `.skillspector-baseline.yaml`, and the existing entries show the expected format.

---

## Task 1: Correct the design document, then change the forge contract

The design document has one ambiguity found while reading the adapter files, and it must be resolved before any adapter is written against it.

The design says a `stackedReviews: none` forge stacks branches in git and declares the dependency in prose. It also says the manual tier never proposes a split. But `generic-git.md` is the only bundled adapter declaring `none`, and `forges.md:124` makes generic-git exactly what the manual tier runs on, so those two rules together mean the `none` path is unreachable through any bundled adapter.

The `none` path is still correct and still needed, but only for a **tier-1 repo-local adapter** at `.fathom/forge.md` that creates real reviews and has no stacking model of its own. Making that explicit is the first step of this task.

**Files:**
- Modify: `docs/plans/2026-08-07-fathom-stacked-reviews-design.md` (sections 2 and 10)
- Modify: `skills/fathom-shared/forges.md:53-60` (capability table row and the reserved paragraph)
- Modify: `skills/fathom-shared/forges.md:17` (the `openReview` contract row)
- Modify: `skills/fathom-shared/forges.md:105-129` (capability tiers, tier-3 rule)

**Interfaces:**
- Produces: the argument name `dependsOn`, the phrase `stackedReviews`, and the three behavior rows that Task 2's adapter files implement verbatim.
- Produces: the tier-3 no-stack rule that Task 6 reads when deciding whether to propose a split.

- [ ] **Step 1: Amend the design document's section 2**

In `docs/plans/2026-08-07-fathom-stacked-reviews-design.md`, find the paragraph in section 3 (`When a split is proposed`) that begins "The manual tier does not propose a split." Append these two lines to that paragraph:

```markdown
This makes the `none` behavior in section 10 reachable only through a tier-1 repo-local adapter at `.fathom/forge.md` that creates real reviews but has no stacking model of its own.
No bundled adapter reaches it, because `generic-git.md` is the only bundled adapter declaring `none` and it is exactly what the manual tier runs on.
```

- [ ] **Step 2: Amend the design document's section 10**

In the same file, in section 10, replace the `none` row of the behavior table with this row:

```markdown
| `none` | Ignore `dependsOn`. The `base` argument gives git-level chaining, and the body's `Depends on` line carries the rest. Reachable only from a tier-1 repo-local adapter, per section 2. |
```

- [ ] **Step 3: Change the `openReview` row in the contract table**

In `skills/fathom-shared/forges.md`, line 17 currently reads:

```markdown
| `openReview(branch, base, title, body)` | Create the review for a branch against a base. Return a stable review id and the review's URL - or, on a forge where no review can be created, the manual-handoff result defined below. |
```

Replace it with:

```markdown
| `openReview(branch, base, title, body, dependsOn?)` | Create the review for a branch against a base. Return a stable review id and the review's URL - or, on a forge where no review can be created, the manual-handoff result defined below. `dependsOn` is optional and carries the review id this one is stacked on; it is absent for a standalone review and for the first bundle of a stack. |
```

- [ ] **Step 4: Replace the `stackedReviews` capability row**

In the same file, line 54 currently reads:

```markdown
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | Reserved. No behavior depends on it yet. |
```

Replace it with:

```markdown
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | How this adapter expresses that one review is stacked on another, in `openReview`. |
```

- [ ] **Step 5: Replace the reserved paragraph with the behavior rules**

In the same file, lines 59-60 currently read:

```markdown
`stackedReviews` is declared and unused.
It is recorded now because the difference is real - `retarget` describes a forge where stacking is branch retargeting with automatic retarget when the upstream merges, and `declared-dependency` describes one where stacking is an explicit dependency plus a manually scoped commit range with no auto-rebase - and because adding a capability key later means revisiting every adapter file.
```

Replace both lines with:

```markdown
`stackedReviews` decides what an adapter does with `openReview`'s optional `dependsOn` argument.

| Value | What `openReview` does with `dependsOn` |
| --- | --- |
| `retarget` | Ignore it. Passing the previous bundle's branch as `base` is the whole mechanism, and the forge retargets the dependent review automatically when its upstream merges. |
| `declared-dependency` | Pass it to the forge's own dependency mechanism, and scope the review's commit range to this bundle's commits only. Nothing is retargeted automatically. |
| `none` | Ignore it. The `base` argument still chains the branches in git, and the calling skill writes the relationship into the review body in prose. |

A `none` adapter is still stackable in the only sense that matters to a reader: the branches chain, each review shows one bundle's diff, and the body says what it depends on.
What it lacks is any forge-side record of the relationship, so nothing retargets and nothing warns when the stack is merged out of order.

Only a repo-local adapter reaches the `none` row in practice.
The one bundled adapter that declares `none` is `generic-git.md`, which is what the manual tier runs on, and the manual tier never proposes a stack.
```

- [ ] **Step 6: Add the tier-3 no-stack rule**

In the same file, in the `Capability tiers` section, find the paragraph beginning "**Tier 3, manual.**" and append this line to the end of that paragraph:

```markdown
A stack is never proposed in this tier: with no review object to create, a three-bundle stack would become three separate sets of open-this-by-hand instructions, which is worse for the user than one review.
```

- [ ] **Step 7: Run the consistency check**

Run:

```bash
grep -n "declared and unused\|Reserved. No behavior" skills/fathom-shared/forges.md
```

Expected: no output, exit code 1. The reserved language is gone.

Run:

```bash
grep -c "dependsOn" skills/fathom-shared/forges.md
```

Expected: `3`. `grep -c` counts matching lines rather than occurrences, and Step 5's prose deliberately says "it" rather than repeating the argument name in each behavior row, so three lines carry it: the contract row, the sentence introducing the behavior table, and the table's own header.

If this returns anything other than 3, report the number rather than dropping the check. A silently omitted verification is worse than a failed one.

- [ ] **Step 8: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0, no non-suppressed findings.

- [ ] **Step 9: Commit**

```bash
git add docs/plans/2026-08-07-fathom-stacked-reviews-design.md skills/fathom-shared/forges.md
git commit -m "feat(fathom): give stackedReviews behavior in the forge contract"
```

---

## Task 2: Implement the capability in the three adapter files

**Files:**
- Modify: `skills/fathom-shared/forges/github.md:21` and `:53-68`
- Modify: `skills/fathom-shared/forges/generic-git.md:20-26` and `:46`
- Modify: `skills/fathom-shared/forges/TEMPLATE.md:40` and `:71-83`

**Interfaces:**
- Consumes: the `dependsOn` argument and the three-row behavior table from Task 1.
- Produces: the squash-merge caveat that Task 7's rebase rule cites.

- [ ] **Step 1: Update the GitHub adapter's capability note**

In `skills/fathom-shared/forges/github.md`, line 21 currently reads:

```markdown
`stackedReviews` is `retarget` because GitHub stacking is branch retargeting, and GitHub retargets a dependent pull request automatically when its upstream merges.
```

Append these three lines directly after it:

```markdown
That automatic retarget is real but partial, and the gap matters to the caller.
When the upstream pull request is **squash-merged**, the squash commit is not an ancestor of the dependent branch, so the dependent pull request retargets to the base and then redisplays the upstream bundle's changes as if they were new.
The dependent branch has to be rebased for its diff to be honest again, which is why the calling skill's rebase rule is keyed on commit ancestry rather than on this capability value.
```

- [ ] **Step 2: Update the GitHub adapter's `openReview` heading and body**

In the same file, change the section heading on line 53 from:

```markdown
## `openReview(branch, base, title, body)`
```

to:

```markdown
## `openReview(branch, base, title, body, dependsOn?)`
```

Then, directly after the paragraph beginning "Return the pull request number as the review id", insert:

```markdown
Ignore `dependsOn` when it is supplied.
`stackedReviews` is `retarget`, so passing the previous bundle's branch as `base` is the entire mechanism, and GitHub needs no separate dependency declaration.
Never encode the dependency a second way, such as by adding a label or an extra API call; the base branch already carries it and a second representation can disagree with the first.
```

- [ ] **Step 3: Update the generic-git adapter**

In `skills/fathom-shared/forges/generic-git.md`, find the paragraph starting "`reviewLookup: none` is the consequential one." and insert this paragraph directly before it:

```markdown
`stackedReviews: none` is never exercised through this adapter.
This adapter is what the manual tier runs on, and `../forges.md` states that the manual tier never proposes a stack, so `openReview` here is only ever called for a standalone review.
The value is declared truthfully rather than left absent, because a repo-local adapter author reading this file as the minimum viable example needs to see every capability filled in.
```

Then change the section heading on line 46 from:

```markdown
## `openReview(branch, base, title, body)`
```

to:

```markdown
## `openReview(branch, base, title, body, dependsOn?)`
```

Then append this line to the end of the paragraph beginning "There is no review to create":

```markdown
`dependsOn` is ignored here for the same reason the id is absent: there is no review object to attach a dependency to.
```

- [ ] **Step 4: Update the adapter template's guidance**

In `skills/fathom-shared/forges/TEMPLATE.md`, line 40 currently reads:

```markdown
> `stackedReviews` - declared but currently unused. `retarget` if stacking means retargeting a branch; `declared-dependency` if it means declaring a dependency plus a commit range.
```

Replace it with:

```markdown
> `stackedReviews` - how your forge expresses that one review is stacked on another, which decides what your `openReview` does with the optional `dependsOn` argument. `retarget` if stacking is just pointing a review at the previous branch, and your forge retargets automatically when the upstream merges. `declared-dependency` if stacking means declaring an explicit dependency and scoping the commit range yourself, with no automatic retarget. `none` if your forge has no stacking model at all, which is a fine answer: the calling skill still chains the branches in git and writes the relationship into the review body.
```

- [ ] **Step 5: Update the template's `openReview` section**

In the same file, change the section heading on line 71 from:

```markdown
## `openReview(branch, base, title, body)`
```

to:

```markdown
## `openReview(branch, base, title, body, dependsOn?)`
```

Then, directly before the line reading `Return the review id and the review's URL.`, insert:

```markdown
> **Say what you do with `dependsOn`, explicitly, even when the answer is nothing.** It arrives holding the review id this one is stacked on, and it is absent for a standalone review and for the first review in a stack. If you declared `retarget` or `none`, write "Ignore `dependsOn`" and say that the `base` argument carries the relationship. If you declared `declared-dependency`, give the exact command that records the dependency, and say how you scope the review to this bundle's commits only - a declared dependency with an unscoped range shows the upstream bundle's changes twice.
```

- [ ] **Step 6: Run the consistency check**

Run:

```bash
grep -rn "openReview(branch, base, title, body)" skills/
```

Expected: no output, exit code 1. Every signature now carries `dependsOn?`.

Run:

```bash
grep -rln "dependsOn" skills/fathom-shared/forges/
```

Expected: exactly three paths, `github.md`, `generic-git.md`, and `TEMPLATE.md`.

- [ ] **Step 7: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 8: Commit**

```bash
git add skills/fathom-shared/forges/github.md skills/fathom-shared/forges/generic-git.md skills/fathom-shared/forges/TEMPLATE.md
git commit -m "feat(fathom): implement dependsOn in the bundled forge adapters"
```

---

## Task 3: Add the split proposal to the approval contract

**Files:**
- Modify: `skills/fathom-shared/approval.md:22-34` (the skip list)
- Modify: `skills/fathom-shared/approval.md:71-79` (recording it)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the `stacking: propose | never` profile field name, and the classification that Task 6 cites when it fires the proposal stop.

`approval.md:69` states that when a new stop is added, it must be explicitly placed in the skip list, the never-skip list, or the unconditional stops. This task performs that classification.

- [ ] **Step 1: Add the skip-list entry**

In `skills/fathom-shared/approval.md`, in the `What auto mode skips` section, append this entry to the end of the bullet list:

```markdown
- The bundle-split proposal in `execute`.
  Apply the proposed split and report the bundles rather than asking for confirmation first.
  This belongs here rather than on the safety list because it fires before any branch, commit, or review exists, so a wrong answer costs nothing and is corrected by re-running with `stacking: never` or a different instruction.
  It is skipped only when the profile's `stacking` field permits a split at all; `stacking: never` suppresses the split itself, in both modes, rather than suppressing the question.
```

- [ ] **Step 2: Add the profile field**

In the same file, in the `Recording it` section, append these lines after the paragraph beginning "First-run setup asks for the mode":

```markdown
A second field, `stacking`, sits alongside `approval` and answers a different question: whether `execute` may split one issue into a stack of dependent reviews at all.
It holds `propose` or `never`, and an absent field means `never`, so a repository opts into stacking by writing `stacking: propose`.

`propose` means the agent may propose a split when the breakdown crosses the threshold in `execute`, with the `approval` field above deciding whether that proposal is a question or a report.
`never` means this repository always produces one review per issue, in both approval modes, in the same permanent way that `forge: none` makes the manual tier permanent.

The field deliberately has two values rather than three.
An `ask` or `auto` value here would restate the `approval` field recorded a few lines above it in the same profile, and two fields that can disagree about the same question will eventually disagree.
```

- [ ] **Step 3: Run the consistency check**

Run:

```bash
grep -n "stacking" skills/fathom-shared/approval.md
```

Expected: exactly 3 matching lines, all using only the values `propose` and `never`.

`grep -n` counts lines rather than occurrences, and the approved text carries the word on three of them: two in the skip-list entry and one in the profile-field paragraph. If you get a different number, report it rather than dropping the check.

Run:

```bash
grep -n "stacking: ask\|stacking: auto" skills/fathom-shared/approval.md
```

Expected: no output, exit code 1. The rejected three-value form appears nowhere.

- [ ] **Step 4: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add skills/fathom-shared/approval.md
git commit -m "feat(fathom): classify the bundle-split stop and add the stacking field"
```

---

## Task 4: Extend the working conventions for bundles

**Files:**
- Modify: `skills/fathom-shared/conventions.md:44-64` (the plan document)
- Modify: `skills/fathom-shared/conventions.md:78-85` (reconcile before finishing)

**Interfaces:**
- Consumes: the bundle vocabulary established in Task 1.
- Produces: the `- Bundles:` plan-document section and the per-bundle reconciliation rule that Task 6 invokes.

Do not touch the `Issue`, `Ref`, and `Branch` labels described at `conventions.md:51-56`. Those exact strings are matched by the merge-closer GitHub Action, and renaming or reformatting them makes the Action close nothing while still exiting successfully.

- [ ] **Step 1: Add the bundles section to the plan document spec**

In `skills/fathom-shared/conventions.md`, in the bullet list of plan document sections, insert this bullet directly after the `- **Tasks**` bullet:

```markdown
- **Bundles** - present only when this issue was split into a stack, and omitted entirely otherwise.
  One line per bundle, in stack order, each reading `- Bundle <k>/<N>: <branch> - <sub-issue refs, comma separated>`.
  Add a `- Review: <id> <url> (bundle k/N)` line beneath a bundle once its review exists.
  The suffix is redundant with the nesting on purpose: the sweep reads these lines individually, and a self-describing record survives being read out of its surrounding context.
  This section is the durable record a resumed run reads to recover the stack, so write it when the split is confirmed rather than when the first review opens.
```

- [ ] **Step 2: Add the per-bundle reconciliation rule**

In the same file, in the `Commit verification` section, find the paragraph beginning "Reconcile before finishing." and append these lines to the end of that section, directly before the paragraph beginning "This check guards a hazard":

```markdown
When the issue was split into a stack, reconcile once per bundle rather than once per issue, and do it before that bundle's review opens rather than at the end of the run.
Count over the range from that bundle's own base to that bundle's head: the resolved base branch for bundle 1, and branch k-1 for bundle k.
Compare that count to the number of tasks closed for that bundle only.
A stack-wide count over the whole range would pass even when one bundle carried another bundle's commits, which is exactly the mistake the check exists to catch.
Stop on a mismatch the same way, and do not open that bundle's review.
```

- [ ] **Step 3: Add the review body rule**

In the same file, append this new section at the end of the file, after `Progress reporting`:

```markdown
## Review bodies in a stack

When one issue produced a stack of reviews, the issue-closing reference goes in the last bundle's review body only.

`execute` puts `Closes <ref>` in the body for a Linear issue, or the task's URL for an Asana task, and both are read by the forge's tracker integration on merge.
Repeating either in every bundle means the first bundle's merge closes the issue while most of the work is still open and unreviewed.

Every bundle's body carries two additional lines instead:

- `Part <k> of <N>` so a reviewer knows this diff is a slice rather than the whole change.
- `Depends on <previous review url>`, omitted for bundle 1, which depends on nothing.

Earlier bundles still name the issue for context, as a plain link with no closing keyword.
The distinction is between referencing an issue and instructing the forge to close it, and only the last bundle does the second one.
```

- [ ] **Step 4: Run the consistency check**

Run:

```bash
grep -n "Issue: <tracker url>\|Ref: <issue ref>\|Branch: <branch>" skills/fathom-shared/conventions.md
```

Expected: the same output as before your edits, one line containing all three labels. If this changed, you altered the merge-closer contract and must revert that part.

Run:

```bash
grep -n "Part <k> of <N>\|Depends on <previous review url>\|Bundle <k>/<N>" skills/fathom-shared/conventions.md
```

Expected: 3 matching lines.

- [ ] **Step 5: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add skills/fathom-shared/conventions.md
git commit -m "feat(fathom): add bundle records, reconciliation, and stack bodies"
```

---

## Task 5: Extend the memory contract for multiple reviews

**Files:**
- Modify: `skills/fathom-shared/memory.md:14` (the `createTask` row)
- Modify: `skills/fathom-shared/memory.md:59-66` (the no-dual-truth section)

**Interfaces:**
- Consumes: the `- Bundles:` plan-document section from Task 4.
- Produces: the cross-bundle dependency edge rule that Task 6 applies at breakdown.

No new memory operation is added. `createTask` already accepts `deps`, which is all the cross-bundle edge needs.

- [ ] **Step 1: Note the cross-bundle edge on `createTask`**

In `skills/fathom-shared/memory.md`, append this sentence to the end of the `createTask` row's cell in the contract table, keeping it on the same table line:

```
When the issue was split into a stack, every task takes a dep on its predecessor so the whole issue forms one sequential chain across bundles as well as within them, which is what lets the backend itself enforce bundle order: a later bundle's task is never claimable while any earlier task is still open. A single edge at each bundle boundary would not achieve this, because a task carrying no deps at all has them trivially closed and stays claimable out of order.
```

- [ ] **Step 2: Update the record requirement for stacks**

In the same file, line 65 currently reads:

```markdown
Whichever backend is active, at least one file under `.fathom/` must record the issue's branch, its review id once one exists, and its tracker URL, because the merge sweep finds an issue by searching that directory, and a merge-closer running on the forge's own CI finds one the same way.
```

Append these lines directly after it:

```markdown
A stacked issue has more than one branch and more than one review id, so it records one of each per bundle, in stack order, in the plan document's `Bundles` section described in `conventions.md`.
The single `Branch` line at the top of the plan document keeps naming bundle 1's branch and is never removed, because the merge-closer Action matches that exact label and knows nothing about stacks.
This is a record of structure rather than of status, so it does not violate the no-dual-truth rule above: task status still lives only in the resolved backend, and the sweep reads review ids from these lines the same way it reads the single-review one.
```

- [ ] **Step 3: Run the consistency check**

Run:

```bash
grep -n "Bundles" skills/fathom-shared/memory.md skills/fathom-shared/conventions.md
```

Expected: at least one line from each file, both naming the same `Bundles` section.

Run:

```bash
grep -c "^| \`" skills/fathom-shared/memory.md
```

Expected: `6`. The contract still has exactly six operations and you added none.

- [ ] **Step 4: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add skills/fathom-shared/memory.md
git commit -m "feat(fathom): record stack structure and cross-bundle task deps"
```

---

## Task 6: Add bundling to the execute breakdown and branch steps

**Files:**
- Modify: `skills/execute/SKILL.md:69-72` (step 7, branch creation)
- Modify: `skills/execute/SKILL.md:73-80` (step 8, breakdown)

**Interfaces:**
- Consumes: the `stacking` field from Task 3, the `Bundles` plan section and cap from Task 4, the cross-bundle dep edge from Task 5, and the tier-3 no-stack rule from Task 1.
- Produces: the branch naming pattern `<existing-branch-name>-<k>` that Tasks 7 and 8 match against.

Steps are renumbered nowhere. Insert into the existing numbered steps 7 and 8 without changing any step number, because `execute/SKILL.md` steps are referenced by number from other files in this repository.

- [ ] **Step 1: Add the bundle branch naming rule to step 7**

In `skills/execute/SKILL.md`, append these lines to the end of step 7, after the paragraph about conflicts:

```markdown
   These rules describe bundle 1's branch, which is the only branch a single-review run has.
   When step 8 confirms a stack, later bundles take the same name with their index appended, so bundle 2 of `feat/ONC-5-add-webhooks` is `feat/ONC-5-add-webhooks-2`.
   Create each of those from the previous bundle's branch at the moment that bundle starts, not up front: creating them all at breakdown time would leave empty branches behind whenever a run stops early.
```

- [ ] **Step 2: Add the bundling decision to step 8**

In the same file, insert these bullets into step 8, directly after the bullet beginning "- When the issue already has children":

```markdown
   - Decide whether this issue produces one review or a stack, once the child tasks exist and before any dependency edge is added.
     Read the profile's `stacking` field per `../fathom-shared/approval.md`; treat an absent field as `never`, and stop considering a split immediately when it reads `never`.
     Do not consider a split when the resolved forge tier is the manual tier, and say once that the split was not offered because the tier cannot create reviews.
     Otherwise propose a split only when both conditions hold: the breakdown has five or more sub-issues, and at least one valid cut point exists.
     A cut point is valid only where the work up to it is independently mergeable, meaning the repository builds, that bundle's tests pass, and merging it alone would not break the base branch.
     When no valid cut point exists, proceed as a single review and say so rather than forcing a boundary.
   - Shape the bundles as contiguous runs of the sub-issue dependency chain, so bundles inherit its order rather than inventing one.
     Produce at most three bundles, each holding at least two sub-issues; those two limits together mean five sub-issues yield at most two bundles, and six is the smallest breakdown that can yield three.
     Exceed the cap only when the user asked for a specific larger split; never exceed it on the heuristic's own judgment.
   - Present the proposed split before creating anything: the bundles, which sub-issues fall in each, and the resolved forge's `stackedReviews` value with what it means for this run.
     This is a skip-list stop per `../fathom-shared/approval.md`, so `ask` mode waits for an answer and `auto` mode applies the split and reports it.
   - When a split is confirmed, chain every task in the issue sequentially, so each task deps on its predecessor across bundle boundaries as well as within them, rather than only where order matters.
     This is what makes `claimNext` structurally unable to hand out a later bundle's task while any earlier task is open, so the implementation loop needs no bundle-ordering logic of its own.
     A single edge at each bundle boundary is not enough: a task carrying no deps has them trivially closed, so it stays claimable out of order and the branch chain would be built on unfinished work.
     Apply full chaining only when a split is confirmed; a single-review run keeps the conditional chaining described above.
     Then write the `Bundles` section of the plan document described in `conventions.md`, and commit it with the breakdown.
```

- [ ] **Step 3: Run the consistency check**

Run:

```bash
grep -nE "^[0-9]+\. " skills/execute/SKILL.md
```

Expected: steps numbered 1 through 12 with no gaps and no duplicates, exactly as before your edits.

Use `grep -E` here, not plain `grep`. macOS ships BSD grep, whose basic regex does not honor `\?`, so a pattern written that way matches nothing at all and the check silently passes while proving nothing.

Run:

```bash
grep -n "stacking" skills/execute/SKILL.md
```

Expected: at least 1 line, referencing `../fathom-shared/approval.md`.

- [ ] **Step 4: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add skills/execute/SKILL.md
git commit -m "feat(fathom): propose a bundle split during breakdown"
```

---

## Task 7: Split the finish step into a per-bundle routine

**Files:**
- Modify: `skills/execute/SKILL.md:82-97` (step 10, the implementation loop)
- Modify: `skills/execute/SKILL.md:99-117` (step 11, finishing)

**Interfaces:**
- Consumes: the branch naming pattern from Task 6, the per-bundle reconciliation and review-body rules from Task 4, and `dependsOn` from Task 1.
- Produces: the `(bundle k/N)` review record format that Task 8's sweep reads.

Step 11 keeps its number and its single-review text. The stack behavior is added as a clearly scoped alternative within it, so a reader on a single-review run is never asked to follow stack rules.

- [ ] **Step 1: Add the bundle boundary to the implementation loop**

In `skills/execute/SKILL.md`, append this bullet to step 10's inner bullet list, directly after the bullet beginning "- Print the per-task progress line":

```markdown
    - When this issue was split into a stack and the closed task was the last one in its bundle, run the per-bundle finish routine in step 11 for that bundle before claiming again, then, when a later bundle remains, create the next bundle's branch from this one and continue the loop on it.
      Do not wait until the loop drains to open any review: building each bundle on the correct branch from the start is what avoids having to cherry-pick commit ranges onto a chain of branches afterwards.
```

- [ ] **Step 2: Add the per-bundle routine to step 11**

In the same file, insert this block into step 11, directly before the paragraph beginning "Finally, post a completion comment":

```markdown
    When this issue was split into a stack, the review-opening portion above is a per-bundle routine rather than a single closing action, and step 10 invokes it once per bundle as that bundle's last task closes.
    For bundle k of N:
    - Reconcile bundle k's closed tasks against the commits on its branch, over that bundle's own range, per the per-bundle rule in `conventions.md`; stop and do not open this bundle's review when they disagree.
    - Call `resolveBase` on bundle 1's base, which is the resolved base branch, or on branch k-1 for every later bundle.
    - Push branch k, unless the adapter declares `pushesForYou`, exactly as the single-review path does.
    - Call `openReview` with branch k, that base, a title naming the bundle, and a body built per the stack rules in `conventions.md`: the closing reference only in bundle N, plus `Part k of N`, plus `Depends on` the previous bundle's review URL for every bundle after the first.
      Pass the previous bundle's review id as `dependsOn` for every bundle after the first, and omit it for bundle 1.
    - Call `publishReview` with the returned id.
    - Record `- Review: <id> <url> (bundle k/N)` beneath that bundle's line in the plan document's `Bundles` section, since the sweep looks reviews up by id and needs every one of them.
    - Apply `inReview` when bundle 1's review publishes, and never again for the later bundles; the issue is genuinely in review from that moment and re-applying a phase it already holds reports progress that did not happen.
    Skip a bundle whose review already exists and reuse it, the same way the single-review path does, so a resumed run never opens a second review for a bundle that has one.
    After bundle N's routine completes, skip the single-review path above entirely and continue into the closing actions below, which run once for the issue rather than once per bundle.
```

- [ ] **Step 2b: Scope the existing single-review path so a stacked run cannot fall into it**

This is the other half of Step 2, and without it the two paths are not mutually exclusive. A stacked run reaches `claimNext` returning none after its last bundle's routine has already opened that bundle's review, and then executes the original text as well.

In the same file, replace this line:

```markdown
11. Once `claimNext` returns none remaining, finish the issue.
```

with:

```markdown
11. Once `claimNext` returns none remaining, finish the issue.
    This step has two mutually exclusive paths, and exactly one of them runs.
    A single-review issue follows the single-review path immediately below, then the closing actions at the end of this step.
    A stacked issue skips that path entirely and goes straight to the closing actions, because step 10 already opened every one of its reviews through the per-bundle routine further down.
    Running the single-review path on a stacked issue would reconcile the whole issue against a single bundle's commit range, write a second review record in a format the sweep does not read, and move the issue to `inReview` a second time.
    A stacked issue also never enters this step on its own: step 10 invokes the per-bundle routine directly, and bundle N's routine runs the closing actions once as it finishes.
    So when the loop afterwards drains and `claimNext` returns none, this step has already completed for that issue, and nothing in it runs a second time.

    The single-review path, for an issue that was not split into a stack:
```

- [ ] **Step 3: Point the closing commit at the stack tip**

In the same file, in step 11's final paragraph about the closing commit, append:

```markdown
    On a stacked issue this closing commit goes on branch N, the stack tip, because that branch contains every bundle's history and is the only one whose review shows the completed task state.
```

- [ ] **Step 4: Extend the hold report for partial stacks**

In the same file, append this line to step 10's bullet beginning "- On a failure that cannot be fixed":

```markdown
      On a stacked issue, also name which bundles already have open reviews and which were never built, since some of the work is already in front of reviewers and the user needs to know which part held.
```

- [ ] **Step 5: Run the consistency check**

Run:

```bash
grep -n "bundle k/N" skills/execute/SKILL.md skills/fathom-shared/conventions.md
```

Expected: at least one line from each file, both using the identical `(bundle k/N)` format.

Run:

```bash
grep -nE "^[0-9]+\. " skills/execute/SKILL.md
```

Expected: steps 1 through 12 still present, in order, unrenumbered, with steps 9 through 12 at the end.

Use `grep -E` here, not plain `grep`. macOS ships BSD grep, whose basic regex does not honor `\?`, so a pattern written that way matches nothing and the check silently passes while proving nothing.

- [ ] **Step 6: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 7: Commit**

```bash
git add skills/execute/SKILL.md
git commit -m "feat(fathom): open one review per bundle as each bundle completes"
```

---

## Task 8: Teach the sweep about stacks and restacking

**Files:**
- Modify: `skills/execute/SKILL.md:56-61` (step 2, the done-on-merge sweep)

**Interfaces:**
- Consumes: the `(bundle k/N)` record format from Task 7 and the squash-merge caveat from Task 2.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the multi-review sweep rules**

In `skills/execute/SKILL.md`, append these lines to the end of step 2:

```markdown
   An issue split into a stack has one recorded review per bundle rather than one in total, so call `getReviewState` on every recorded id before deciding anything about the issue.
   A stack can satisfy more than one of the cases below at once, so check them in the order written and let the first one that applies decide the whole sweep.
   In particular a stack can hold a merged bundle, an open bundle, and an abandoned one simultaneously, and the abandoned bundle wins: restacking the bundles above it would force-push a rebase onto work the user may be about to discard, which is exactly the unattended destruction that stop exists to prevent.
   When any bundle reports `closed-unmerged`, apply the closed-without-merging path for that bundle, name which bundles above it in the stack are now orphaned by it, and neither close the issue nor restack anything; whether to retry, rescope, or drop the orphaned work is the user's judgment call.
   This case is checked first and is terminal: no later case runs after it, however many other bundles merged or stayed open.
   Otherwise move the issue to `done` when every bundle reports `merged`.
   Otherwise, with some bundles merged and others still open, close nothing: report the partial progress, naming which bundles merged, then run the restack check below.
   When the adapter declares `reviewLookup: none` the whole sweep is unavailable here as it already is for single reviews, so say so once and act on nothing.

   The restack check asks one forge-agnostic question: is the merged bundle's content an ancestor of each remaining stack branch?
   Rebase a remaining branch onto its updated base only when the answer is no, and leave it alone when the answer is yes.
   Ancestry is the right test rather than the adapter's `stackedReviews` value, because a squash-merge on a `retarget` forge leaves a dependent review redisplaying the merged bundle's changes exactly as an unretargeted `none` forge would, and one check covers both.
   Rebase the remaining branches bottom-up, so each one lands on a base that is already correct.
   Push a rebased branch with `--force-with-lease` and never with a bare force push.
   When the lease is rejected, stop and hold: another commit reached that branch, and overwriting it discards someone's work, which is the hazard `../fathom-shared/approval.md` already refuses to take unattended.
   When the rebase conflicts, stop and hold naming the conflicting files, exactly as a base-branch update conflict does in step 7.
```

- [ ] **Step 2: Add the mid-stack tier drop rule**

In the same file, append this line to step 1, after the sentence about stating the resolved tier:

```markdown
   When a resumed run resolves the manual tier on an issue whose earlier bundles already have open reviews, leave those reviews alone and hand the remaining bundles off manually, saying that the tier changed between runs so the stack is now half automated and half manual.
```

- [ ] **Step 3: Run the consistency check**

Run:

```bash
grep -n "force-with-lease" skills/execute/SKILL.md
```

Expected: exactly 1 line, the one requiring the flag and forbidding a bare force push.
The sentence handling a rejected lease follows it and says "the lease is rejected" without repeating the flag name, so it does not match this pattern.
There must be no line permitting a bare `--force`.

Also confirm by reading that the sentence immediately after it stops and holds when the lease is rejected.
That behavior is the point of the check, and a grep count alone cannot prove it.

Run:

```bash
grep -n "git push --force[^-]" skills/execute/SKILL.md
```

Expected: no output, exit code 1.

- [ ] **Step 4: Run the scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add skills/execute/SKILL.md
git commit -m "feat(fathom): sweep every bundle and restack on ancestry"
```

---

## Task 9: Bump the version and run the full verification

**Files:**
- Modify: `.claude-plugin/plugin.json` (the `version` field)
- Modify: `.claude-plugin/marketplace.json` and `README.md` (written by the sync script, not by hand)

**Interfaces:**
- Consumes: every preceding task.
- Produces: nothing.

- [ ] **Step 1: Bump the plugin version**

In `.claude-plugin/plugin.json`, change:

```json
  "version": "2.1.0",
```

to:

```json
  "version": "2.2.0",
```

This is a minor bump because the change adds behavior and every existing repository, forge, and tier keeps behaving exactly as before unless it opts in.

Do not edit `.claude-plugin/marketplace.json` or `README.md` by hand. `plugin.json` is the source of truth and the next step propagates it.

- [ ] **Step 2: Propagate the version**

Run:

```bash
bin/sync-versions.sh
```

Expected: exit code 0, and `git status --short` now shows `.claude-plugin/marketplace.json` and `README.md` as modified.

- [ ] **Step 3: Run the full scanner**

Run:

```bash
bin/scan-skills.sh
```

Expected: exit code 0, no non-suppressed findings across all three skills.

- [ ] **Step 4: Run the whole-change consistency check**

Run:

```bash
grep -rn "declared and unused\|Reserved. No behavior\|openReview(branch, base, title, body)" skills/
```

Expected: no output, exit code 1. No file still describes the capability as unused or the signature as four-argument.

Run:

```bash
grep -rn "—" skills/ docs/plans/2026-08-07-fathom-stacked-reviews-design.md
```

Expected: no output, exit code 1. No em dash was introduced.

Do not add the plan file itself to this check. The plan contains this very grep command, so the literal character appears in it by necessity and would always match.

Run:

```bash
grep -rn "TODO\|TBD" skills/
```

Expected: no output, exit code 1.

- [ ] **Step 5: Read the changed files together**

Open `skills/execute/SKILL.md`, `skills/fathom-shared/forges.md`, `skills/fathom-shared/conventions.md`, and `skills/fathom-shared/approval.md` side by side and confirm three things by reading, because no tool in this repository checks them:

- Every place that says "the review" for a stacked issue is unambiguous about whether it means one bundle's review or all of them.
- The bundle cap (3 bundles, 2 sub-issues each, 5 sub-issue threshold) appears with identical numbers everywhere it appears.
- The `stacking` field is described identically in `approval.md` and `execute/SKILL.md`.

Fix any disagreement in place before committing.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "chore(fathom): release 2.2.0 with stacked reviews"
```

---

## Self-review record

**Spec coverage.** Every numbered section of the design document maps to a task: sections 1, 2, 3 and 4 to Tasks 3 and 6; section 5 to Task 6; sections 6 and 7 to Tasks 5 and 6; sections 8 and 9 to Tasks 4 and 7; section 10 to Tasks 1 and 2; sections 11, 12 and 13 to Task 8; section 14 to Task 7; section 15 to Task 8; the `Files touched` list to Tasks 1 through 8; and `Verification` to Task 9.

**Spec gap found and fixed.** The design's `stackedReviews: none` behavior was unreachable through any bundled adapter, because the only bundled adapter declaring `none` is the one the manual tier runs on, and the manual tier never stacks. Task 1 Steps 1 and 2 amend the design document to scope that row to tier-1 repo-local adapters, and Task 2 Step 3 records the same fact in `generic-git.md`.

**Naming consistency.** The argument is `dependsOn` in Tasks 1, 2 and 7. The record format is `(bundle k/N)` in Tasks 4, 7 and 8. The plan-document section is `Bundles` in Tasks 4, 5 and 6. The profile field is `stacking` with values `propose` and `never` in Tasks 3 and 6. The branch pattern is the base name with `-<k>` appended in Tasks 6 and 7.
