# Forge Portability — Implementation Plan

> **Date:** 2026-08-02
> **Design:** `docs/plans/2026-08-02-forge-portability-design.md`
> **Branch:** `feat/multi-forge-support`

**Goal:** Extract a forge contract with adapters, so a non-GitHub forge is added by writing an adapter rather than by editing shared contracts — and so an unknown internal forge degrades gracefully instead of hard-stopping preflight.

**Architecture:** Mirror the existing tracker abstraction. A new `forges.md` defines five operations and a declared capability table; `forges/github.md` holds everything currently inline; `forges/generic-git.md` is the tier-3 fallback; `.workbench/forge.md` lets a team write their own without forking. Three capability tiers replace the single hard stop.

**Tech stack:** Markdown skill files. No application code — behavior is defined entirely by the prose contracts the agent reads at runtime.

**Sequencing rule:** the contract and adapters land before anything is rewired to call them, so no intermediate commit references an operation that does not yet exist.

---

## Phase A — The forge contract and its adapters

### Task A1: Write the forge contract

**Files:** Create `skills/workbench-shared/forges.md`

Mirror `trackers.md`'s structure and voice. Include:

- The opening rule, matching `trackers.md:3-5`: call the forge only through the contract; resolve the adapter at runtime before any forge work; never call forge tools directly from a core skill body.
- The five-operation table: `verifyForge`, `resolveBase`, `openReview`, `publishReview`, `getReviewState`.
- The declared-capability table: `ciHooks`, `draftState`, `pushesForYou`, `reviewLookup`, `stackedReviews`. State that absent means false, and that `stackedReviews` is declared but drives no behavior yet.
- Adapter resolution order, and the rule that **explicit configuration resolves while detection only seeds a question**.
- The three tiers (Adapter / Assisted / Manual), and `forge: none` as tier 3 pinned rather than a fourth tier.
- The **adapter-or-nothing** rule, cross-referencing the Absolute boundary in `execute/SKILL.md:9-18`.
- The tier-3 ratchet disclosure: `inReview` is still applied, and the run says plainly that nothing will auto-close it.
- The base-branch resolution section moved verbatim from `trackers.md:37-49`, retitled in review vocabulary.

**Verify:** `forges.md` names all five operations and all five capabilities; the base-branch text matches what `trackers.md` held.

### Task A2: Write the GitHub adapter

**Files:** Create `skills/workbench-shared/forges/github.md`

Everything currently inline, relocated unchanged in behavior:

- `verifyForge` → `gh auth status`, with the install/authenticate fix text from `trackers.md:73-75`.
- `openReview` → push the branch, then `gh pr create` against the base; return the PR number as the review id plus the URL.
- `publishReview` → **explicit no-op**, with a note that this is deliberate and the draft fix is a deferred follow-up.
- `getReviewState` → `gh pr view <id> --json state,mergedAt`; map to `open` / `merged` / `closed-unmerged`.
- Capabilities: `ciHooks: true`, `draftState: true`, `pushesForYou: false`, `reviewLookup: by-id`, `stackedReviews: retarget`.
- Carry over the prohibition from `trackers.md:73`: never call the GitHub HTTP API, never read tokens from disk or environment.

**Verify:** every `gh` invocation that exists anywhere in `skills/` today appears in this file.

### Task A3: Write the generic-git fallback adapter

**Files:** Create `skills/workbench-shared/forges/generic-git.md`

- `verifyForge` → verifies git and a reachable `origin` only; always passes when those hold.
- `openReview` → push the branch, then print branch, base, suggested title and body for a human to open the review by hand. Returns no review id.
- `publishReview` → no-op.
- `getReviewState` → always `unknown`.
- Capabilities: `ciHooks: false`, `draftState: false`, `pushesForYou: false`, `reviewLookup: none`.
- State the consequence: the sweep does not run, and the ratchet disclosure is required.

### Task A4: Write the adapter-authoring template

**Files:** Create `skills/workbench-shared/forges/TEMPLATE.md`

An annotated skeleton a team copies to `.workbench/forge.md`. Each operation carries a comment on what it must return and what breaks when it is wrong. Call out that `reviewLookup: none` is a legitimate answer, and that a partial adapter is better than none.

---

## Phase B — The tracker contract's ninth operation

### Task B1: Add `listComments` to the tracker contract

**Files:** Modify `skills/workbench-shared/trackers.md` (contract table, ~L12-24)

Add the row: `listComments(ref)` — return existing comment bodies on an issue, newest first. Update the "exactly these eight operations" wording at `trackers.md:9` to nine.

### Task B2: Implement `listComments` in both tracker adapters

**Files:** Modify `skills/workbench-shared/trackers/asana.md`, `skills/workbench-shared/trackers/linear.md`

