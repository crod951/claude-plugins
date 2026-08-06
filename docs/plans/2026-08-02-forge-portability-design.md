# Forge Portability — Design

> **Date:** 2026-08-02
> **Status:** Proposed
> **Responds to:** `docs/plans/Workbench skill — forge portability feedback.md`
> **Branch:** `feat/multi-forge-support`

## Problem

Workbench abstracts the tracker and hardcodes the forge.

`trackers.md` defines eight named operations, isolates each tracker's tools behind an adapter file, and instructs the agent to discover tool names at runtime (`agents.md:29`). It states the principle outright at `trackers.md:5`: never call tracker tools directly from a core skill body.

The forge gets none of that. `gh` and GitHub-specific concepts are invoked directly from shared contract files and from `execute`'s procedure body. A non-GitHub forge therefore cannot be added by writing an adapter — it requires editing the shared contracts. On a machine without `gh`, `trackers.md:69-78` stops the run before any work begins, in both approval modes.

The motivating environment is an **internal enterprise forge**. That has a consequence worth stating early, because it shapes the whole design: **we cannot ship adapters for these forges.** We do not know their names, hosts, or CLIs. A contract populated only with `forges/github.md` and a few public siblings does nothing for a team on `code.example.internal`. The contract is necessary but not sufficient — the deliverable is the contract *plus a supported path for a team to write their own adapter without forking this repo.*

## Non-goals

Declared explicitly so they are not half-built:

- **Multi-repo reviews.** The feedback doc's trait #4 (a review spanning several repositories, merged as one unit). Workbench's branch model, `.workbench/` layout, and memory contract are single-repo end to end. Supporting this needs a different memory design, not an adapter.
- **Shipping adapters for specific public non-GitHub forges.** GitLab, Gerrit, Forgejo and others become additive once the contract exists. None are in this change.
- **Changing GitHub's draft-PR behavior.** See issue 5 below — real, deferred deliberately.
- **Removing the legacy `- PR:` checklist field.** Additive now, removed after repos have cycled.
- **CI check awareness.** `docs/workbench.md:407` already lists this as a known limitation. The contract makes it reachable later; it is not built here.

## The forge contract

A new `skills/workbench-shared/forges.md`, mirroring `trackers.md`, with adapters under `skills/workbench-shared/forges/`. Naming follows the existing `trackers.md` + `trackers/` pattern.

### Operations

| Operation | Purpose |
| --- | --- |
| `verifyForge()` | Cheap read-only preflight check. Returns verified or unverified; nothing else. |
| `resolveBase(branch)` | Confirm the base branch exists on the remote and is a valid merge target. |
| `openReview(branch, base, title, body)` | Create the review. The adapter decides whether this also pushes. Returns a stable review id and URL. |
| `publishReview(id)` | Move a draft review to notified-review state. A no-op where the forge does not distinguish. |
| `getReviewState(id)` | Return `open`, `merged`, `closed-unmerged`, or `unknown`, plus a merge timestamp when merged. |

Five operations, not six. The feedback doc proposed `capabilities()` as a sixth; capabilities are static facts about a forge rather than a runtime call, so they are declared in the adapter file instead — the same way tracker adapters declare their typical tool names as a starting hint.

### Declared capabilities

Every adapter file declares this table. Absent means false.

| Capability | Values | Drives |
| --- | --- | --- |
| `ciHooks` | true / false | Whether the merge-closer question is asked at all. |
| `draftState` | true / false | Whether `publishReview` is meaningful, and when `inReview` is applied. |
| `pushesForYou` | true / false | Whether the skill pushes the branch or `openReview` owns the push. |
| `reviewLookup` | `by-id` / `none` | Whether the done-on-merge sweep can run. |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | Reserved; no behavior in this change. |

Capabilities matter because forges differ in kind, not just in command names — the same lesson `agents.md:24-27` already records for tracker MCP builds with different tool coverage.

`stackedReviews` is declared but unused. It is included now because adding a capability key later means revisiting every adapter file, and the feedback doc documents a genuine model difference (GitHub retargets branches and auto-rebases on upstream merge; the evaluated forge uses declared dependencies with a manually scoped commit range and no auto-rebase).

