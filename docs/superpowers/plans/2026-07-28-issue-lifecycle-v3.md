# Issue Lifecycle v3 Clean-Room Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the v2 command-based issue-lifecycle plugin with a clean-room, agent-portable skill set (Claude Code + Kiro) driving Asana or Linear issues from requirements to an open PR.

**Architecture:** Two core skills (`issue-lifecycle`, `issue-intake`) written in capability language with zero tool names, backed by three adapter axes in `skills/shared/`: tracker adapters (Asana, Linear) behind an 8-operation contract, memory adapters (beads, markdown checklist) behind a 6-operation contract, and one thin per-agent notes file.
Runtime probing resolves adapters; a committed tracker profile (`.issue-lifecycle/config.md` in the consumer repo) holds state mappings and default destinations.

**Tech Stack:** Markdown skill files per the open Agent Skills standard (SKILL.md), Claude Code plugin packaging, `bd` (beads CLI), `gh` CLI, Asana MCP, Linear MCP.

**Spec:** `docs/superpowers/specs/2026-07-28-issue-lifecycle-v3-design.md` - the implementer MUST read it before starting any task.

## Global Constraints

- Work in repo `/Users/christopherrodrigues/Desktop/Projects/claude-plugins` on branch `feat/issue-lifecycle-v3`.
- Clean-room rule: never open, copy from, or reference files in the `slickage-claude-plugins` repository.
- Never use the em dash character; use plain `-`.
- In all skill/reference markdown, put each full sentence on its own line.
- Core skills (`skills/issue-lifecycle/SKILL.md`, `skills/issue-intake/SKILL.md`) must contain zero MCP tool names (nothing matching `mcp_`), zero `bd ` commands, and zero agent-specific tool names (TaskCreate, TaskUpdate, Glob, Grep).
  Capability language only; concrete tools live in adapters.
- Every SKILL.md needs frontmatter: `name`, `description` (with third-person trigger phrasing "This skill should be used when..."), `version: 3.0.0`.
- Version 3.0.0 everywhere; `bin/sync-versions.sh` syncs plugin.json, README, marketplace.json - the pre-commit hook runs it automatically, so commit README/marketplace version mismatches never by hand-editing but by letting the hook sync (verify after commit).
- Tracker state phases are exactly: `inProgress`, `inReview`, `done`.
- Tracker contract operations are exactly: `getIssue`, `listSubIssues`, `listDestinations`, `resolveDestination`, `createIssue`, `createSubIssue`, `updateState`, `comment`.
- Memory contract operations are exactly: `init`, `createTask`, `claimNext`, `close`, `status`, `parentTask`.
- Issue refs: Linear = native key (lowercased in branches); Asana = `asana-<last 6 digits of GID>` + title slug in branches, full URL recorded in checklist file and PR body.
- Consumer-repo artifacts: `.issue-lifecycle/config.md` (tracker profile, committed), `.issue-lifecycle/tasks/<ISSUE-REF>.md` (plan + checklist, committed on feature branch, kept permanently).

---

### Task 1: Remove v2 and scaffold the v3 plugin skeleton

**Files:**
- Delete: `plugins/issue-lifecycle/commands/issue-start.md`, `plugins/issue-lifecycle/commands/issue-task.md`, `plugins/issue-lifecycle/commands/issue-finish.md`, `plugins/issue-lifecycle/commands/commit.md`
- Modify: `plugins/issue-lifecycle/.claude-plugin/plugin.json`
- Create: directories `plugins/issue-lifecycle/skills/issue-lifecycle/`, `plugins/issue-lifecycle/skills/issue-intake/`, `plugins/issue-lifecycle/skills/shared/trackers/`, `plugins/issue-lifecycle/skills/shared/memory/`

**Interfaces:**
- Produces: plugin.json with `"version": "3.0.0"` that later tasks' files live under; directory tree matching the spec's Section 1 layout.

- [ ] **Step 1: Delete the v2 commands directory**

```bash
git rm -r plugins/issue-lifecycle/commands
```

- [ ] **Step 2: Update plugin.json**

Read the existing file first, keep `name` and any marketplace-required fields, set:

```json
{
  "name": "issue-lifecycle",
  "version": "3.0.0",
  "description": "Drive a tracker issue (Asana or Linear) from requirements to an open PR. Agent-portable skills for Claude Code and Kiro with resumable, task-tracked implementation runs."
}
```

- [ ] **Step 3: Create the skill directory tree**

```bash
mkdir -p plugins/issue-lifecycle/skills/issue-lifecycle \
         plugins/issue-lifecycle/skills/issue-intake \
         plugins/issue-lifecycle/skills/shared/trackers \
         plugins/issue-lifecycle/skills/shared/memory
```

- [ ] **Step 4: Verify**

Run: `ls plugins/issue-lifecycle/commands 2>&1; cat plugins/issue-lifecycle/.claude-plugin/plugin.json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['version']=='3.0.0', d; print('ok')"`
Expected: "No such file or directory" for commands; "ok" for the version.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/issue-lifecycle
git commit -m "feat(issue-lifecycle)!: remove v2 commands, scaffold v3 skill layout"
```

After committing, run `git show --stat HEAD` and confirm the pre-commit version-sync hook did not leave README/marketplace.json out of sync (`grep -n "issue-lifecycle" README.md .claude-plugin/marketplace.json | grep -i version` - if they show 2.1.0 they will be synced by the hook on the next commit that touches them; that is fine).

---

### Task 2: Tracker contract and resolution (`shared/trackers.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/trackers.md`

**Interfaces:**
- Produces: the 8-operation tracker contract table, the runtime resolution procedure, and the first-run tracker profile procedure.
  Adapter files (Tasks 3-4) implement this contract; core skills (Tasks 8-9) reference operations by these exact names.

- [ ] **Step 1: Write `trackers.md`**

The file must contain these sections, written fresh (sentence per line):

1. `# Tracker adapters` - one paragraph: skills call the tracker only through this contract; resolve the adapter at runtime; never call tracker tools directly from a core skill body.
2. `## The contract` - a table with exactly these rows and a purpose column written in your own words:
   - `getIssue(ref)` - fetch title, description, type/labels, URL, native id, state, existing children.
   - `listSubIssues(ref)` - existing child issues with id, title, state (used by adopt).
   - `listDestinations()` - where a top-level issue can be created (Asana projects, Linear teams), stable id + display name.
   - `resolveDestination(hint?)` - turn a hint or the tracker profile's default into a native destination id; null if ambiguous.
   - `createIssue(title, description, type, destination)` - returns ref + URL.
   - `createSubIssue(parentRef, title, description)` - returns ref + URL.
   - `updateState(ref, phase)` - phase is `inProgress` | `inReview` | `done`, applied via the tracker profile mapping.
   - `comment(ref, body)` - post a comment.
3. `## Runtime resolution` - the decision procedure:
   - Reference shaped like `ABC-123` means Linear; an Asana URL or bare GID means Asana.
   - Ambiguous reference: check which tracker MCP is connected; if both, ask the user once.
   - Discover the connected MCP's actual tool names at runtime; adapter files list typical names but builds vary.
   - Resolved tracker's MCP not connected: stop with a clear message naming the missing MCP; never fall back to the other tracker.
4. `## First-run tracker profile` - the setup procedure exactly as specced:
   - Trigger: no `.issue-lifecycle/config.md` in the repo (check other local branches for a newer one before prompting).
   - List what the project has (Linear: workflow states; Asana: board sections and status custom fields), propose a mapping for the three phases, user confirms or corrects.
   - Save to `.issue-lifecycle/config.md`, committed; include the default destination for intake.
   - Include a fenced example of the config file format:

```markdown
# issue-lifecycle tracker profile
tracker: asana
default-destination: Prototypes (1209000000000001)
state-mapping:
  inProgress: section "In Progress"
  inReview: section "Review"
  done: section "Done" + completed
```

   - Subsequent runs read the profile silently; a mapped state that no longer exists, or an explicit user request, re-runs setup; merge conflicts in the profile are resolved by re-running setup.

- [ ] **Step 2: Verify**