Name each tracker's typical comment-listing tool, following the existing convention that listed tool names are a starting hint rather than a guarantee (`trackers.md:128-129`).

---

## Phase C — Rewire `trackers.md`

### Task C1: Replace the `gh` preflight with `verifyForge()`

**Files:** Modify `skills/workbench-shared/trackers.md:69-78`

Resolve the forge adapter, then call `verifyForge()`. Keep the one-pass property from `:71` — a user missing both dependencies gets one stop naming everything to fix. Failure no longer stops the run outright: it drops to the tier the resolution produced. Rewrite `:78` ("Only a verified MCP and a verified `gh` allow the run to begin") so a verified MCP alone allows a tier-2 or tier-3 run to begin.

### Task C2: Move base-branch resolution out

**Files:** Modify `skills/workbench-shared/trackers.md:37-49`

Delete the section, leaving a pointer to `forges.md`. Update every in-repo reference to "the base-branch rules in `trackers.md`" — `execute/SKILL.md:67` is one.

### Task C3: Rebuild the sweep on review ids

**Files:** Modify `skills/workbench-shared/trackers.md:80-98`

- Replace the `gh pr view` / `gh pr list` mechanics at `:85` with `getReviewState(id)` per recorded id.
- Prefer the `- Review:` id; fall back to branch matching when only a legacy `- PR:` line exists.
- Skip the sweep entirely when `reviewLookup: none`, saying so once.
- Delete the stamp-push block at `:91-98` in full.
- Keep the merged path's existing state re-read at `:87-88` and make it the sole idempotency mechanism.
- Delete the `--limit` pagination warning; direct id lookup removes the hazard.

### Task C4: Move the closed-unmerged marker to a tracker comment

**Files:** Modify `skills/workbench-shared/trackers.md:100-115`

- Keep the reporting and the question at `:106-109` unchanged.
- Replace the recorded `.workbench/` line at `:111-113` with a `comment()` carrying the sentinel `workbench: review-closed-unmerged <url> <date>`.
- The idempotency check is `listComments` plus a substring match on the sentinel, explicitly not "the last comment says".
- Keep `:114-115`: a different review later closed unmerged is new information and is reported again; a recorded abandonment never blocks a later merge from closing the issue normally.
- Keep reading legacy `- PR closed unmerged:` lines as valid markers.

### Task C5: Add the forge question to first-run setup, and gate merge-closer

**Files:** Modify `skills/workbench-shared/trackers.md:138-198`

- Add the forge question to the numbered sequence, seeded by remote-host match then `PATH` probe. Record as `forge:`.
- Gate the merge-closer question at `:163-166` on `capabilities.ciHooks`. When false, skip the question and record `merge-closer: none (forge has no hooks)`.
- Add `forge:` to the profile format block at `:184-194`.
- Extend the repair pattern at `:166` so a profile with no `forge:` field gets the question on next load.
- Update the step count in the "must run these five steps" wording at `:145`.

---

## Phase D — Tracker adapters

### Task D1: Gate Asana's merge-closer offer

**Files:** Modify `skills/workbench-shared/trackers/asana.md:55-78`

Condition the GitHub Action offer and the native-integration recommendation on `ciHooks`. Keep the workflow template; scope it explicitly to GitHub-capable forges.

### Task D2: Gate Linear's merge-closer and condition its integration logic

**Files:** Modify `skills/workbench-shared/trackers/linear.md:26-73`

Same gating. Additionally, the `Closes <ref>` behavior and the "skip `updateState(done)` because the integration handles it" logic at `:26-40` are GitHub-integration specific — condition them on the resolved forge being GitHub. On any other forge, Linear closes through `updateState` as normal.

---

## Phase E — Skill bodies and shared contracts

### Task E1: Rewrite `execute` step 11 on the forge contract

**Files:** Modify `skills/execute/SKILL.md:96`

- Replace "push the branch, and open the pull request with the `gh` command-line tool" with `openReview(branch, base, title, body)`, and honor `pushesForYou`: when true the skill must **not** push separately.
- Call `publishReview(id)` after, then `updateState(inReview)`.
- Record `- Review: <id> <url>` alongside the existing `- PR:` line.
- Add the tier-3 branch: no review opened, print the manual handoff, apply `inReview`, and state the ratchet disclosure.
- Leave the reconciliation, staging, and closing-commit rules at `:96` untouched — they are already forge-neutral and `conventions.md:73-78` is load-bearing.

### Task E2: Update `execute` preflight and reporting

**Files:** Modify `skills/execute/SKILL.md:50-58, 97`

- `:53` — stop only when the tracker MCP does not verify; forge non-verification selects a tier instead.
- `:57-58` — cleanup-phrase handling stays, but a claim about a review's fate cannot be confirmed when `reviewLookup: none`; say so rather than confirming.
- `:97` — the final summary reports the review URL when there is one, and the tier when there is not.

