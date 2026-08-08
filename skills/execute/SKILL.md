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
2. Run the done-on-merge sweep for the resolved tracker; the mechanics are described in `../fathom-shared/trackers.md` and are tracker-agnostic, with each adapter file defining only its own closure action for the merged path.
   This sweep is itself tracker work, so it only runs once preflight has verified the MCP.
   When the invocation itself was a cleanup phrase, run only this sweep, report what it found, then stop; do not continue into the rest of this procedure.
   Treat any claim about a review's fate as a cleanup phrase, whether it says merged, closed, abandoned, landed, or shipped, and whether it names an issue or asks to clean up whatever is outstanding.
   Never act on the claim itself: confirm each referenced review's real state through `getReviewState` first, then apply the merged path or the closed-without-merging path accordingly, and say plainly when the confirmed state differs from what the user described.
   When the resolved forge declares `reviewLookup: none`, the claim cannot be confirmed at all. Say that plainly and act on nothing; do not close an issue on the strength of an unverifiable claim, since a wrong close is exactly what the confirmation step exists to prevent.
   An issue split into a stack has one recorded review per bundle rather than one in total, so call `getReviewState` on every recorded id before deciding anything about the issue.
   Move the issue to `done` only when every bundle reports `merged`.
   When some bundles are merged and others are still open, close nothing: report the partial progress, naming which bundles merged, then run the restack check below.
   When any bundle reports `closed-unmerged`, apply the closed-without-merging path for that bundle, name which bundles above it in the stack are now orphaned by it, and neither close the issue nor restack anything; whether to retry, rescope, or drop the orphaned work is the user's judgment call.
   When the adapter declares `reviewLookup: none` the whole sweep is unavailable here as it already is for single reviews, so say so once and act on nothing.

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
7. Ensure a feature branch exists for this issue; when one must be created, prefix its name from the issue type (`feat/` for a feature, `fix/` for a bug, `chore/` for a chore, `docs/` for docs, `feat/` by default) followed by the issue ref and a short title slug; skip creation when a matching branch already exists.
   Resolve the base branch per the base-branch rules in `../fathom-shared/forges.md`, then fetch it and create the new branch from the fetched remote copy rather than from a local copy that may be behind, since branching from a stale local copy is the usual cause of conflicts at merge time.
   When the branch already exists and the base branch has moved on since, bring it up to date before implementing, and report that you did.
   When that update conflicts, stop and hold exactly as an unfixable test failure would: keep the work, leave the task in progress, report which files conflict, and let the user decide how to resolve them; never resolve a conflict by discarding either side's changes.
   These rules describe bundle 1's branch, which is the only branch a single-review run has.
   When step 8 confirms a stack, later bundles take the same name with their index appended, so bundle 2 of `feat/ONC-5-add-webhooks` is `feat/ONC-5-add-webhooks-2`.
   Create each of those from the previous bundle's branch at the moment that bundle starts, not up front: creating them all at breakdown time would leave empty branches behind whenever a run stops early.
8. Ensure the breakdown exists.
   - Skip the rest of this step when a breakdown already exists for this issue.
   - Call `init` for the issue, then call `parentTask` for it.
   - When the issue has no existing children, plan three to seven units of work, each sized so it can be implemented and verified on its own; for each one, call `createSubIssue` first, then call `createTask` with the newly created sub-issue's ref as `subIssueRef`, then write the returned task id back onto that sub-issue so the link reads both ways, since the task id does not exist until `createTask` returns, setting `deps` to the id of the task it builds on so tasks chain sequentially by default whenever order matters.
   - When the issue already has children, call `listSubIssues` to adopt them instead of inventing a new breakdown; for each adopted sub-issue, still call `createTask`, passing that sub-issue's existing ref as `subIssueRef` and skipping `createSubIssue` since the sub-issue already exists, then write the returned task id back onto that sub-issue the same way, and setting `deps` the same way.
   - Decide whether this issue produces one review or a stack, once the child tasks exist and before any dependency edge is added.
     Read the profile's `stacking` field per `../fathom-shared/approval.md`; treat an absent field as `propose`, and stop considering a split immediately when it reads `never`.
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
   - After every child task exists, add the parent's dependency edge on each child, so the parent cannot close before its children and "no open children" becomes a real signal rather than an assumption.
   - Either way, write the plan document described in `conventions.md` and commit it with the breakdown.
   - Write `.fathom/tasks/<ISSUE-REF>.md` only when the resolved backend is the checklist adapter, since that file holds checkbox statuses; with beads active the statuses live in beads and no file belongs there, as `memory.md` states.
9. Call `updateState` to move the issue to the `inProgress` phase.
10. Run the implementation loop until `claimNext` reports nothing claimable.
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
    - When this issue was split into a stack and the closed task was the last one in its bundle, run the per-bundle finish routine in step 11 for that bundle before claiming again, then, when a later bundle remains, create the next bundle's branch from this one and continue the loop on it.
      Do not wait until the loop drains to open any review: building each bundle on the correct branch from the start is what avoids having to cherry-pick commit ranges onto a chain of branches afterwards.
    - On a failure that cannot be fixed, stop and hold: keep the change, leave the task in progress, report the failure, and exit without continuing the loop.
      On a stacked issue, also name which bundles already have open reviews and which were never built, since some of the work is already in front of reviewers and the user needs to know which part held.
    One commit per task, always, even when two tasks touch the same file.

11. Once `claimNext` returns none remaining, finish the issue.
    This step has two mutually exclusive paths, and exactly one of them runs.
    A single-review issue follows the single-review path immediately below, then the closing actions at the end of this step.
    A stacked issue skips that path entirely and goes straight to the closing actions, because step 10 already opened every one of its reviews through the per-bundle routine further down.
    Running the single-review path on a stacked issue would reconcile the whole issue against a single bundle's commit range, write a second review record in a format the sweep does not read, and move the issue to `inReview` a second time.
    A stacked issue also never enters this step on its own: step 10 invokes the per-bundle routine directly, and bundle N's routine runs the closing actions once as it finishes.
    So when the loop afterwards drains and `claimNext` returns none, this step has already completed for that issue, and nothing in it runs a second time.

    The single-review path, for an issue that was not split into a stack:

    Run the commit reconciliation from `conventions.md` and stop if the task and commit counts disagree.
    Commit any leftover uncommitted change that belongs to this issue's tasks, leaving unrelated working-tree edits alone rather than sweeping them into the review.
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

    Finally, post a completion comment on the issue, including the done-on-merge note from `asana.md` when the tracker is Asana, and commit and push the task-state files this run changed as a final closing commit so the branch carries the completed state, staging them by explicit path per the staging rules in `conventions.md`: the beads JSONL export and `metadata.json` when beads is the backend, and this issue's files under `.fathom/`; never sweep `.beads/` or `.fathom/` as directories, since the beads database and runtime files are intentionally ignored and must not ride into the review.
    Push this closing commit with an ordinary `git push` of the branch even when the adapter declares `pushesForYou`, since that capability governs only the push that opens the review, as `../fathom-shared/forges.md` states; skipping it here would leave the completed task state in the local clone while the review reads as finished.
    On a stacked issue this closing commit goes on branch N, the stack tip, because that branch contains every bundle's history and is the only one whose review shows the completed task state.
12. Report a final summary: the issue, the review URL when one was opened or the resolved tier when one was not, the tracker's current phase, and the task counts from `status()`.

## Display overlay

When the running agent exposes built-in task-list capabilities, mirror progress into them for a live view; follow the display-overlay rule in `memory.md` and never treat that view as authoritative.