## Adapter resolution

Resolution and detection are distinct, and conflating them is the trap. **Explicit configuration resolves. Detection only suggests an answer to a question the user is asked.** An internal forge on an unrecognized host matches no bundled adapter, so URL parsing can never be the primary mechanism — at best it recognizes GitHub.

Resolution order, first match winning:

1. **`.workbench/forge.md`** — a repo-local adapter. Wins over everything.
2. **The profile's `forge:` field** naming a bundled adapter, e.g. `forges/github.md`.
3. **`forge: none`** in the profile — pins tier 3 (below) and suppresses all offers.
4. Nothing configured → run first-run forge setup.

First-run forge setup asks one question, seeded with whatever detection can offer:

- Match the `origin` remote host against bundled adapters. A `github.com` host suggests `github`.
- Otherwise probe `PATH` for candidate forge CLIs and name what was found.
- Otherwise offer the manual tier.

The answer is recorded in `.workbench/config.md` as `forge:`, so the question is asked once per repository.

### The repo-local adapter path

`.workbench/forge.md` is the deliverable that actually serves an unknown internal forge. A team writes one file describing their forge's five operations and capability table, commits it to their own repository, and workbench uses it. No fork, no PR to this repo, no waiting on us.

This change ships an annotated template at `skills/workbench-shared/forges/TEMPLATE.md` and documents the path in `docs/workbench.md`.

## The three tiers

Capability tiers, with persistence as a separate axis rather than a fourth tier.

**Tier 1 — Adapter.** A resolved adapter, bundled or repo-local. Full operations; the declared capability table governs which paths run. GitHub is this tier today and its behavior is unchanged.

**Tier 2 — Assisted.** No adapter resolved, but a candidate forge CLI was found on `PATH`. Push the branch, then offer three choices: use the candidate for this run only, write `.workbench/forge.md` now so future runs are tier 1, or fall through to manual. **The agent never runs the candidate without that answer.**

**Tier 3 — Manual.** No adapter, no candidate, the user declined, or `forge: none` is pinned. Push the branch and print what a human needs to open the review by hand: branch, base, suggested title, suggested body. `getReviewState` is unavailable, so the done-on-merge sweep does not run.

`forge: none` is not a tier of its own — it is tier 3 made permanent, which stops the offer from recurring on every invocation.

### Adapter or nothing

Tier 2 exists in tension with the Absolute boundary (`execute/SKILL.md:9-18`, `trackers.md:132-136`), whose entire purpose is that a missing tool is a user decision rather than an obstacle to route around. An agent that discovers an unknown CLI and autonomously drives it to push code to a corporate server is exactly the improvisation that boundary forbids. The failure modes are concrete: guessed flags can push the wrong ref, publish a draft to a reviewer group prematurely, or file a review in the wrong project.

The rule that resolves the tension:

> **Anything the agent executes against a forge is authorized by a written adapter file, or by the user's explicit acceptance at the tier-2 stop of a named candidate for a single run. Never by an inference made in the moment.**

Tier 2's probe therefore produces a *suggestion*, and its best outcome is a committed `.workbench/forge.md` the team can review and correct. The probe is an on-ramp to tier 1, not a parallel improvisation path. Everything else the boundary already forbids continues to apply without exception: no credential scavenging, no direct HTTP API calls, no editing agent or MCP configuration.

### Tier 3 and the one-way ratchet

In tier 3 nothing can observe review state, so the done-on-merge sweep can never fire and issues accumulate in `inReview` permanently.

The design still applies `inReview` at open time — a human really did open a review, we simply cannot see it — but says so plainly at open time and records it in the profile. Silently becoming a one-way ratchet in exactly the restricted environments this change exists to serve would be the worst outcome available.

## The done-on-merge sweep, rebuilt

Two changes: key on review id rather than branch name, and stop pushing stamps to the base branch.

### ID-keyed lookup

At `openReview`, record the returned review id alongside the URL in the issue's file under `.workbench/`:

```text
- Review: <id> <url>
```