Run: `grep -c "getIssue\|listSubIssues\|listDestinations\|resolveDestination\|createIssue\|createSubIssue\|updateState\|comment" plugins/issue-lifecycle/skills/shared/trackers.md`
Expected: count >= 8.
Run: `grep -n "config.md" plugins/issue-lifecycle/skills/shared/trackers.md | head -1`
Expected: at least one hit.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/trackers.md
git commit -m "feat(issue-lifecycle): add tracker contract, resolution, and profile setup"
```

---

### Task 3: Linear adapter (`shared/trackers/linear.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/trackers/linear.md`

**Interfaces:**
- Consumes: the contract operation names from Task 2.
- Produces: Linear mapping referenced by `trackers.md` resolution.

- [ ] **Step 1: Write `linear.md`**

Contents (fresh text, sentence per line):

1. `# Linear adapter` - backed by the Linear MCP; verify the connected server's tool names at runtime (create/update tools are commonly consolidated into a save-style tool; fetch/list/user tools are stable).
2. A mapping table, one row per contract operation:
   - `getIssue` - fetch by key; save the native UUID, URL, labels, state.
   - `listSubIssues` - list issues filtered by parent.
   - `listDestinations` - the viewer's team memberships (from the current-user tool), then projects for a chosen team; do not list the whole workspace's teams.
   - `resolveDestination` - match team key or name to its UUID; validate a project if given.
   - `createIssue` - create with team, title, description; add project when resolved.
   - `createSubIssue` - create with parent id (team inherited from the parent).
   - `updateState` - update state using the names saved in the tracker profile.
   - `comment` - create a comment with issue id + body.
3. Notes section:
   - Issue refs are native keys like `ONC-5`; lowercase for branch names.
   - Linear's GitHub integration closes the issue when a PR whose body contains `Closes <KEY>` merges; do not force a `done` transition at PR time.
   - First-run profile: list the team's workflow states and propose the closest matches for the three phases.

- [ ] **Step 2: Verify**

Run: `grep -c "updateState\|createSubIssue\|resolveDestination" plugins/issue-lifecycle/skills/shared/trackers/linear.md`
Expected: >= 3.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/trackers/linear.md
git commit -m "feat(issue-lifecycle): add Linear tracker adapter"
```

---

### Task 4: Asana adapter (`shared/trackers/asana.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/trackers/asana.md`

**Interfaces:**
- Consumes: contract operation names from Task 2.
- Produces: Asana mapping including the issue-ref scheme and done-on-merge behavior that Task 8's finish step references.

- [ ] **Step 1: Write `asana.md`**

Contents (fresh text, sentence per line):

1. `# Asana adapter` - backed by the Asana MCP; verify connected tool names at runtime.
2. Mapping table, one row per contract operation:
   - `getIssue` - fetch the task by GID (parsed from a pasted URL) or by name search fallback; save GID, permalink URL, completed flag, memberships (project + section).
   - `listSubIssues` - list the task's subtasks.
   - `listDestinations` - list projects in the workspace the user can access.
   - `resolveDestination` - match project name/GID from hint or profile default.
   - `createIssue` - create a task in the resolved project.
   - `createSubIssue` - create a subtask under the parent task.
   - `updateState` - main task only: apply the profile mapping (move to mapped section, or set mapped status custom field); `done` additionally sets the completed flag.
   - `comment` - post a story/comment on the task.
3. `## Issue references` - Asana has no human-readable keys:
   - Invocation is by pasted task URL; name search is the fallback.
   - The ref used in branches and filenames is `asana-<last 6 digits of the task GID>`; branches append a title slug (example: `feat/asana-482913-add-login`).
   - Record the full task URL in the checklist file, the tracker profile, and the PR body; a resumed session finds the task by that URL.
4. `## Subtask limitation` - subtasks do not appear in board sections unless explicitly added; sub-issue transitions degrade to the completed flag (`inProgress` is a no-op or an optional comment; `done` marks complete); section/status mapping applies to the main task only.
5. `## Done on merge` - Asana has no PR-merge integration:
   - At PR open, move the main task to the mapped `inReview` state and post a comment stating the task will be closed by the next skill run after the PR merges.
   - Every skill invocation in a repo first checks: does any `.issue-lifecycle/tasks/*.md` reference an Asana task whose PR has since merged (check with `gh pr view <branch> --json state,mergedAt`)?
     If yes, apply the mapped `done` state and completed flag before proceeding.
   - Idempotency: after closing, append a `- Closed: <date>` line to that checklist file (committed to the default branch); the sweep skips files that already carry a Closed line, so the check runs at most once per issue.

