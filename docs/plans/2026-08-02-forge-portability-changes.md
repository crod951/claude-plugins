# Forge Portability — Change Summary

> **Branch:** `feat/multi-forge-support` → `main`
> **Date:** 2026-08-02
> **Version:** workbench 1.0.0 → 1.1.0
> **Design:** [`2026-08-02-forge-portability-design.md`](./2026-08-02-forge-portability-design.md)
> **Plan:** [`2026-08-02-forge-portability-plan.md`](./2026-08-02-forge-portability-plan.md)
> **Responds to:** [`Workbench skill — forge portability feedback.md`](./Workbench%20skill%20—%20forge%20portability%20feedback.md)

---

## In one paragraph

Workbench abstracted the tracker but hardcoded GitHub, so supporting another forge meant editing shared contract files rather than adding an adapter — and on a machine without `gh`, preflight stopped the run before any work began, in both approval modes. This branch extracts a five-operation forge contract with adapters, mirroring the existing tracker abstraction, and adds three capability tiers so an unresolvable forge degrades to a manual handoff instead of a hard stop. **On GitHub the behavior is unchanged**, except that two live defects are fixed. Everything else is additive.

**Net:** +1,299 / −123 across 22 files. Four new files carry the contract and its adapters; the rest is rewiring.

---

## Why this was needed

`trackers.md:5` already states the principle the forge layer never followed:

> Never call tracker tools directly from a core skill body; always go through the operations named here.

The tracker gets eight named operations, per-tracker adapter files, and runtime tool discovery. The forge got none of it: `gh` was invoked directly from shared contract prose and from `execute`'s procedure body. The result was that a non-GitHub forge could not be supported by adding an adapter.

The motivating environment is an **internal enterprise forge**, which shapes the whole design: we cannot ship adapters for forges whose names, hosts, and CLIs we have never seen. A contract populated only with `github.md` would not help anyone on `code.example.internal`. So the deliverable is the contract **plus a supported path for a team to write their own adapter without forking this repo**.

---

## The measurable result

Real `gh` invocations (`gh pr`, `gh auth`, "GitHub CLI"), by file:

| File | Before | After |
|---|---|---|
| `workbench-shared/trackers.md` | 5 | **0** |
| `execute/SKILL.md` | 1 | **0** |
| `scaffold/SKILL.md` | 1 | **0** |
| `workbench-shared/forges/github.md` *(new)* | — | 7 |

"Pull request" in shared contracts (`trackers.md`, `conventions.md`, `approval.md`, `memory*.md`, `execute`, `scaffold`): **32 → 0**. It survives only in `forges/github.md` and inside the GitHub-scoped sections of the tracker adapters, where it names real GitHub behavior.

