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