- [ ] **Step 2: Verify**

Run: `grep -cn "GID\|subtask\|completed flag" plugins/issue-lifecycle/skills/shared/trackers/asana.md`
Expected: >= 3.
Run: `grep -n "merge" plugins/issue-lifecycle/skills/shared/trackers/asana.md | head -3`
Expected: done-on-merge section present.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/trackers/asana.md
git commit -m "feat(issue-lifecycle): add Asana tracker adapter with ref scheme and done-on-merge"
```

---

### Task 5: Memory contract and resolution (`shared/memory.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/memory.md`

**Interfaces:**
- Produces: 6-operation memory contract; fallback resolution; display-overlay rule.
  Tasks 6-7 implement it; Tasks 8-9 consume operation names.

- [ ] **Step 1: Write `memory.md`**

Contents (fresh, sentence per line):

1. `# Task memory` - task state lives in exactly one durable backend per run; the backend is resolved by probing, never configured.
2. `## The contract` - table with exactly these rows:
   - `init(issueRef)` - prepare the backend for this issue's task set.
   - `createTask(title, description, subIssueRef, deps)` - returns a task id.
   - `claimNext()` - return and mark in-progress the first open task whose deps are all closed; null when none remain.
   - `close(taskId)` - mark done.
   - `status()` - open/done counts and the current in-progress task.
   - `parentTask(issueRef)` - create/fetch the parent task representing the overarching issue.
3. `## Resolution` - probe once per run, existing state wins over capability:
   - `.beads/` exists in the repo: use the beads adapter.
   - `.issue-lifecycle/tasks/<ref>.md` exists and contains task checkboxes: use the checklist adapter (even if `bd` is installed - never switch backends mid-issue).
   - Neither (fresh run): `bd --version` succeeds means beads, otherwise checklist.
   - State the durability rationale in one line: both backends live in the repo, so any later session on any machine resumes by reading the repo.
   - Resume reads the working tree, not the last commit: an in-progress marker may be uncommitted when a session dies, and the file on disk is the truth.
4. `## Display overlay` - if the agent exposes built-in task-list tools, mirror tasks into them for live progress UI; rebuild the overlay from the durable backend on resume; NEVER read the overlay as the source of truth; skip silently when no such tools exist.
5. `## No dual truth` - when beads is active the checklist file contains the plan only (no checkboxes); in checklist mode the file holds plan and statuses; task status never lives in two places.

- [ ] **Step 2: Verify**

Run: `grep -c "claimNext\|parentTask\|createTask" plugins/issue-lifecycle/skills/shared/memory.md`
Expected: >= 3.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/memory.md
git commit -m "feat(issue-lifecycle): add memory contract with fallback resolution and overlay rule"
```

---

### Task 6: beads adapter (`shared/memory/beads.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/memory/beads.md`

**Interfaces:**
- Consumes: memory contract names from Task 5.
- Produces: beads command mapping.

- [ ] **Step 1: Write `beads.md`**

Mapping table (fresh text):

- `init` - `bd init` if `.beads/` absent; no-op otherwise.
- `createTask` - `bd create "<title>" -d "<description>"`; set the sub-issue ref via `bd update <id> --external-ref <subIssueRef>`; dependencies via `bd dep add <id> <depId>`.
- `claimNext` - `bd list --status open` filtered to unblocked; claim with `bd update <id> --claim`.
- `close` - `bd close <id>`.
- `status` - `bd list` summarized to open/done counts and the in-progress task.
- `parentTask` - `bd create` for the overarching issue with the issue URL as external-ref; child tasks depend on nothing but are linked by the naming/description convention `<issueRef>: <task title>`.

Note: verify subcommand flags against the installed `bd` at implementation time (`bd --help`, `bd create --help`); if a flag differs, use the installed form and update this file.

- [ ] **Step 2: Verify**

Run: `grep -c "bd " plugins/issue-lifecycle/skills/shared/memory/beads.md`
Expected: >= 6.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/memory/beads.md
git commit -m "feat(issue-lifecycle): add beads memory adapter"
```

