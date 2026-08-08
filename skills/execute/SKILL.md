---
name: execute
description: This skill should be used when the user asks to "execute ONC-5", "run execute on this issue", "work on an issue", "start an issue", "implement this Asana/Linear issue", "take this issue to a PR", "take this issue to review", pastes an Asana task URL to build, or names a Linear issue key like ONC-5. Also use when the user says something like "the PR for <issue> merged", "the review for <issue> merged", "clean up merged issues", "the PR was closed", "the change landed", "that PR got abandoned", "that review was abandoned", or "close out merged work", to run the done-on-merge sweep on demand. Drives an existing tracker issue from breakdown through implementation to an open code review with resumable task tracking, on GitHub or any other forge with an adapter.
version: 1.0.0
---

# Execute

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse the request and stop.
Say which MCP is missing and that the user must connect it before this skill can continue.
Refuse even when a bypass looks possible and helpful.
Do not read or search for credentials in files, environment variables, or token caches.
Do not call tracker HTTP APIs.
Do not edit MCP or agent configuration.
Treat a disabled server as a deliberate user decision, a stop condition, never an obstacle to route around.

This skill drives one tracker issue through a single resumable autonomous pass, from breakdown through implementation to an open code review.
There is no separate start step and finish step; re-invoke this same skill on the same issue to resume wherever the last run left off.
Every run begins by reading durable state from the repository and the tracker, not from anything remembered between invocations.

## Operating principles

- Treat this as one resumable pass guarded by observable artifacts on disk and in the tracker, never by memory of a previous run.
- After the first-run tracker profile is confirmed, proceed without further mid-run confirmation; only stop when this procedure says to stop.
- Auto mode removes questions, never safety stops; every stop in `approval.md` fires in both modes.
- The memory backend is the source of truth for task state; state flows one way from it to the tracker, never the reverse.
- On an unfixable test failure, stop and hold rather than pushing partial or broken work forward.
- Tracker access goes only through the connected tracker MCP; when it is missing, stop and say so; never hunt for credentials on disk or call tracker APIs directly.

## Read first

Before doing any tracker or memory work, read:

These paths are relative to the directory containing this SKILL.md file, not the current workspace.
In a global Kiro install they resolve under `~/.kiro/skills/` (for example `~/.kiro/skills/fathom-shared/trackers.md`); in a Claude Code plugin install they resolve inside the plugin's `skills/` directory.