The sweep then calls `getReviewState(id)` per recorded id. Direct per-id lookups remove the pagination hazard the current text has to warn about (`trackers.md:85`: pass `--limit` above the repository's total PR count or older branches are silently skipped). This is better on GitHub too, independent of portability.

Branch name is retained as a display field only.

**Back-compat.** This change writes the `- Review:` line *in addition to* the existing `- PR:` line, and the sweep prefers the id when present, falling back to branch matching when it is absent. Existing repositories keep working with no migration step. Removing the fallback and the legacy field is the deferred follow-up.

### The stamp push is deleted

Today both sweep outcomes are made idempotent by appending a line to the issue's `.workbench/` file, committing it, and **pushing it to the base branch** (`trackers.md:91-98`). The push is essential — `trackers.md:92` concedes that a local-only stamp never propagates.

That requires write access to the base branch. Most shared repositories protect `main`. The push fails, `trackers.md:96` correctly reports and continues, and then the skip condition at `trackers.md:98` never fires because the line never landed durably. **The issue is re-swept on every invocation, forever.** This is a live GitHub defect, not a portability problem.

The two paths differ sharply in severity:

- **Merged:** mostly noise. `trackers.md:87-88` already re-reads issue state and skips the tracker write when the issue is complete. The stamp is redundant here.
- **Closed unmerged:** blocking. `trackers.md:109` reports *and asks the user*, and `approval.md:47` lists it as a safety stop that fires in **both** approval modes. Every invocation halts on the same dead review, and the user's answer is not persisted either, so answering does not help.

The replacement:

- **Merged path:** idempotency comes from tracker state, which the sweep already reads. No marker, no commit, no push.
- **Closed-unmerged path:** the marker becomes a **comment on the tracker issue**, carrying the sentinel `workbench: review-closed-unmerged <url> <date>`. Durable, visible from any clone, and writable without base-branch permission. Matched as a substring, since users reply in comment threads.

This deletes `trackers.md:91-98` and `:112-113` — the branch-placement cautions, and the three-way "apply before task work, or from a separate worktree, or defer and say so" choice. It also removes a documented data-loss footgun: `trackers.md:94` warns that a checkout or stash to place the stamp can lose the in-progress marker the memory contract treats as truth. The sweep becomes read-only against git.

Alternatives rejected: pushing the marker to the feature branch (dead for an abandoned review, often deleted after merge), and a dedicated state branch (new mechanism, still needs push access).

### Cost: a ninth tracker operation

`getIssue` returns title, description, type, URL, native id, state, and children — **not comments**. Reading the sentinel needs a new operation:

| Operation | Purpose |
| --- | --- |
| `listComments(ref)` | Return existing comment bodies on an issue, newest first. |

This takes the tracker contract from eight operations to nine and touches both tracker adapters. It is a real cost and the honest price of removing the stamp push. A separate operation is preferred over extending `getIssue`, which sits on the hot path of every run and should not carry a comment payload it usually does not need.

## Point-by-point response to the feedback

| # | Finding | Resolution |
| --- | --- | --- |
| 1 | `gh` is a hard preflight stop | **Accepted.** Preflight calls `verifyForge()` on the resolved adapter. Tiers 2 and 3 replace the stop with a degraded path. |
| 2 | Sweep keyed on branch names | **Accepted.** ID-keyed via `getReviewState(id)`, additive with branch fallback retained for back-compat. |
| 3 | Merge-closer writes GH Actions unconditionally | **Accepted.** The question is gated on `capabilities.ciHooks`. When false, record `merge-closer: none (forge has no hooks)` so the profile never asserts a capability that does not exist. |
| 4 | Push-then-open-PR assumed | **Accepted.** Push and review-open collapse into `openReview`; the `pushesForYou` capability tells the skill whether to push. |
| 5 | "Review opened" treated as "ready for review" | **Partially accepted.** `publishReview` and `draftState` are in the contract now; GitHub's `publishReview` is a no-op so this change is provably behavior-preserving. The GitHub draft-PR fix is deferred (below). |
| 6 | Stamp push assumes an unprotected base | **Accepted, fixed differently.** The proposed fix — use tracker state as the idempotency check — works for the merged path but not the closed-unmerged path, where the issue sits in `inReview` either way and there is no state to key on. Tracker comment covers both. |
| 7 | `agents.md` allowlists `gh` | **Accepted.** `agents.md:43` names the resolved forge's CLI rather than `gh`. |
| — | Stacked reviews deserve a capability flag | **Accepted as declaration only.** `stackedReviews` is declared; no behavior depends on it yet. |
| — | `getReviewState` could report CI checks | **Deferred.** Noted as reachable; not built. |

### Additional findings from this review

Not in the feedback doc:

- **`scaffold/SKILL.md:42` gates on `gh` verification, but scaffold never touches a forge.** It only creates tracker issues. This gate is deleted rather than ported to `verifyForge()`.
- **Base-branch resolution is misfiled.** `trackers.md:37-49` is a VCS/forge concern with nothing tracker-specific in it. It moves to `forges.md`.

## Deferred follow-ups

Tracked as separate work so this change stays reviewable:

1. **GitHub draft-PR behavior.** A draft PR currently moves the issue to `inReview` even though it is explicitly not ready. Drive `inReview` off `publishReview` on GitHub too.
2. **Checklist format migration.** Remove the legacy `- PR:` field and the sweep's branch-matching fallback once repositories have cycled through at least one run on the new format.

## Blast radius

| File | Change |
| --- | --- |
| `skills/workbench-shared/forges.md` | **New.** Contract, capability table, tiers, resolution order, base-branch resolution. |
| `skills/workbench-shared/forges/github.md` | **New.** Everything currently inline. Behavior-preserving. |
| `skills/workbench-shared/forges/generic-git.md` | **New.** Tier 3 fallback. |
| `skills/workbench-shared/forges/TEMPLATE.md` | **New.** Annotated adapter-authoring template. |
| `skills/workbench-shared/trackers.md` | Preflight calls `verifyForge()`; sweep rebuilt; stamp-push section deleted; base-branch section moved out; `listComments` added to the contract; merge-closer question gated on `ciHooks`. |
| `skills/workbench-shared/trackers/asana.md` | `listComments`; merge-closer offer gated on `ciHooks`. |
| `skills/workbench-shared/trackers/linear.md` | Same, plus its GitHub-integration logic conditioned on the resolved forge. |
| `skills/execute/SKILL.md` | Step 11 calls `openReview` then `publishReview`; step 1 preflight wording; tier-aware reporting; description trigger phrases made forge-neutral. |
| `skills/scaffold/SKILL.md` | Forge gate at `:42` deleted. |
| `skills/workbench-shared/approval.md` | The closed-unmerged stop stays and now fires once; tier-2 offer classified as a stop. |
| `skills/workbench-shared/memory/checklist.md` | `- Review:` field added; `- PR:` retained as legacy. |
| `skills/workbench-shared/agents.md` | Allowlist names the resolved forge CLI. |
| `skills/workbench-shared/conventions.md` | "Pull request" → forge-neutral vocabulary. |
| `docs/workbench.md` | Forge setup, the three tiers, repo-local adapter path, rewritten merge-closer section. |
| `README.md` | `gh` moves from unconditional prerequisite to GitHub-specific. |

Vocabulary: "pull request" is used exclusively across the repo today and "merge request" appears nowhere. Shared contracts move to **review**; the GitHub adapter keeps "pull request" where it names real `gh` behavior.

## Compatibility

- **Existing GitHub repositories:** no user-visible change. Same preflight outcome, same PR-opening behavior, same sweep results. The stamp push stops happening, which fixes the protected-branch defect for them.
- **Existing `.workbench/` files:** `- Closed:` lines continue to be read as valid markers forever; they simply stop being written.
- **Existing profiles:** a profile with no `forge:` field triggers the forge question on next load, following the repair pattern `trackers.md:166` already uses for `merge-closer`.
- **New tracker comments:** workbench will now write a comment to the user's tracker on an abandoned review. This is new outbound writes and is documented.
