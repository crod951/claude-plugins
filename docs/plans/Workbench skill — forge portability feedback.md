# Workbench skill — forge portability feedback

Feedback for `crod951/skills` (workbench v1.0.0), prepared 2026-08-02.

Context: I evaluated whether `execute` and `scaffold` could run in an environment whose git hosting and code review system are not GitHub. The tracker abstraction held up well. The forge layer did not. Everything below is about that gap.

The specific review system is not important to the findings, so this writeup describes it generically as "the other forge." What matters is its shape, and these traits are common to several non-GitHub review systems (Gerrit is the closest widely-known analogue):

- **A review is a set of commits, not a branch.** It has a stable review ID. There is no way to look up a review by branch name, and no CLI subcommand that lists reviews.
- **The review CLI pushes the review ref itself.** Running `git push` manually is explicitly discouraged and produces a wrong branch state.
- **Reviews are created as drafts.** The diff is mutable and reviewers are not notified until a separate publish step.
- **A review can span multiple repositories** and is reviewed and merged as one unit.
- **CI checks are configured per-repository, independent of any GitHub-Actions-like mechanism.** There is no `.github/workflows` equivalent.

All findings were verified against the skill source at commit `HEAD` of `crod951/skills`, plus that forge's public-facing CLI documentation and a live CLI run. Line numbers refer to files under `skills/`.

## Root cause

**The tracker is abstracted. The forge is not.**

`trackers.md` defines eight named operations, isolates each tracker's tools in an adapter file, and instructs the agent to discover tool names at runtime rather than hardcoding them (`agents.md:29`). It even states the principle explicitly:

> Never call tracker tools directly from a core skill body; always go through the operations named here. (`trackers.md:5`)

The forge gets none of that treatment. `gh` and GitHub-specific concepts are called directly from shared contract files and from `execute`'s procedure body. The result is that a non-GitHub forge cannot be supported by adding an adapter — it requires editing the shared contracts.

Coupling is concentrated, which is good news for the fix. Counting lines mentioning `gh`/`github`/`pull request`/`PR`:

| File | Hits |
|---|---|
| `workbench-shared/trackers.md` | 27 |
| `workbench-shared/trackers/asana.md` | 17 |
| `workbench-shared/trackers/linear.md` | 14 |
| `execute/SKILL.md` | 10 |
| `workbench-shared/conventions.md` | 3 |
| `workbench-shared/approval.md` | 2 |
| `workbench-shared/memory/checklist.md` | 2 |
| `scaffold/SKILL.md` | 2 |
| `workbench-shared/agents.md` | 1 |
| `workbench-shared/memory/beads.md` | 1 |
| `workbench-shared/memory.md` | 0 |

`memory.md`, `memory/beads.md`, and most of `conventions.md` are already forge-neutral. The work is contained in three files plus the two tracker adapters.

## Blocking issues

### 1. `gh` is a hard preflight stop, so nothing runs at all

`trackers.md:69-75` makes the GitHub CLI part of preflight, verified with `gh auth status`, with a missing binary and an unauthenticated one treated identically as unverified. `approval.md:36-41` lists unverified preflight among the stops auto mode never skips.

On a machine without `gh`, or in an environment where the GitHub CLI is not available, the skill stops before reading the tracker, before the sweep, before any work. There is no partial-capability path — no way to say "this repo's forge is something else."

**Suggested fix:** make the forge check a lookup against a resolved forge adapter rather than a hardcoded `gh` check. Preflight should verify *the forge this repo actually uses*.

### 2. The done-on-merge sweep is keyed on branch names, not review IDs

`trackers.md:85` finds merged work by matching branch names recorded under `.workbench/` against `gh pr list --state all --json headRefName,state,mergedAt`.

Two separate problems:

- `gh` is GitHub-only (issue 1).
- **The design assumes reviews are discoverable by branch name.** On a forge where a review is a set of commits keyed by review ID, with no list-reviews command, branch-name lookup has nothing to bind to. Reviews spanning multiple repos make it worse.

This is the one finding I would call an architectural issue rather than a tooling one. It is also worth noting the ID-keyed approach is *better on GitHub too*: storing the PR number and looking it up directly avoids the pagination hazard the current text has to warn about (`--limit` above total PR count, else older branches are silently skipped).

**Suggested fix:** record the review's stable ID (PR number, or the other forge's review ID) in `.workbench/` at open time, and have the sweep do direct per-ID lookups through a forge adapter. Keep the branch name as a display field only.

### 3. The merge-closer offers write GitHub Actions workflows unconditionally

`asana.md:76-78` and `linear.md:68-73` offer to write `.github/workflows/workbench-close.yml`, and first-run setup asks the merge-closer question for both trackers (`trackers.md:163-166`).

On a forge with no GitHub Actions equivalent, this offer is a dead end: accepting it writes a file that will never execute, and records `merge-closer: installed` in the profile — which then tells the sweep that something else owns closure when nothing does. That is worse than declining, because the profile now asserts a capability that does not exist.

**Suggested fix:** gate the merge-closer question on the resolved forge advertising a CI-hooks capability. When it does not, skip the question and record `merge-closer: none (forge has no hooks)` so the sweep knows it is the sole closure mechanism.

### 4. Push-then-open-PR is assumed, and conflicts with forges that push for you

`execute/SKILL.md:96` instructs: push the branch, then open the pull request with `gh`.

