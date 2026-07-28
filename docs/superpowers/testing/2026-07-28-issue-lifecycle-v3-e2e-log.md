# Issue Lifecycle v3 - E2E Matrix Log

Fixtures: il-test-app (github.com/crod951/il-test-app), Asana workspace "My Company" project "Issue Lifecycle Test" (sections Backlog / To do / In Progress / In Review / Done), beads v0.49.0, Kiro IDE with skills symlinked and Asana MCP via ~/.kiro/settings/mcp.json.

## Combo 4: Kiro + Asana + beads

### Intake (removeItem requirements)

- Skill triggered unprompted from natural-language requirements: PASS
- Done-on-merge sweep ran before tracker work: PASS
- Tracker resolved to Asana via connected-MCP check (no profile yet): PASS
- Destination: single project found and presented in draft (approval doubles as the ask-once): PASS with note
- Draft shown before any creation, includes inferred type (Feature): PASS
- Sub-issue count 5 (within 3-7), independently implementable units: PASS
- Awaiting user approval at time of logging.

### Lifecycle (combo 4, first attempt): FAIL - one root cause, clean downstream code

Root cause: Kiro did not read the ../shared/ docs ("shared steering files aren't present in this environment") and improvised the entire run from SKILL.md alone.
The skill contained no guard requiring it to stop when references are unreadable.

Downstream deviations, all traceable to the root cause:
- Memory resolution skipped: bd installed but beads never used; improvised checklist file instead (combo 4's backend requirement failed).
- Checklist file never updated: all 5 tasks still unchecked after implementation; claim/close cycle never ran; status truth broken.
- Branch used full GID (feat/1216966075616004-remove-item) instead of the asana-<last6> ref scheme.
- Single mega-commit for all 5 tasks instead of per-task commits.
- config.md improvised (workspace/project GIDs, no state mapping at all); first-run confirmation never asked.
- Generated checklist used em dashes and a non-spec format.

What still worked from SKILL.md alone: trigger, branch prefix, implementation quality (13/13 tests), PR body (Closes URL, completed tasks, HEROC-ish test plan), Asana subtask completion, In Review claim, completion comment (per Kiro transcript; Asana API verification pending - V1 MCP call hung).

Fix: harden both SKILL.md "Read first" sections - explicit path anchor (relative to the SKILL.md file's own directory; ~/.kiro/skills/shared/ for Kiro global installs) plus a stop-if-unreadable guard forbidding improvised contracts. Rerun follows.

### Intake rerun after fix ff4cc5e (applyDiscount): PASS

- Shared docs read this time; tool-name discovery and section inspection followed trackers.md.
- First-run profile proposed in exact spec format (state-mapping block) and gated on approval together with the draft.
- 4 sub-issues (within 3-7), type inferred, draft shown before any creation.
- The stop-guard/path-anchor fix resolved the improvisation failure end to end at the intake phase.

### Lifecycle rerun (applyDiscount, combo 4): implementation phase PASS, interrupted at PR open

- Memory resolution correct: fresh run + bd available -> beads adapter, bd init, parent task created.
- Adopt path exercised live: 4 existing Asana sub-issues adopted into beads tasks (the review-cycle Critical fix verified end to end).
- Per-task loop correct: claim -> implement -> test -> commit -> close, one commit per task (615.1-615.4), 16/16 tests passing.
- Branch and ref scheme correct: asana-176679.
- FINDING (adapter gap): the V1 Asana MCP exposes no section-move tool, so updateState's mapped section move cannot execute; agent degraded to a comment. asana.md needs an explicit fallback chain for MCP builds without a section tool. V2 server migration may also resolve this.
- Run interrupted by Kiro model rate limit at PR-open. Cross-session resume test follows: new conversation, "work on asana-176679", expect guards to skip to finish (PR, inReview, completion comment) with no duplicate work.

### Cross-session resume (combo 4): PASS

- New Kiro conversation, "work on asana-176679": guards read repo state (beads + checklist + open PR), skipped all completed work, executed only the finish steps (remaining closes, completion comment, overlay sync).
- No duplicate commits, no re-implementation. PR: il-test-app #2, 16/16 tests.
- Section move to In Review again blocked by V1 MCP (no section tool); degraded to comment consistently. Combo 4 verdict: PASS with the known adapter gap.

### Done-on-merge sweep + V2 server (formatPrice intake): PASS

- Sweep fired first, found no Closed stamp, verified PR merged via gh, applied done.
- V2 MCP enabled the real section move: task moved to Done section AND completed flag set (V1 could only comment).
- Closed stamp appended and committed (fa57582); idempotency in place for future runs.
- Intake continued with destination from saved profile, zero prompts; draft gated with type inferred.
- Kiro V2 config via mcp-remote proxy worked (registered app, localhost:3334 OAuth).

### Sweep idempotency + already-closed issue (combo 4): PASS

- Re-invoking lifecycle on the closed asana-176679: sweep saw the Closed stamp and did not re-close; guards found all work complete; run reported done and pushed a straggler closing commit.
- Note: the run never reached memory resolution because every guard short-circuited on the closed issue, so the beads-without-binary stop-guard test moves to an open issue.

### Combo 3 (Kiro + Asana + checklist, formatPrice): PARTIAL PASS

Working: sweep idempotency; URL parse + asana-945428 ref; adopt path (4 subtasks); checklist file created with sub-issue links and final states; V2 section moves (In Progress, In Review); mid-run debugging (negative currency format) with 24/24 tests; PR #3 with done-on-merge note; final closing commit (fix-3 behavior exercised).

Deviations (all prose-adherence, Kiro model):
- Stop-guard bypassed: .beads present + bd hidden should stop; agent reasoned per-issue and used checklist. Guard text confirmed readable via symlink.
- Checklist format improvised: check marks and em dashes instead of the spec marker legend; statuses recorded only at the end, not cycled per claim/close.
- Tasks batched: 4 tasks in 2 commits despite the per-task commit rule in step 9.
- Merge-closer ask never fired despite the profile lacking a merge-closer line (fix 43354c2 was live).

Response: inline the highest-value invariants directly in SKILL.md (backend stop rule, no-batching prohibition, profile-load checks pointer); accept that prose adherence varies by model and document it. bd restored to PATH after the run.