### Task E3: Make `execute`'s trigger phrases forge-neutral

**Files:** Modify `skills/execute/SKILL.md:3`

Keep the GitHub-flavored phrases (users say "PR"), add review-neutral equivalents so the skill routes on other forges' vocabulary too.

### Task E4: Delete scaffold's forge gate

**Files:** Modify `skills/scaffold/SKILL.md:42`

Remove the GitHub CLI clause. Scaffold creates tracker issues and never touches a forge; the tracker-MCP stop stays exactly as it is.

### Task E5: Update `approval.md`

**Files:** Modify `skills/workbench-shared/approval.md:36-47`

- The closed-unmerged stop at `:47` stays a never-skipped stop; note it now fires once per abandoned review rather than on every run.
- Preflight's never-skipped stop at `:36-41` narrows to the tracker MCP.
- Classify the tier-2 offer as a stop that fires in both modes — auto mode must not pick a forge CLI unattended.

### Task E6: Add the review-id field to the checklist format

**Files:** Modify `skills/workbench-shared/memory/checklist.md:7, 16, 31, 40, 45`

Add `- Review: (filled at open)`. Keep `- PR:` as a legacy field that is read but no longer the primary key. Update the `init` and `parentTask` descriptions accordingly.

### Task E7: Update the agent allowlist

**Files:** Modify `skills/workbench-shared/agents.md:43`

Replace the literal `gh` with the resolved forge adapter's CLI, keeping `gh` as the GitHub example.

### Task E8: Neutralize vocabulary in shared contracts

**Files:** Modify `skills/workbench-shared/conventions.md:78, 80-90`, plus residual "pull request" uses in `trackers.md` and `memory.md:65`

Shared contracts say "review". The GitHub adapter keeps "pull request" where it names real `gh` behavior. `memory.md:65` currently justifies the no-dual-truth invariant partly by the merge-closer Action's `grep` — restate it forge-neutrally.

---

## Phase F — Documentation

### Task F1: Rewrite the forge sections of the workbench guide

**Files:** Modify `docs/workbench.md:41, 121-130, 152, 161, 197-198, 299-336, 392, 407, 438`

- Requirements (`:41`) and setup (`:121-130`): `gh` is a GitHub-specific requirement, not universal.
- Add a section on the three tiers and what each does.
- Add a section on writing `.workbench/forge.md`, pointing at `TEMPLATE.md`.
- Rewrite "How the tracker learns a PR merged" (`:319-336`) around `ciHooks` rather than three GitHub arrangements.
- Document the new tracker comment as new outbound writes.
- Update the lifecycle diagram (`:299-305`) to review vocabulary.
- Note in troubleshooting (`:392`) that the protected-branch stamp failure is fixed.

### Task F2: Update the README

**Files:** Modify `README.md:31, 38`

Move the GitHub CLI from an unconditional prerequisite to a GitHub-specific one; mention multi-forge support in the skill description.

---

## Phase G — Verification and release

### Task G1: Reconcile the SkillSpector baseline

**Files:** Modify `.skillspector-baseline.yaml` (L63-69, L75)

Two suppression reasons reference the GitHub Action template and an `ASANA_TOKEN` GitHub secret. Update the reasons to match the gated behavior. Run `bin/scan-skills.sh` and resolve any new non-suppressed finding — new prose about probing `PATH` for CLIs is plausible new-finding territory.

### Task G2: Bump the plugin version

**Files:** Modify `.claude-plugin/plugin.json`, then run `bin/sync-versions.sh`

Minor bump to `1.1.0` — additive contract, behavior-preserving on GitHub. Add a `forge` keyword; `plugin.json` is the source of truth and the script propagates to `marketplace.json` and `README.md`.

### Task G3: End-to-end read-through

No automated test covers skill prose, so verify by reading:

- Every operation named in a skill body exists in a contract file.
- No `gh` invocation survives outside `forges/github.md`.
- Every `trackers.md` line number referenced from another file still resolves.
- The GitHub path reads identically in behavior to `main` — this change is behavior-preserving on GitHub, and any difference is a defect.

---

## Risks

- **Prose contracts have no compiler.** A dangling operation name or stale cross-reference fails silently at runtime, inside an agent. Task G3 is the only thing standing in for a type checker; it is not optional.
- **The nine-operation tracker contract touches Asana and Linear equally.** If either MCP lacks a comment-listing tool, the closed-unmerged marker has no home on that tracker and the design needs a per-tracker fallback. Verify tool coverage during Task B2 before Phase C depends on it.
- **Tier 2 is where the Absolute boundary is most likely to erode.** The adapter-or-nothing rule must be stated in `forges.md` itself, not only in this plan.