---

### Task 7: Checklist adapter (`shared/memory/checklist.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/memory/checklist.md`

**Interfaces:**
- Consumes: memory contract names from Task 5.
- Produces: the checklist file format that Task 8's resume logic and Task 4's done-on-merge check read.

- [ ] **Step 1: Write `checklist.md`**

Contents:

1. State lives at `.issue-lifecycle/tasks/<ISSUE-REF>.md` on the feature branch, committed with every change; kept permanently after merge as the record.
2. Full fenced example of the file format:

```markdown
# ONC-5: Add login flow

- Issue: https://linear.app/acme/issue/ONC-5
- Branch: feat/onc-5-add-login
- PR: (filled at open)

## Plan

One-paragraph approach summary.
Testing notes.

## Tasks

- [x] 1. Create login form component -> sub-issue: https://... (done 2026-07-28)
- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://...
- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://...
```

3. Operation mapping:
   - `init` - create the file with the plan section and empty task list; commit.
   - `createTask` - append a `- [ ] N. <title> (deps: ...) -> sub-issue: <url>` line; commit with the scaffold.
   - `claimNext` - first `- [ ]` line whose deps are all `- [x]`; rewrite marker to `- [>]`.
   - `close` - rewrite `- [>]` to `- [x]` with a done date; the rewrite rides the task's implementation commit.
   - `status` - count markers.
   - `parentTask` - the file itself is the parent; the header line is the parent record.
4. Marker legend: `[ ]` open, `[>]` in progress, `[x]` done.

- [ ] **Step 2: Verify**

Run: `grep -c "\[>\]\|\[x\]\|\[ \]" plugins/issue-lifecycle/skills/shared/memory/checklist.md`
Expected: >= 3.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/memory/checklist.md
git commit -m "feat(issue-lifecycle): add markdown checklist memory adapter"
```

---

### Task 8: Core skill `issue-lifecycle` (`skills/issue-lifecycle/SKILL.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/issue-lifecycle/SKILL.md`

**Interfaces:**
- Consumes: tracker contract (Task 2), memory contract (Task 5), issue-ref scheme + done-on-merge (Task 4), checklist format (Task 7).
- Produces: the primary user-facing skill.

- [ ] **Step 1: Write SKILL.md**

Frontmatter:

```yaml
---
name: Issue Lifecycle
description: This skill should be used when the user asks to "work on an issue", "start an issue", "implement this Asana/Linear issue", "take this issue to a PR", pastes an Asana task URL to build, or names a Linear issue key like ONC-5. Drives the issue from breakdown through implementation to an open PR with resumable task tracking.
version: 3.0.0
---
```

Body (capability language only, sentence per line, target under 100 lines):

1. One-paragraph overview: single resumable autonomous pass from issue to PR; re-invoke to resume; no separate start/finish steps.
2. Operating principles (bullets): resumable single pass guarded by observable artifacts; zero mid-run confirmation after first-run profile setup; the memory backend is the source of truth and state flows one way to the tracker; stop and hold on unfixable test failures.
3. Shared references to read first: `../shared/trackers.md`, `../shared/memory.md`, `../shared/agents.md` (relative links).
4. Procedure, numbered:
   1. Post-merge sweep: apply the Asana done-on-merge check from the tracker adapter before anything else.
   2. Resolve tracker (per trackers.md) and memory backend (per memory.md); load or create the tracker profile.
   3. Determine the issue ref from the argument, a pasted URL, or the current branch name; conflicting argument and branch refs: warn and ask which.
   4. `getIssue`; save title, description, type, URL, children.
   5. Research the codebase for relevant files and patterns using the agent's file search and read capabilities.
   6. Ensure the feature branch (guarded): prefix from issue type (feature -> `feat/`, bug -> `fix/`, chore -> `chore/`, docs -> `docs/`, default `feat/`), then the issue ref and a title slug.
   7. Ensure the breakdown (guarded): `parentTask`, then for each planned unit `createTask` + `createSubIssue`, linking each pair; adopt existing sub-issues instead of inventing when the issue already has children; write the plan into the checklist file.
   8. `updateState(issue, inProgress)`.
   9. Implementation loop: `claimNext`; move its sub-issue to inProgress; implement following project patterns; run the related tests; on pass commit (message references the issue ref and task), `close` the task, sub-issue to done; on unfixable failure stop and hold (keep changes, task stays in progress, report, exit).
   10. Finish (guarded, when `claimNext` returns null): commit any leftover changes; close the parent task; push; open the PR with `gh` (body: `Closes <ref>` for Linear or the task URL for Asana, summary, completed tasks, test plan) unless one exists; `updateState(issue, inReview)`; post the completion comment (for Asana include the done-on-merge note).
   11. Final summary: issue, PR URL, tracker state, task counts.
5. Display overlay note: one line pointing at memory.md's overlay rule.

- [ ] **Step 2: Verify capability-language rule**

Run: `grep -nE "mcp_|TaskCreate|TaskUpdate|Glob|Grep|bd " plugins/issue-lifecycle/skills/issue-lifecycle/SKILL.md`
Expected: no output (exit 1).
Run: `wc -l plugins/issue-lifecycle/skills/issue-lifecycle/SKILL.md`
Expected: under ~120 lines.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/issue-lifecycle/SKILL.md
git commit -m "feat(issue-lifecycle): add core issue-lifecycle skill"
```