- `../fathom-shared/trackers.md` for the tracker contract, phase names, and first-run profile setup.
- `../fathom-shared/forges.md` for the forge contract, adapter resolution, the capability tiers, and base-branch resolution.
- `../fathom-shared/memory.md` for the memory contract and backend resolution rules.
- `../fathom-shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.
- `../fathom-shared/conventions.md` for staging safety, commit messages, the plan document, and progress reporting.
- `../fathom-shared/approval.md` for the two approval modes, and for the stops that hold in both.

If any of these files cannot be found and read, stop immediately and report which paths were tried - never improvise their contracts from memory or proceed without them.

## Procedure

1. Resolve the approval mode per `../fathom-shared/approval.md` and state it, then run preflight verification as described in `../fathom-shared/trackers.md` before any other tracker step.
   Infer the preflight target from the invocation before verifying anything: an explicitly named tracker, or the shape of the issue ref from the invocation argument, a pasted URL, or the current branch name, in the same order of preference step 4 uses; only when none of those settles it fall back to the profile, then to the single connected MCP, per the shared precedence in `trackers.md`.
   This keeps preflight, the sweep, and the run itself on one tracker; verifying whatever the profile names while the invocation clearly targets the other tracker would sweep and verify the wrong one.
   Stop here, following that section's instructions, when the tracker's MCP does not verify.
   A forge that does not verify is not a stop: it selects a capability tier per `../fathom-shared/forges.md`. State the resolved tier before continuing, so the user knows up front whether this run will end in an opened review or a manual handoff.
   When a resumed run resolves the manual tier on an issue whose earlier bundles already have open reviews, leave those reviews alone and hand the remaining bundles off manually, saying that the tier changed between runs so the stack is now half automated and half manual.
   Say with it that no later run will move this issue to `done` on its own, because the manual tier cannot observe what happened to a review, so closing the issue is now a manual step.
2. Run the done-on-merge sweep for the resolved tracker; the mechanics are described in `../fathom-shared/trackers.md` and are tracker-agnostic, with each adapter file defining only its own closure action for the merged path.
   This sweep is itself tracker work, so it only runs once preflight has verified the MCP.
   When the invocation itself was a cleanup phrase, run only this sweep, report what it found, then stop; do not continue into the rest of this procedure.
   Treat any claim about a review's fate as a cleanup phrase, whether it says merged, closed, abandoned, landed, or shipped, and whether it names an issue or asks to clean up whatever is outstanding.
   Never act on the claim itself: confirm each referenced review's real state through `getReviewState` first, then apply the merged path or the closed-without-merging path accordingly, and say plainly when the confirmed state differs from what the user described.
   When the resolved forge declares `reviewLookup: none`, the claim cannot be confirmed at all. Say that plainly and act on nothing; do not close an issue on the strength of an unverifiable claim, since a wrong close is exactly what the confirmation step exists to prevent.
   That same `reviewLookup: none` declaration makes the whole sweep unavailable, exactly as it already is for single reviews, so say so once and act on nothing.
   Check it before the cases below rather than after them, since it decides whether `getReviewState` can be called at all.
   An issue split into a stack has one recorded review per bundle rather than one in total, so collect every bundle's record first, then call `getReviewState` on every id collected before deciding anything about the issue.
   Those records are not all reachable from the checkout this sweep runs in: each bundle's `- Review:` line is committed on that bundle's own branch, so a sweep running from the base branch checkout sees the records of the bundles that have merged and none of the records above them.
   Collect the rest by fetching, per the collection rule in `../fathom-shared/trackers.md`: read the branch names from the plan document's `Bundles` section, fetch each of those branches, and read each fetched branch's own copy of the plan document for that bundle's `- Review:` line.
   This is read-only git work that writes nothing, which is why the ids stay in the plan document rather than being mirrored into a second store the base branch could read directly; one record of a fact cannot disagree with itself.
   A stack can satisfy more than one of the cases below at once, so check them in the order written and let the first one that applies decide the whole sweep.
   In particular a stack can hold a merged bundle, an open bundle, and an abandoned one simultaneously, and the abandoned bundle wins: restacking the bundles above it would force-push a rebase onto work the user may be about to discard, which is exactly the unattended destruction that stop exists to prevent.
   When any bundle reports `closed-unmerged`, apply the closed-without-merging path for that bundle, name which bundles above it in the stack are now orphaned by it, and neither close the issue nor restack anything; whether to retry, rescope, or drop the orphaned work is the user's judgment call.
   This case is checked first and is terminal: no later case runs after it, however many other bundles merged or stayed open.
   Otherwise, when any bundle reports `unknown`, or the collection above found no `- Review:` record for some bundle between 1 and N, change nothing about the issue and leave it for a later sweep: name the review ids that came back `unknown` and the bundles whose records are missing, close nothing, restack nothing, and report no progress for the issue.
   `unknown` means the sweep did not learn that review's fate, not that the review is open or merged, so calling it any of those states is a claim about work that was never observed.
   A missing record is the same kind of gap and is treated identically: the `Bundles` section says how many bundles this issue has, so N is known even when a record is not, and a stack judged on fewer records than N is judged on an incomplete set.
   A bundle carrying only the `- Review: pending (bundle k/N)` marker described in `conventions.md`, or only the `- Review: none confirmed (bundle k/N)` line that records a user's confirmation that no review exists, counts as a missing record here rather than as a review: neither line names an id, so there is nothing for `getReviewState` to be called on and nothing is known about that bundle's fate.
   With N of 3 and only two records collected, every case below would read a partly recorded three-bundle stack as a complete two-bundle one, and the first of them would move a half-merged issue to `done`.
   So require a record for every bundle from 1 to N before evaluating any of the aggregate cases below, and take this case whenever that requirement is unmet.
   This case sits below the `closed-unmerged` case, which closes nothing and restacks nothing whatever the undetermined or unrecorded bundles turn out to be, and above the three cases below, each of which judges the whole stack on all of its bundles at once and cannot do that with an undetermined or missing bundle among them.
   Otherwise move the issue to `done` when every bundle reports `merged`.
   Otherwise, with some bundles merged and others still open, close nothing: report the partial progress, naming which bundles merged, then run the restack check below.
   Otherwise every bundle is still open, with none merged, none abandoned, and none undetermined, so the stack is simply still in review: say that, close nothing, and restack nothing, since no merge has moved any base.

   The restack check asks one forge-agnostic question: is the merged bundle's content an ancestor of each remaining stack branch?
   Rebase a remaining branch onto its updated base only when the answer is no, and leave it alone when the answer is yes.
   Ancestry is the right test rather than the adapter's `stackedReviews` value, because a squash-merge on a `retarget` forge leaves a dependent review redisplaying the merged bundle's changes exactly as an unretargeted `none` forge would, and one check covers both.
   Rebase the remaining branches bottom-up, so each one lands on a base that is already correct.
   Push a rebased branch with `--force-with-lease` and never with a bare force push.
   When the lease is rejected, stop and hold: another commit reached that branch, and overwriting it discards someone's work, which is the hazard `../fathom-shared/approval.md` already refuses to take unattended.
   When the rebase conflicts, stop and hold naming the conflicting files, exactly as a base-branch update conflict does in step 7.
3. Resolve which tracker owns this issue and which memory backend owns its task state, following `trackers.md` and `memory.md`.
   When the repo already contains beads state but the beads tooling is unavailable on this machine, stop and say so as memory.md directs; never substitute a different backend for a repo whose state lives in another one.
   Load the existing `.fathom/config.md` tracker profile, or run first-run setup when none exists; either way, run the tracker adapter's profile-load checks and honor any one-time offers they define.
4. Determine the issue ref from the invocation argument, a pasted issue URL, or the current branch name, in that order of preference; when the argument and the branch name refer to different issues, stop and ask the user which one to use.
5. Call `getIssue` for that ref and save its title, description, type, URL, and existing children for the rest of this run.
   When the issue is already in the `done` phase or marked complete, do not start work: say so, report what the sweep found for it, and ask whether to reopen it or pick a different issue.
6. Search the codebase and read the files that look relevant to this issue, noting existing patterns to follow during implementation.
7. Ensure the branch this run implements on exists, and continue on that one branch until step 10 says to move to the next bundle.
   Decide which branch that is before creating anything: read this issue's plan document when one already exists, since a resumed run recovers the stack from durable state and never from memory of an earlier run.
   When that document carries a `Bundles` section, this issue was already split: recover every bundle's index, branch, sub-issue refs, and recorded review id from it, and carry that recovered stack through the rest of this run, including step 10's loop and step 11's per-bundle routine.
   The bundle in progress is the first one with no recorded review, because a bundle's review is recorded as its last task closes, so this run continues on that bundle's branch rather than on bundle 1's.
   Continuing on bundle 1's branch instead would land a later bundle's commits in a review that is already open and published, which is the failure this recovery exists to prevent.
   When every bundle already carries a recorded review, no bundle is in progress and the branch is bundle N's, the stack tip: every bundle's work is committed and reviewed, so all that can remain is the issue-level finalization, which step 11 puts on the tip branch anyway.
   Do not create another branch and do not go back to an earlier bundle's branch in that case; this run is finishing the stack rather than building it.
   The branch is bundle 1's whenever no plan document exists yet, which is a first run rather than a resumed one, and whenever the plan document carries no `Bundles` section, which is a single-review issue.

   Name a branch that must be created from the issue type (`feat/` for a feature, `fix/` for a bug, `chore/` for a chore, `docs/` for docs, `feat/` by default) followed by the issue ref and a short title slug; skip creation when a matching branch already exists.
   Resolve the base branch per the base-branch rules in `../fathom-shared/forges.md`, then fetch it and create the new branch from the fetched remote copy rather than from a local copy that may be behind, since branching from a stale local copy is the usual cause of conflicts at merge time.
   When the branch already exists and the base branch has moved on since, bring it up to date before implementing, and report that you did.
   When that update conflicts, stop and hold exactly as an unfixable test failure would: keep the work, leave the task in progress, report which files conflict, and let the user decide how to resolve them; never resolve a conflict by discarding either side's changes.
   These rules describe bundle 1's branch, which is the only branch a single-review run has.
   When step 8 confirms a stack, later bundles take the same name with their index appended, so bundle 2 of `feat/ONC-5-add-webhooks` is `feat/ONC-5-add-webhooks-2`.
   Create each of those from the previous bundle's branch at the moment that bundle starts, not up front: creating them all at breakdown time would leave empty branches behind whenever a run stops early.
   Give every one of them the same already-exists guard bundle 1 has: check out a bundle branch that already exists rather than creating it, and create it only when it is genuinely absent, since creating a branch name that already carries that bundle's commits either fails outright or resets the branch and discards them.
8. Ensure the breakdown exists.
   - Skip the rest of this step when a breakdown already exists for this issue.
     Every decision below is made once, at breakdown time, so a resumed run reads the split, the bundles, and their branches out of the plan document instead of deciding any of them again.
     When that plan document carries a `Bundles` section, the stack step 7 recovered from it governs the rest of this run, and arriving here with such a section on disk but no recovered stack is the defect: go back to step 7 and recover it before implementing anything.
     A resumed single-review issue has no `Bundles` section and so has nothing to recover; step 7 has already put it on its one branch.
   - Plan the units of work before writing anything to the tracker or the memory backend.
     When the issue has no existing children, plan three to seven units of work, each sized so it can be implemented and verified on its own, and hold that plan rather than creating anything from it yet.
     When the issue already has children, call `listSubIssues` to adopt them instead of inventing a new breakdown, which reads the tracker without writing to it.
     Either way the units are ordered, each building on the one before it, and that order is what the `deps` below and any bundle boundary follow.
   - Decide whether this issue produces one review or a stack, from those planned units and before anything is written to the tracker.
     Never consider a split when the resolved forge tier is the manual tier, whatever the breakdown looks like, since that tier cannot create a review at all.
     Read the profile's `stacking` field per `../fathom-shared/approval.md`; treat an absent field as `never`, and stop considering a split immediately when it reads `never`, whether it was written or absent.
     Otherwise propose a split only when both conditions hold: the breakdown has five or more units of work, and at least one valid cut point exists.
     A cut point is valid only where the planned units up to it form a self-contained change: the units after it build on the units before it and not the reverse, and the earlier units together deliver something that stands on its own rather than half of one thing.
     Judge that from the plan alone, because the plan is all there is to judge from at this moment: the decision is made at breakdown time, before any of the work is written, so there is no build to run and no tests to pass at a candidate boundary.
     This is therefore a prediction about reviewability rather than a verified property of the repository, and two later steps catch a wrong prediction.
     The confirmation stop below shows the proposed boundaries to the user before anything is built, which is the cheap correction.
     The per-bundle finish routine in step 11 then reconciles that bundle and runs its tests for real, and its stop-and-hold fires when either disagrees, which is the expensive one.
     A boundary that looked self-contained in the plan and turns out not to be is caught before that bundle's review opens rather than after it ships.
     When no valid cut point exists, proceed as a single review and say so rather than forcing a boundary.
     Both conditions are properties of the planned units rather than of anything on the tracker: the count comes from the plan, and a cut point's validity is a property of the work itself, which is what lets this whole decision run before a single sub-issue exists.
     When the manual-tier guard above fired, say the split was not offered because the tier cannot create reviews only if the breakdown would otherwise have crossed the five-unit threshold; below that threshold no split was available in any tier, so explaining its absence would report a decision that was never live.
   - When both of those conditions hold, shape the bundles as contiguous runs of the planned order established above, so bundles inherit that order rather than inventing one.
     Produce at most three bundles, each holding at least two units; those two limits together mean five units yield at most two bundles, and six is the smallest breakdown that can yield three.
     Exceed the cap only when the user asked for a specific larger split; never exceed it on the heuristic's own judgment.
   - When both of those conditions hold, present the proposed split before anything is written to the tracker: the bundles, which units fall in each, and the resolved forge's `stackedReviews` value with what it means for this run.
     This is a skip-list stop per `../fathom-shared/approval.md`, so `ask` mode waits for an answer and `auto` mode applies the split and reports it.
     Placing it ahead of every write is what makes it safe to abandon: a user who walks away from the question, or declines outright, leaves no sub-issue on the tracker, no task in memory, and no task file on disk, so there is nothing half-built to reconcile.
   - Call `init` for the issue, then call `parentTask` for it, once the split question is settled.
     These are the first writes this step makes, which is why they sit below the proposal stop rather than above it; nothing between the plan and this point reads either of them.
   - Create the sub-issues and their tasks next, passing each task's final `deps` to `createTask` itself, since that is the only operation in `../fathom-shared/memory.md` that takes `deps` and a chain cannot be added to tasks that already exist.
     When no split was confirmed and the issue has no existing children, for each planned unit call `createSubIssue` first, then call `createTask` with the newly created sub-issue's ref as `subIssueRef`, then write the returned task id back onto that sub-issue so the link reads both ways, since the task id does not exist until `createTask` returns, setting `deps` to the id of the task it builds on so tasks chain sequentially by default whenever order matters.
     When no split was confirmed and the issue already had children, for each adopted sub-issue still call `createTask`, passing that sub-issue's existing ref as `subIssueRef` and skipping `createSubIssue` since the sub-issue already exists, then write the returned task id back onto that sub-issue the same way, and setting `deps` the same way.
     Those two are the single-review behavior exactly as it has always run, one sub-issue and its task at a time, so nothing watching the tracker sees a different sequence than before.
     When a split was confirmed, take the same create-versus-adopt decision those two branches take: create a sub-issue for each planned unit when the issue has no existing children, and adopt the existing children when it has them, skipping `createSubIssue` for each adopted one exactly as the adopt branch above does.
     A split never changes whether the sub-issues already exist, so an issue that arrived with children gets tasks created against those children and never a duplicate set alongside them.
     Create them strictly one at a time in the planned order, from the first unit to the last, rather than in whatever order the bundle records suggest.
     That order is what makes each task's predecessor id already exist when the next task needs it as a dep, and it also has every sub-issue ref created before the `Bundles` section that names them is written.
     Chain every task in the issue sequentially on that path, so each task deps on its predecessor across bundle boundaries as well as within them, rather than only where order matters.
     This is what makes `claimNext` structurally unable to hand out a later bundle's task while any earlier task is open, so the implementation loop needs no bundle-ordering logic of its own.
     A single edge at each bundle boundary is not enough: a task carrying no deps has them trivially closed, so it stays claimable out of order and the branch chain would be built on unfinished work.
   - After every child task exists, add the parent's dependency edge on each child, so the parent cannot close before its children and "no open children" becomes a real signal rather than an assumption.
   - Whether the sub-issues were newly created or adopted, write the plan document described in `conventions.md` and commit it with the breakdown.
     When a split was confirmed, that same document also carries the `Bundles` section recording each bundle's index, branch, and sub-issue refs, so write it now rather than when the first review opens, since it is what a resumed run reads to recover the stack.
     Write the `- Merge-closer: suppressed` line described in `conventions.md` with it, since a stacked issue records every bundle's branch and the merge-closer Action would otherwise close the whole issue on whichever bundle merged first.
   - Write `.fathom/tasks/<ISSUE-REF>.md` only when the resolved backend is the checklist adapter, since that file holds checkbox statuses; with beads active the statuses live in beads and no file belongs there, as `memory.md` states.
9. Call `updateState` to move the issue to the `inProgress` phase.
10. Run the implementation loop until `claimNext` reports nothing claimable.
    Before the first pass, when this issue was split into a stack, check the bundle step 7 recovered: when every task in that bundle is already closed and it still carries no recorded review, its per-bundle finish routine was interrupted, so run that routine from step 11 for that bundle now, and then, when a later bundle remains, move onto its branch under the already-exists guard in step 7, exactly as the end of a pass would.
    Decide that from the durable record rather than from what is claimable: the closed tasks live in the memory backend and the recorded reviews live in the plan document, and both outlive the run that was interrupted.
    Claiming without this check would hand out the next bundle's first task, since an interrupted routine leaves this bundle's tasks all closed while the next bundle's are still open, and that task would then be implemented on this bundle's branch and land in the wrong review.
    A run interrupted later still, after every bundle's routine finished but before the issue's closing actions did, leaves nothing claimable at all and so makes no pass here; step 11 recovers that one.

    Each pass through the loop does the following, in order.
    - Call `claimNext`, and record the claim in the memory backend's own format at claim time.
    - Move the claimed task's linked sub-issue to the `inProgress` phase, subject to the adapter's own rules for sub-issues; the Asana adapter degrades this to a no-op on subtasks, so read its subtask section rather than assuming a state change happens.
      Never redirect a sub-issue transition onto the main issue: closing a parent because one child finished would mark the whole issue done early.
    - Implement that one unit of work, following the codebase patterns found in step 6.
    - Run the tests covering that unit.
      When the repository has no test framework, or the touched code has no tests, say so once and write a test for the unit using whatever the project already depends on, then treat that test as this task's verification.
      When the project genuinely cannot run tests, say so plainly in the progress line and in the review body rather than implying the work was verified.
    - On a passing run, commit the change with a message referencing the issue ref and the task, staged and worded per `conventions.md`: never stage with a blanket pattern, and never stage a file that could carry a secret.
    - Confirm the commit exists before closing anything, and record its short hash with the close per the commit-verification rules in `conventions.md`.
    - Close the task in the memory backend and move its sub-issue to `done`, again per the adapter's sub-issue rules, recording the close as it happens rather than summarizing at the end of the loop.
      A task is not closed until both its memory record and its sub-issue are closed; closing only the sub-issue leaves it claimable and `claimNext` will hand you the same task again.
    - Print the per-task progress line from `conventions.md`.
    - When this issue was split into a stack and the closed task was the last one in its bundle, run the per-bundle finish routine in step 11 for that bundle before claiming again, then, when a later bundle remains, move onto the next bundle's branch under the already-exists guard in step 7, creating it from this one only when it is absent and checking it out when it is not, and continue the loop on it.
      Do not wait until the loop drains to open any review: building each bundle on the correct branch from the start is what avoids having to cherry-pick commit ranges onto a chain of branches afterwards.
    - On a failure that cannot be fixed, stop and hold: keep the change, leave the task in progress, report the failure, and exit without continuing the loop.
      On a stacked issue, also name which bundles already have open reviews and which were never built, since some of the work is already in front of reviewers and the user needs to know which part held.
    One commit per task, always, even when two tasks touch the same file.

11. Once `claimNext` returns none remaining, finish the issue.
    Read this issue's plan document before anything else in this step and look for the `- Finalization: complete` line described in `conventions.md`.
    That line is this issue's one durable record that its closing actions have run, the closing actions themselves are the only thing that writes it, and it is written by the last of them.
    When it is present, this issue is already finished: say so, change nothing else in this step, and go to step 12.
    The one exception is a line sitting on a commit that was never pushed; push that commit before reporting, since that push is itself the last of the closing actions and the only one that can still be missing while the line exists.
    When the line is absent, run the rest of this step.
    One recorded fact deciding this is what keeps a stacked issue from finalizing twice, in place of reasoning about which path invoked which routine.

    This step has two mutually exclusive paths, and exactly one of them runs.
    A single-review issue follows the single-review path immediately below, then the closing actions at the end of this step.
    A stacked issue skips that path entirely and goes straight to the closing actions, because step 10 already opened every one of its reviews through the per-bundle routine further down.
    Running the single-review path on a stacked issue would reconcile the whole issue against a single bundle's commit range, write a second review record in a format the sweep does not read, and move the issue to `inReview` a second time.
    On a stacked run that completes, step 10 invokes the per-bundle routine directly and bundle N's routine runs the closing actions as it finishes, so the finalization line is already written and pushed by the time the loop drains.
    Re-entering this step then reads that line and stops at the check above, having changed nothing, so the closing actions run exactly once however the run reached them.

    A run interrupted before that line was written arrives here with it absent, and recovering such a run is the only reason a stacked issue ever runs this step's body.
    Every task can be closed while the finalization that follows the last one is unfinished, and in that state nothing is claimable precisely when there is most left to do, so decide what remains from the durable record instead: the plan document's `Bundles` section says which bundles carry a recorded review, the memory backend says whether the parent task is still open, the tracker says the issue's phase and whether the completion comment is already on it, and branch N says whether the final closing commit exists and is pushed.
    Then do only what that record shows is missing, and skip whatever it shows is already done, which is what makes arriving here twice produce the same result as arriving once.
    Never call `openReview` for a bundle that already carries a recorded review; reuse it, exactly as the per-bundle routine's own guard says.
    A bundle whose tasks are all closed and whose review is missing is recovered in step 10 rather than here, before any claiming, so by the time this step runs every bundle has its review.
    Close the parent task only when the backend shows it open, apply `inReview` only when the tracker shows the issue in an earlier phase, post the completion comment only when `listComments` shows the issue does not already carry one, and make and push the final closing commit only when branch N does not already carry the completed task state.
    When the resolved tracker cannot list comments, post the comment and say that it may be a duplicate, since a second completion comment is a cosmetic cost and a missing one loses the handoff entirely.
    When the record shows every one of those already done, the previous run got all the way to the last closing action without recording it, so write the finalization line described below, commit and push it as bookkeeping, and say that the issue was already finished and only its record was missing.
    That is the one thing such a run still owes: leaving the line unwritten would make every later run walk this recovery again.

    The single-review path, for an issue that was not split into a stack:

    Commit any leftover uncommitted change that belongs to this issue's tasks, leaving unrelated working-tree edits alone rather than sweeping them into the review.
    Then run the commit reconciliation from `conventions.md` and stop if the task and commit counts disagree, in that order, so the range it counts already carries every commit this issue's tasks produced.
    Close the parent task in the memory backend (a no-op for the checklist adapter, whose file is the parent record).

    Then open the review through the forge contract in `../fathom-shared/forges.md`, never by invoking a forge CLI directly from this procedure.
    - Confirm the resolved base with `resolveBase` first, as the contract requires, before anything is created against it.
    - Push the branch, unless the resolved adapter declares `pushesForYou`; when it does, `openReview` owns the push and pushing here would produce a wrong branch state.
    - Call `openReview` with the branch, the resolved base, a title, and a body containing `Closes <ref>` for a Linear issue or the task's URL for an Asana task, plus a summary, the list of completed tasks, and a test plan.
    - Skip this when a review already exists for the branch, and reuse that one; resuming an issue must never open a second review.
    - Call `publishReview` with the returned id.
    - Record `- Review: <id> <url>` in this issue's file under `.fathom/`, alongside the existing `- PR:` line, since the sweep looks issues up by id.
    - Call `updateState` to move the issue to the `inReview` phase.

    When `openReview` returns the manual-handoff result instead of an id, there is no review object: skip `publishReview`, record no review id, print the handoff.
    Still apply `inReview`, and say plainly that no later run will move this issue to `done` on its own because the forge cannot be observed, so closing it is now a manual step.

    When this issue was split into a stack, the review-opening portion above is a per-bundle routine rather than a single closing action, and step 10 invokes it once per bundle as that bundle's last task closes.
    For bundle k of N:
    - Commit any leftover uncommitted change that belongs to this bundle's tasks, leaving unrelated working-tree edits alone rather than sweeping them into the review, exactly as the single-review path does before it opens its one review.
      A change left uncommitted here is absent from bundle k's review and lands in bundle k+1's instead, which is worse than the single-review case rather than merely equivalent to it.
    - Then reconcile bundle k's closed tasks against the commits on its branch, over that bundle's own range as it stands after the commit above, per the per-bundle rule in `conventions.md`; stop and do not open this bundle's review when they disagree.
      These two run in this order because the leftover commit changes the very range the reconciliation counts.
      Reconciling first would count a range still missing that commit, so a bundle with leftover work would come up short and stop the routine even though nothing was wrong; and where the count happened to match anyway, the leftover commit would land in the range afterwards and never be reconciled at all.
    - Call `resolveBase` on bundle 1's base, which is the resolved base branch, or on branch k-1 for every later bundle.
    - Write `- Review: pending (bundle k/N)` beneath that bundle's line in the plan document's `Bundles` section, and commit it on branch k, before calling `openReview` for this bundle.
      Stage only the plan document, by explicit path, per the staging rules in `conventions.md`, list what is staged and confirm it carries only that one added marker line, and word it as bookkeeping rather than as a task: `chore(<issue-ref>): mark bundle k review pending`, naming no task in the body.
      That is the same kind of commit as the `- Review:` record below and `conventions.md` excludes it from task and commit reconciliation for the same reasons.
      Make it before branch k reaches the remote, so that whichever push puts the branch there carries it: the push below on an ordinary adapter, or the push `openReview` owns under `pushesForYou`.
      The marker means only that a run reached the point of calling `openReview` for that bundle: it is committed before the call, so the call may or may not have started and a review may or may not exist.
      Its job is to force the next run to look the review up rather than to prove that any review was created.
      Writing it ahead of the call is still the whole point, since once `openReview` has been entered a run that dies leaves no other trace that anything was tried at all.
    - Push branch k, unless the adapter declares `pushesForYou`, exactly as the single-review path does.
    - Call `openReview` with branch k, that base, a title naming the bundle, and a body built per the stack rules in `conventions.md`: the closing reference only in bundle N, plus `Part k of N`, plus `Depends on` the previous bundle's review URL for every bundle after the first.
      Pass the previous bundle's review id as `dependsOn` for every bundle after the first, and omit it for bundle 1.
      Those two are not two representations of one dependency: `dependsOn` is the contract's machine-readable argument, which an adapter with no dependency mechanism of its own ignores, while the `Depends on <url>` body line is prose for a human reviewer and carries no machine meaning, exactly as `conventions.md` and `../fathom-shared/forges/github.md` both state.
    - Branch on what `openReview` returned before doing anything with it, since the manual-handoff result defined in `../fathom-shared/forges.md` is a typed outcome of that call and carries no review id.
      When it is that result, there is no review object for this bundle: do not call `publishReview`, do not write a `- Review: <id> <url>` record for it, and stop and report the handoff for bundle k rather than continuing to bundle k+1.
      Writing a record from it would put an entry in the `Bundles` section with no id behind it, which the sweep reads as a review it can look up and cannot, and continuing would leave bundle k+1 with no id to pass as `dependsOn` and no URL for its `Depends on` line.
      Remove the pending marker written above as part of stopping, committing that removal as the same kind of bookkeeping commit, since this result says outright that no review object was created and a marker left behind would hold every later run on a bundle that provably has none.
      A stacked run should not normally reach this at all, because the manual tier never proposes a split, as `../fathom-shared/forges.md` states, and it is the only tier that hands a review off by hand.
      So treat this branch as a guard against an adapter that returns the handoff result from a non-manual tier, rather than as a path a correct run is expected to take, and say that plainly when it fires.
    - Call `publishReview` with the returned id.
    - Replace that bundle's `- Review: pending (bundle k/N)` marker with `- Review: <id> <url> (bundle k/N)` in the plan document's `Bundles` section, since the sweep looks reviews up by id and needs every one of them.
    - Commit and push that recorded line immediately, on branch k, before moving to bundle k+1's branch or doing anything else.
      Stage only the plan document, by explicit path, per the staging rules in `conventions.md`, and word it as bookkeeping rather than as a task: `chore(<issue-ref>): record bundle k review id`, naming no task in the body.
      Then do what those same staging rules require before every commit: list what is staged and confirm every part of it belongs to the work at hand, which here is the one `- Review:` line that replaced the marker and nothing else.
      Staging that document by path takes whatever else is already sitting in it, so when the staged diff carries an unrelated edit as well, unstage it rather than committing it and cleaning up later, and leave it in the working tree for the run's final closing commit to carry.
      `conventions.md` excludes plan document and bookkeeping commits from task and commit reconciliation, and a commit shaped this way is one of them, so it cannot be miscounted as the commit that implemented a task.
      Waiting for the run's final closing commit instead would leave bundle 1's review id uncommitted through bundles 2 and 3, where a sweep run from another clone cannot see it and an interrupted run leaves it on one machine's disk only.
    - Apply `inReview` when bundle 1's review publishes, and never again for the later bundles; the issue is genuinely in review from that moment and re-applying a phase it already holds reports progress that did not happen.
      A resumed run that reuses bundle 1's existing review publishes nothing, so apply `inReview` there instead, whenever the tracker still shows the issue in an earlier phase; read that phase from the tracker rather than assuming the interrupted run got as far as applying it.
      That is a phase update and nothing more: reusing a review never reopens it and never calls `publishReview` on it again.
      Later bundles keep this rule exactly as written and never apply the phase, whether their reviews were newly opened or reused.
    Skip the `openReview` call for a bundle whose review already exists and reuse that review, the same way the single-review path does, so a resumed run never opens a second review for a bundle that has one.
    Decide that from that bundle's entry in the `Bundles` section and from nothing else, since the pending marker above is written and committed before `openReview` is called and is therefore the only record that separates a bundle no run has tried to open a review for from a bundle where one may exist.
    Exactly one of four cases holds for bundle k.
    When the entry carries a full `- Review: <id> <url> (bundle k/N)` line, the review exists and is already recorded: reuse it, open nothing, change no record, and skip the lookup below entirely.
    When the entry carries no line at all beneath it, no run has ever reached this bundle's `openReview` call, because the marker is committed before the call and no run reaches the call without it, so no review can exist for this bundle: write the marker as the routine above says, open the review, and skip the lookup below entirely.
    That is the ordinary case on a first run through a stack, which is why a first run never stops here.
    When the entry carries a `- Review: pending (bundle k/N)` marker and no id, a run reached the call and recorded no outcome, so the call may or may not have started and a review may or may not exist: work through the lookup below, and hold wherever it cannot settle the question.
    When the entry carries a `- Review: none confirmed (bundle k/N)` line, the user has already confirmed for an earlier hold that no review exists for this bundle: replace that line with the pending marker as the routine above says, open the review, and skip the lookup below entirely.
    Do not read the remote's branch list as evidence in any of these four cases, and never treat a branch the remote does not carry as proof that no review was opened from it.
    A forge retains a review after its head branch is deleted, and nothing in the lifecycle rules prevents a bundle branch being deleted or reused before its `- Review:` record is durable, so branch absence cannot tell a bundle no run ever reached from one whose review was opened and whose branch later went away.
    The pending marker records that a run got as far as the call instead, and it is the only evidence this procedure accepts on that question.
    On the pending case, ask the forge with `findReviewByBranch` for branch k, which returns bounded candidate records carrying each review's id, its URL, and its base, as `../fathom-shared/forges.md` defines the operation, then keep only the candidates whose base is exactly the base `resolveBase` returned for this bundle.
    Bundle branches chain, so a head branch can carry a review opened against a different base than this bundle now targets; matching on the exact head and base pair is what keeps this bundle's commits out of that review, and the base in the candidate record is what makes that match possible at all.
    When exactly one candidate survives that filter, that review exists and belongs to this bundle, so back its id and URL into the record first, then call `getReviewState` on that id to decide whether this run may continue.
    The state decides continuation and never whether the record may be written: the candidate came back from the forge keyed on this bundle's exact head and base, which makes the id true whatever the review's fate turns out to be, and a merged, closed, or undetermined review whose id goes unrecorded is exactly the bundle the sweep reads as missing a record forever.
    Then read the state and act on it.
    On `open`, carry on with the rest of this routine for bundle k, which is the ordinary recovery.
    On `merged`, carry on the same way: the bundle's outcome is known and good, its review needs no reopening, and its id is now recorded, so the sweep can see that bundle merged.
    On `closed-unmerged`, stop and hold after recording, naming bundle k and saying its review was abandoned, since whether to retry, rescope, or drop that work is the user's judgment exactly as it is in the sweep's own abandoned case.
    On `unknown`, stop and hold after recording, since nothing was learned about that review's fate and building the next bundle on an outcome this run never observed is the guess this whole lookup exists to avoid.
    Keep that candidate's URL alongside its id, since the backfill below records both and no other operation in the contract reports a review's URL.
    When more than one survives, stop and hold naming them, since choosing between two candidate reviews by guess is the failure this pairing exists to prevent.
    When no candidate matches at all, do not call `openReview`: stop and hold instead.
    A lookup that comes back with nothing matching does not establish that nothing exists, because the list is bounded and can leave out a review that is really there, as `../fathom-shared/forges.md` states, and the pending marker is exactly the state an earlier run leaves behind when it was interrupted around its `openReview` call.
    Say in the hold report that bundle k carries a pending marker, that a review may already exist for this bundle, that this run could not find one and cannot prove there is none, and that the user should confirm whether a review exists for that bundle before the run continues.
    Say with it what unblocks the next run, since a hold with no stated remedy leaves the bundle blocked forever: when the user confirms that no review exists, replace bundle k's marker with a `- Review: none confirmed (bundle k/N)` line in the `Bundles` section, committed and pushed on branch k as the same bookkeeping commit the recording step below makes, and the next run opens that bundle's review rather than holding again.
    When the user instead finds a review that does exist, record it as a full `- Review: <id> <url> (bundle k/N)` line the same way, and the next run reuses it.
    Either confirmation belongs in the `Bundles` section, because that is where the next run reads it; a confirmation given only in conversation leaves the durable record unchanged and every later run holds identically.
    When the resolved adapter omits `findReviewByBranch`, which `../fathom-shared/forges.md` says is legitimate, no lookup is possible at all: say once that the forge cannot be asked, then hold on exactly those same terms, since a pending marker with no id beside it says nothing about whether the call that followed it created a review.
    Holding costs one confirmation on a run that was interrupted between marking bundle k pending and recording its review, while opening blindly costs a duplicate review that no record names and the sweep can never reconcile, so the hold is the cheaper of the two.
    A matched candidate does not skip the two recording steps above it, whatever its state, and this is where a resumed run otherwise loses a bundle.
    That bundle's entry carries the pending marker, since the marker is what brought this run into the lookup at all: replace it now with a real `- Review: <id> <url> (bundle k/N)` line built from the id and URL on the candidate record that matched, then commit it exactly as the recording step above does: stage only the plan document, by explicit path, verify the staged diff carries only that one replaced line before committing, and word it as the same bookkeeping commit.
    Push it on branch k before anything else, including before any hold the state above calls for, since a record that never leaves this clone closes none of the gaps below.
    Then continue or hold as that state directs.
    Without that backfill the review exists on the forge and nothing in the repository names it, so the sweep never learns its id, step 7 keeps reading that bundle as the one in progress, and the completeness rule in step 2 leaves the whole issue undecided forever.
    A bundle whose entry already carries its full `- Review:` line never reaches the lookup at all: its record is already durable, so it changes nothing and makes no commit.
    A bundle with no line at all is unaffected by any of this and runs the routine above unchanged.
    After bundle N's routine completes, close the parent task in the memory backend (a no-op for the checklist adapter, whose file is the parent record), which is the one action the single-review path takes that no bundle routine has taken yet.
    Then skip the single-review path above entirely and continue into the closing actions below, which run once for the issue rather than once per bundle.
    The parent task is closed exactly once either way: the single-review path closes it before opening its review, and a stacked issue closes it here, after the last bundle's review and before the issue's completion comment.

    Finally, post a completion comment on the issue, including the done-on-merge note from `asana.md` when the tracker is Asana, then write `- Finalization: complete` into this issue's plan document per `conventions.md`, and commit and push the task-state files this run changed as a final closing commit so the branch carries the completed state, staging them by explicit path per the staging rules in `conventions.md`: the beads JSONL export and `metadata.json` when beads is the backend, and this issue's files under `.fathom/`; never sweep `.beads/` or `.fathom/` as directories, since the beads database and runtime files are intentionally ignored and must not ride into the review.
    Write that line last, after every other closing action has been taken, since it records that they were: a line written earlier would claim a finalization that had not happened and the check at the top of this step would then skip the rest of it forever.
    It rides this same closing commit, so it becomes durable at the moment the completed task state does, and this commit is the only one that carries it on a run that reaches here normally.
    Push this closing commit with an ordinary `git push` of the branch even when the adapter declares `pushesForYou`, since that capability governs only the push that opens the review, as `../fathom-shared/forges.md` states; skipping it here would leave the completed task state in the local clone while the review reads as finished.
    On a stacked issue this closing commit goes on branch N, the stack tip, because that branch contains every bundle's history and is the only one whose review shows the completed task state.
    Say plainly at handoff, when the issue was split, that its record carries `- Merge-closer: suppressed`, so the merge-closer Action will take no action for it however its bundles merge.
    On a repository that relies on that Action for closure this is a real change: a stacked issue reaches `done` only when a later run's done-on-merge sweep sees every bundle merged, where a single-review issue still closes on merge without one.
    The alternative is worse, since the Action matches branch names and every bundle records one, so the first bundle to merge would close the whole issue and the sweep would then read it as complete and never correct it.
12. Report a final summary: the issue, the review URL when one was opened, every bundle's review URL in order when the issue was split into a stack, or the resolved tier when no review was opened, the tracker's current phase, and the task counts from `status()`.

## Display overlay

When the running agent exposes built-in task-list capabilities, mirror progress into them for a live view; follow the display-overlay rule in `memory.md` and never treat that view as authoritative.