The other forge inverts this: its CLI pushes the review ref itself, and pushing manually is explicitly discouraged because it creates the wrong branch state. So the sequence in step 11 is not merely unsupported there, it is actively harmful.

**Suggested fix:** collapse "push" and "open review" into a single forge operation (`openReview`) and let the adapter decide whether that involves a push.

### 5. "Review opened" is treated as equivalent to "ready for review"

`execute/SKILL.md:96` moves the issue to `inReview` at the moment the PR is opened.

On a draft-by-default forge, the review is created with a mutable diff and no reviewer notification; publishing is a separate act. The tracker would say "in review" while nobody can see the work.

**This is not purely an other-forge problem.** GitHub draft PRs have exactly the same shape — a draft PR moves the issue to `inReview` today even though it is explicitly not ready. The current behavior is arguably already wrong on GitHub.

**Suggested fix:** separate `openReview` from `publishReview`, and drive the `inReview` transition off publication.

### 6. The sweep's stamp push assumes an unprotected base branch

`trackers.md:91-97` appends a `- Closed: <date>` line and pushes it to the base branch. On failure it reports and continues (good), but `trackers.md:98` means the issue is then re-reported on every subsequent run, forever.

**This is a live GitHub bug, not a portability issue.** Any repo that protects `main` — which is most shared GitHub repos — hits this permanently. The sweep's idempotency depends on write access to the protected branch.

**Suggested fix:** persist the closed-stamp somewhere that does not require a protected-branch push. The tracker itself is the obvious candidate — the issue is already in the `done` state, so re-reading state (which `trackers.md:87-88` already does) can serve as the idempotency check without any commit at all.

### 7. `agents.md` tells users to allowlist `gh`

`agents.md:43` instructs pre-approving `git`, `gh`, and `bd`. Minor, but it should name the resolved forge's CLI rather than `gh` specifically.

## Suggested shape of the fix: a forge contract

The cleanest change is a `forge.md` that mirrors `trackers.md`, with adapters under `forge/`. Roughly:

| Operation | Purpose |
|---|---|
| `verifyForge()` | Cheap read-only preflight check; returns capability flags. |
| `resolveBase()` | Confirm the base branch exists on the remote and is a valid merge target. |
| `openReview(branch, base, title, body)` | Create the review. Adapter decides whether this pushes. Returns a stable review ID and URL. |
| `publishReview(id)` | Move from draft to notified-review, where the forge distinguishes them. |
| `getReviewState(id)` | Return `open` / `merged` / `closed-unmerged` plus merge timestamp. |
| `capabilities()` | Advertise `ciHooks`, `draftState`, `pushesForYou`, `stackedReviews`. |

Then:

- `trackers.md` preflight calls `verifyForge()` instead of `gh auth status`.
- The sweep calls `getReviewState(id)` per recorded ID.
- The merge-closer question is gated on `capabilities().ciHooks`.
- `execute` step 11 calls `openReview` then `publishReview`, with `inReview` following publication.

A `forge/github.md` adapter would hold everything currently inline, and the existing behavior is preserved exactly. Other forges (GitLab, Gerrit, Phabricator, and the one I tested) become additive.

The capability flags matter because forges differ in kind, not just in command names — which is the same lesson `agents.md:24-27` already records for tracker MCP builds that expose different tool coverage.

## What ports without changes

Worth stating, because the majority of the design is sound:

- **The tracker contract.** Eight operations, adapters isolated, runtime tool discovery. Adding a third tracker looks straightforward.
- **The memory contract.** `memory.md` has zero forge coupling. The beads adapter is unaffected.
- **Commit conventions, the plan document, staging safety, commit verification, reconciliation.** All VCS-neutral and genuinely useful. The reconciliation step (`conventions.md:73-78`) is the strongest safety feature in the skill, and it guards a hazard that is universal across forges rather than specific to any one of them: **every forge reviews committed work only, so anything left staged or uncommitted is silently absent from the review.** Gerrit inherits this from plain `git push` — its upload docs discuss only commits and describe no dirty-tree check. `gh pr create`'s documentation is likewise silent on uncommitted changes. An autonomous loop that implements a task but fails to commit it therefore opens a review that is missing that work, with no error anywhere. Reconciliation catches exactly this via the task/commit count mismatch, which is why I would treat it as load-bearing rather than optional.
- **Approval modes.** The skip-list / never-skip-list split (`approval.md`) is well-reasoned, and the closing note about classifying each new stop is a good maintenance discipline.
- **The absolute boundary on credentials.** Refusing to scavenge tokens or edit MCP config is exactly right, and it is what made this skill worth evaluating for a restricted environment at all.

## Two smaller notes

**Stacked reviews are a real capability difference, worth a capability flag.** GitHub stacking is branch retargeting, with auto-retarget when the upstream merges. On the forge I tested, stacking is a declared dependency plus a manually scoped commit range, with no auto-rebase — and the merge engine independently blocks a review whose base commit is not yet on the destination branch. A skill that wanted to stack would need to know which model it is on.

**`docs/workbench.md:407` already lists "No CI awareness" as a known limitation.** Combining that with a forge contract would let `getReviewState` also report check status, which closes the gap without new machinery.

---

Scope note: I did not run `execute` end to end against the other forge, so these are findings from reading the skill source plus verifying forge behavior independently. Issues 1–4 are certain (direct contradictions with documented forge behavior). Issues 5–7 are read from the code and reasoned against documented forge semantics, not observed failures.