---

### Task 9: Core skill `issue-intake` (`skills/issue-intake/SKILL.md`)

**Files:**
- Create: `plugins/issue-lifecycle/skills/issue-intake/SKILL.md`

**Interfaces:**
- Consumes: tracker contract (Task 2), tracker profile default destination (Task 2).
- Produces: intake skill that hands off to issue-lifecycle.

- [ ] **Step 1: Write SKILL.md**

Frontmatter:

```yaml
---
name: Issue Intake
description: This skill should be used when the user asks to "turn these requirements into an issue", "create an issue and sub-issues", "scaffold an issue from this PRD or spec", or "break these requirements into tickets" for Asana or Linear. Creates a main issue plus linked sub-issues, then offers to hand off to the issue-lifecycle skill.
version: 3.0.0
---
```

Body (capability language, sentence per line, target under 80 lines):

1. Overview: requirements text in, scaffolded tracker issue + sub-issues out; nothing is created before the user approves the draft.
2. Shared references: `../shared/trackers.md`, `../shared/agents.md`.
3. Procedure:
   1. Post-merge sweep (same one line as lifecycle step 1).
   2. Resolve tracker; `resolveDestination` from an explicit hint, else the tracker profile default, else `listDestinations` and ask once.
   3. Draft the main issue (title, description summarizing the requirements) and 3-7 sub-issue drafts sized as independently implementable units; show the full draft and wait for approval; apply edits.
   4. `createIssue`, then `createSubIssue` per child; report all URLs.
   5. Save the destination to the tracker profile if it changed.
   6. Offer handoff: "run issue-lifecycle on <ref> now?" and if yes invoke that skill.

- [ ] **Step 2: Verify**

Run: `grep -nE "mcp_|TaskCreate|TaskUpdate|Glob|Grep|bd " plugins/issue-lifecycle/skills/issue-intake/SKILL.md`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/issue-intake/SKILL.md
git commit -m "feat(issue-lifecycle): add issue-intake skill"
```

---

### Task 10: Agent notes (`shared/agents.md`)

Execution order note: run this task BEFORE Tasks 8-9; both core skills reference this file.

**Files:**
- Create: `plugins/issue-lifecycle/skills/shared/agents.md`

**Interfaces:**
- Consumes: overlay rule from Task 5.
- Produces: per-agent specifics referenced by both core skills.

- [ ] **Step 1: Write `agents.md`**

Contents:

1. `# Agent notes` - the skills follow the open Agent Skills standard and run unchanged in Claude Code and Kiro; this file holds the only per-agent differences.
2. `## Install` - Claude Code: install the plugin from this marketplace repo.
   Kiro: copy or symlink the plugin's `skills/` directory into `.kiro/skills/` (workspace) or `~/.kiro/skills/` (global).