**One counter-intuitive number, called out deliberately:** "GitHub" mentions *increased* in the tracker adapters — `asana.md` 7 → 11, `linear.md` 3 → 7. That is the change working as intended. Those files always contained GitHub-specific logic (the GitHub App, the Actions template, Linear's GitHub integration); it was simply unmarked. The new text says so out loud — "Everything in this section assumes the resolved forge is GitHub" — so a reader can tell scoped behavior from universal behavior. Implicit coupling became explicit scoping.

---

## New API surface

### The forge contract — `skills/workbench-shared/forges.md` (new, 150 lines)

| Operation | Purpose |
|---|---|
| `verifyForge()` | Cheap read-only preflight. Returns verified/unverified, nothing else. |
| `resolveBase(branch)` | Confirm the base branch exists on the remote and is a valid merge target. |
| `openReview(branch, base, title, body)` | Create the review. **Owns the push.** Returns a stable review id and URL. |
| `publishReview(id)` | Draft → notified review. No-op where the forge does not distinguish. |
| `getReviewState(id)` | `open` / `merged` / `closed-unmerged` / `unknown`, plus a merge timestamp. |

Five operations, not six. The feedback doc proposed `capabilities()` as a runtime call; capabilities are static facts about a forge, so they are **declared in the adapter file** instead — the same pattern tracker adapters use for tool-name hints.

### Declared capabilities

| Capability | Values | Drives |
|---|---|---|
| `ciHooks` | true / false | Whether the merge-closer question is asked at all. |
| `draftState` | true / false | Whether `publishReview` is meaningful. |
| `pushesForYou` | true / false | Whether `openReview` owns the push or the caller pushes first. |
| `reviewLookup` | `by-id` / `none` | Whether the done-on-merge sweep can run. |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | Reserved; no behavior yet. |

`stackedReviews` is declared but unused. It is included now because adding a capability key later means revisiting every adapter file, and the model difference is real (GitHub retargets branches and auto-rebases on upstream merge; Gerrit-shaped forges use declared dependencies with a manually scoped commit range and no auto-rebase).

### The ninth tracker operation

`listComments(ref)` was added to the tracker contract (`trackers.md` 8 → 9 operations) and mapped in both adapters. It exists solely so the sweep can read markers it wrote on an earlier run — see the closed-unmerged fix below. This is the one place the change touches the tracker contract, and it is the honest cost of removing the stamp push.

---

## Two live defects fixed

Both were in the feedback doc; neither is a portability issue. **These are the changes most worth reviewing carefully**, because they alter GitHub behavior.

### 1. The stamp push could never succeed on a protected branch

Recording a merge meant appending a `- Closed:` line to the issue's `.workbench/` file, committing it, and **pushing it to the base branch** (`trackers.md:91-98`). The old text conceded at `:92` that a local-only stamp never propagates, so the push was load-bearing.

Most shared repos protect `main`. The push failed, `:96` correctly reported and continued, and then the skip condition at `:98` never fired — because the line never landed. **The issue was re-swept on every invocation, forever.**

**Fix:** deleted entirely. `trackers.md:87-88` already re-read issue state and skipped the write when the issue was complete, so the merged path was *already* idempotent; the stamp was redundant. Tracker state is now the sole mechanism, and the sweep writes and pushes nothing.

This also removes a documented data-loss footgun — the old `:94` warned that checking out or stashing to place the stamp could lose the in-progress marker the memory contract treats as truth.

### 2. The closed-unmerged path re-asked forever, in both approval modes

Worse than the above, because the merged path had tracker state to fall back on and this one did not: the issue sits in `inReview` whether or not it has been reported. `trackers.md:109` reports **and asks the user**, and `approval.md:47` lists it as a stop that fires in *both* modes — and the user's answer was persisted nowhere, so answering did not help.

**Fix:** the marker is now a comment on the tracker issue carrying a sentinel:

```text
workbench: review-closed-unmerged <review url> <date>
```

Matched as a substring across the whole comment stream, not by inspecting the newest comment — users reply in threads. A comment needs no branch write access and is visible from every clone.

**Fallback:** when a tracker MCP exposes no comment-listing tool, this falls back to the old file-based marker, with its protected-branch limitation now stated out loud rather than silent.

---

## Behavior changes by audience

### If you are on GitHub

Nothing changes except the two fixes above. Same preflight outcome, same PR opening, same sweep results. `publishReview` is an explicit no-op on the GitHub adapter specifically so this is provably behavior-preserving.

One improvement that is not portability-related: the sweep now looks each review up **by id** instead of matching branch names against a listed set. The old text had to warn you to pass `--limit` above your repo's total PR count, because the default caps at 30 and a capped listing silently skips older recorded branches. Direct id lookup removes the failure mode rather than warning about it — a bound that drops the oldest records is a defect that grows quietly with repo age.

### If you are on another forge

You now have three tiers instead of a hard stop:

| Tier | When | What happens |
|---|---|---|
| **Adapter** | An adapter resolved and verified | Everything. Reviews opened, issues closed on merge. |
| **Assisted** | No adapter, but a forge CLI is on `PATH` | Branch pushed, then asked: use it once, write an adapter, or hand off. **Never unattended.** |
| **Manual** | No adapter, no candidate, or `forge: none` | Branch pushed; you get branch, base, title, body to open the review yourself. Sweep does not run. |

To get tier 1 on a forge workbench does not ship, copy `forges/TEMPLATE.md` to `.workbench/forge.md`, fill in five operations, commit. A repo-local adapter beats every bundled one, so no fork is needed and teammates who clone get it automatically.

### If you use Asana or Linear

Workbench will now **write a comment to your tracker** when it finds an abandoned review. That is new outbound activity and is documented in the guide.

The merge-closer question is skipped entirely on a forge with no CI hooks, recording `merge-closer: none (forge has no hooks)`. Previously, accepting the offer on such a forge wrote a workflow file that would never execute and recorded `installed` — telling the sweep that something else owned closure when nothing did.

---

## The safety rule worth reviewing

Tier 2 probes `PATH` for forge CLIs, which sits close to the Absolute boundary in `execute/SKILL.md:9-18` — the rule that a missing tool is a user decision, not an obstacle to route around. The reconciliation, stated in `forges.md` itself and not only in planning docs:

> **Anything the agent executes against a forge is authorized by a written adapter file, or by the user's explicit acceptance at the assisted-tier stop of a named candidate for a single run. Never by an inference made in the moment.**

The probe reports what it found and stops. Its best outcome is a committed `.workbench/forge.md` the team can review and correct. Accepting a probed CLI is classified in `approval.md` as a stop that fires in **both** approval modes — auto mode removes questions, never safety stops.

Rationale: an agent driving an unfamiliar CLI unattended can push the wrong ref, publish a draft to a reviewer group before the work is ready, or file a review in the wrong project — all with the user's credentials against the user's server.

---

## Compatibility

**No migration is required.**

| Existing state | What happens |
|---|---|
| `.workbench/config.md` with no `forge:` field | Next run asks the forge question and repairs the profile, using the same repair pattern `trackers.md:166` already applies to `merge-closer`. |
| `.workbench/` record with a branch and no review id | Sweep falls back to branch matching, then rewrites the record with an id — the fallback drains rather than becoming permanent. |
| Legacy `- Closed:` and `- PR closed unmerged:` lines | Still read as valid markers forever. Simply no longer written. |
| `- PR:` checklist field | Kept as a read-only legacy line alongside the new `- Review:` line. |

The `!` on commit `46b9108` marks a breaking *contract* change (the sweep's key and the marker's location), not a breaking *upgrade*. Nothing in an existing repo needs touching.

---

## File-by-file

### New

| File | Lines | What |
|---|---|---|
| `workbench-shared/forges.md` | 150 | The contract, capability table, resolution order, three tiers, adapter-or-nothing rule, ratchet disclosure, base-branch resolution. |
| `workbench-shared/forges/github.md` | 92 | Every `gh` invocation, relocated. Behavior-preserving. |
| `workbench-shared/forges/generic-git.md` | 77 | Tier-3 fallback. `reviewLookup: none`, manual handoff. |
| `workbench-shared/forges/TEMPLATE.md` | 107 | Annotated skeleton for `.workbench/forge.md`. |

### Modified

| File | ± | What |
|---|---|---|
| `workbench-shared/trackers.md` | +76 / −47 | Preflight → `verifyForge`; sweep rebuilt on review ids; stamp push deleted; closed-unmerged marker → tracker comment; base-branch section moved out; `listComments` added; forge question added to first-run (5 → 6 steps); merge-closer gated on `ciHooks`; `forge` added to the profile format. |
| `execute/SKILL.md` | +28 / −9 | Step 11 → `openReview`/`publishReview`, honoring `pushesForYou`; manual-tier branch; review-id recording; preflight no longer stops on the forge; cleanup phrases refuse to act when `reviewLookup: none`; `forges.md` added to *Read first*; trigger phrases made forge-neutral. |
| `workbench-shared/trackers/asana.md` | +15 / −4 | `listComments` (filtering system stories); merge-closer gated on `ciHooks`; GitHub App and Actions sections explicitly scoped to GitHub. |
| `workbench-shared/trackers/linear.md` | +8 / −3 | `listComments` (inline-in-`getIssue` builds handled); merge-closer gated; GitHub-integration logic scoped to the GitHub forge. |
| `workbench-shared/memory/checklist.md` | +8 / −4 | `- Review:` field added to the format and to `init`; `- PR:` kept as legacy. |
| `workbench-shared/approval.md` | +6 / −2 | Preflight stop narrowed to the tracker MCP; closed-unmerged stop notes it now fires once; tier-2 acceptance added as a never-skipped stop. |
| `workbench-shared/conventions.md` | +5 / −3 | Review vocabulary; states the universal "every forge reviews committed work only" hazard the commit reconciliation guards. |
| `scaffold/SKILL.md` | +2 / −1 | Forge gate deleted — scaffold creates tracker issues and never opens a review, so the gate was a bug rather than a portability issue. |
| `workbench-shared/agents.md` | +1 / −1 | Allowlist names the resolved adapter's CLI, with `gh` as the GitHub example. |
| `workbench-shared/memory.md` | +1 / −1 | No-dual-truth invariant restated forge-neutrally; now names the review id. |
| `docs/workbench.md` | +80 / −35 | New **Forges** section (tiers, repo-local adapters); merge-closer section rewritten around `ciHooks`; requirements, setup, first-run table, lifecycle diagram, troubleshooting, limitations, upgrading. |
| `README.md`, `.claude-plugin/*`, `.skillspector-baseline.yaml` | +32 | v1.1.0 bump and sync; `forge` / `code-review` keywords; `gh` moved to a GitHub-specific prerequisite; two suppression reasons reconciled for `ciHooks` gating. |

---

## Deliberately deferred

Excluded so this change stays behavior-preserving on GitHub and therefore reviewable. Both are tracked.

1. **GitHub draft-PR behavior** (`wb-y3n.8.1`). A draft PR currently moves the issue to `inReview` even though it is explicitly not ready — a real defect, and the feedback doc is right about it. The contract now has `publishReview` and `draftState` to fix it with; mixing "make it portable" with "change what it does on the forge everyone uses" would make this diff unreviewable.
2. **Removing the legacy `- PR:` field and branch fallback** (`wb-y3n.8.2`). Wait until repos have cycled through at least one run on the new format.
3. **CI check awareness.** `docs/workbench.md` already lists this as a known limitation. `getReviewState` makes it reachable later; not built here.

**Non-goals**, declared so they are not half-built: multi-repo reviews (the memory model is single-repo end to end), and shipping adapters for specific public non-GitHub forges (additive once the contract exists).

---

## Verification

### Done

- **SkillSpector v2.5.1: PASS.** `execute` 0 active / 0 suppressed, `scaffold` 0 active / 2, `workbench-shared` 0 active / 8. The new `PATH`-probing and forge-CLI prose introduced zero findings. All nine baseline suppressions still match live findings, so none went stale despite the Phase C deletions.
- **Static read-through: PASS.** No `gh` outside `forges/github.md`; all 5 forge and 9 tracker operations resolve to a contract file; all 5 capabilities declared in the contract and all three adapters; no dangling cross-file references; step counts and profile format consistent.

### Not done — please treat as open

- **`listComments` tool coverage is unconfirmed against live MCPs** (`wb-y3n.7.4`). No Asana or Linear MCP was connected while this was written, so those tool names are documented hints — the same status every other tool name in those adapters has, but not a confirmation. If either tracker cannot list comments, the sentinel falls back to the file marker, which is already specified, so this is a confirmation task rather than a blocker.
- **No end-to-end run.** Skill prose has no compiler and no test harness; the static read-through stands in for one. A tier-1 GitHub run and a forced tier-3 run (`forge: none`) are the two highest-value manual checks.

---

## Suggested review order

1. `workbench-shared/forges.md` — the contract everything else refers to.
2. `workbench-shared/forges/github.md` — confirm it preserves current GitHub behavior exactly.
3. `workbench-shared/trackers.md`, sweep and closed-unmerged sections — the two defect fixes, and the largest diff.
4. `execute/SKILL.md` step 11 — the one place a skill body opens a review.
5. `workbench-shared/forges/TEMPLATE.md` — the actual deliverable for internal forges; worth reading as a user would.
6. Everything else is vocabulary, gating, and docs.