3. `## Task display overlay` - Claude Code: TaskCreate/TaskUpdate/TaskList tool family.
   Kiro: use its built-in todo/task tools if exposed; otherwise skip the overlay.
   Repeat the one-line rule: overlay is display only, never truth.
4. `## MCP tool naming` - tool name prefixes differ per agent and per MCP build; discover the connected tracker server's actual tool names at runtime instead of hardcoding.
5. `## Permissions` - for smooth autonomous runs pre-approve: `git`, `gh`, `bd`, and the tracker MCP's tools; list where each agent configures this (Claude Code settings allowlist; Kiro trusted commands).

- [ ] **Step 2: Verify**

Run: `grep -c "Kiro\|kiro" plugins/issue-lifecycle/skills/shared/agents.md`
Expected: >= 3.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/skills/shared/agents.md
git commit -m "feat(issue-lifecycle): add per-agent notes"
```

---

### Task 11: Plugin README rewrite

**Files:**
- Modify: `plugins/issue-lifecycle/README.md` (full rewrite)

**Interfaces:**
- Consumes: everything above.
- Produces: install + usage doc for Ryan's team.

- [ ] **Step 1: Rewrite README.md**

Sections:

1. What it is: two skills (issue-lifecycle, issue-intake), trackers supported (Asana, Linear), agents supported (Claude Code, Kiro), one-line frontier-model note (built for frontier-model agents; no small-model mode).
2. Install - Claude Code: marketplace/plugin instructions matching this repo's existing README conventions (read the repo root README first and match its install phrasing).
   Kiro: copy/symlink `skills/` into `.kiro/skills/`.
3. Setup: connect your tracker MCP (Asana or Linear); optionally install beads (`bd`) for the richest task memory; first run asks once about state mapping and saves `.issue-lifecycle/config.md`.
4. Usage examples: "work on ONC-5"; "work on <asana task url>"; "turn these requirements into an issue".
5. How task memory works: three tiers in one short table (beads -> checklist file -> built-in display overlay).
6. What lands in your repo: `.issue-lifecycle/config.md` (committed profile) and `.issue-lifecycle/tasks/<ref>.md` (per-issue plan + checklist, permanent record).
7. Migrating from v2: commands removed; equivalent flows (issue-start + issue-task + issue-finish -> single "work on <issue>"); v2 remains in git history.

- [ ] **Step 2: Verify**

Run: `grep -c "Kiro\|Asana\|Linear\|beads" plugins/issue-lifecycle/README.md`
Expected: >= 8.

- [ ] **Step 3: Commit**

```bash
git add plugins/issue-lifecycle/README.md
git commit -m "docs(issue-lifecycle): rewrite README for v3 multi-agent, multi-tracker skills"
```

Check `git show --stat HEAD` for the version-sync hook having touched root README/marketplace.json; include those changes if the hook staged them.

---

### Task 12: Static validation pass

**Files:**
- Modify: any file flagged by validators.

**Interfaces:**
- Consumes: the complete plugin from Tasks 1-11.
- Produces: a validator-clean plugin.

- [ ] **Step 1: Run the plugin validator**

Dispatch the `plugin-dev:plugin-validator` agent on `plugins/issue-lifecycle/`.
Fix every error; fix warnings unless clearly wrong.

- [ ] **Step 2: Run the skill reviewer**

Dispatch the `plugin-dev:skill-reviewer` agent for each of the two SKILL.md files.
Apply description/trigger improvements it suggests; keep the frontmatter contract from Tasks 8-9 (name, third-person description, version).

- [ ] **Step 3: Run Skill Spector**

Skill Spector is the external skill validator the collaborator asked for.
Find it first (`npx skill-spector --help` or search "skill spector agent skills validator" for the current install method); run it against both SKILL.md files and fix findings.
If it cannot be located or installed, record that in the commit message and rely on Step 1-2 validators.

- [ ] **Step 4: Re-run the capability-language greps**

Run: `grep -rnE "mcp_|TaskCreate|TaskUpdate|Glob|Grep" plugins/issue-lifecycle/skills/issue-lifecycle/SKILL.md plugins/issue-lifecycle/skills/issue-intake/SKILL.md`
Expected: no output (agents.md and adapters MAY name tools; core skills may not).

- [ ] **Step 5: Cross-reference check**

Run: `grep -rn "\.\./shared\|shared/" plugins/issue-lifecycle/skills/*/SKILL.md` and confirm every referenced path exists on disk.

- [ ] **Step 6: Commit fixes**

```bash
git add -A plugins/issue-lifecycle
git commit -m "fix(issue-lifecycle): apply validator and skill-reviewer findings"
```

(Skip the commit if there were no findings.)

---

### Task 13: E2E fixtures (CHECKPOINT - needs the user)

**Files:**
- None in this repo.

**Interfaces:**
- Produces: test environments for Task 14.

This task requires the user's accounts and machine; pause and coordinate rather than proceeding autonomously.

- [ ] **Step 1: Test repo** - create a throwaway repo (e.g. `~/Desktop/Projects/il-test-app`) with a small real project: a few source files, a test suite with passing tests, and one intentionally broken test on a branch for the stop-and-hold scenario.
  Push to GitHub (private) so `gh pr` works.
- [ ] **Step 2: Asana** - user creates/confirms a free Asana workspace, a project with board sections including In Progress / Review / Done, and connects the Asana MCP in Claude Code.
- [ ] **Step 3: Linear** - confirm a Linear test team exists and its MCP is connected.
- [ ] **Step 4: Kiro** - user installs Kiro, symlinks the plugin's `skills/` into `~/.kiro/skills/`, connects the Asana MCP in Kiro's mcp.json, and confirms the skills appear in Kiro's skill UI.
- [ ] **Step 5: beads** - confirm `bd --version` works on the machine; note the version in the test log.

---

### Task 14: E2E scenario matrix (CHECKPOINT - interactive)

**Files:**
- Create: `docs/superpowers/testing/2026-07-28-issue-lifecycle-v3-e2e-log.md` (running results log)

**Interfaces:**
- Consumes: fixtures from Task 13.

Run the spec's four combos; log every run (combo, scenario, result, defects) in the e2e log file and fix defects between runs with focused commits.

- [ ] **Combo 1: Claude Code + Linear + beads** - full run (intake -> lifecycle -> PR), resume test (kill at task 2, re-invoke), first-run profile test.
- [ ] **Combo 2: Claude Code + Asana + checklist** (rename `bd` off PATH for the run) - full run by pasted URL, resume test, subtask completed-flag check, post-merge close check, and clone-inherit test (fresh clone of the test repo must read the committed profile without prompting).
- [ ] **Combo 3: Kiro + Asana + checklist** - full run, resume test, overlay behavior noted (present or skipped).
- [ ] **Combo 4: Kiro + Asana + beads** - full run plus stop-and-hold scenario on the broken-test branch.
- [ ] **Failure paths (any combo):** disconnect the tracker MCP and confirm a clean stop naming the missing MCP.
- [ ] **Commit the log**

```bash
git add docs/superpowers/testing/2026-07-28-issue-lifecycle-v3-e2e-log.md
git commit -m "test(issue-lifecycle): record v3 e2e matrix results"
```

---

### Task 15: Version sync + branch wrap-up

**Files:**
- Modify: root `README.md`, `.claude-plugin/marketplace.json` (via sync tooling)

- [ ] **Step 1: Run the version sync**

Run: `bin/sync-versions.sh` and confirm root README + marketplace.json show issue-lifecycle 3.0.0.

- [ ] **Step 2: Commit**

```bash
git add README.md .claude-plugin/marketplace.json
git commit -m "chore(issue-lifecycle): sync v3.0.0 across marketplace metadata"
```

- [ ] **Step 3: Push and hand off**

Run: `git push -u origin feat/issue-lifecycle-v3`.
Then use superpowers:finishing-a-development-branch to decide merge/PR.
