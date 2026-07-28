# Issue Lifecycle v3: Clean-Room Multi-Agent Rewrite - Design

Date: 2026-07-28
Branch: `feat/issue-lifecycle-v3`
Status: Approved

## Purpose

Rewrite the issue-lifecycle plugin as a clean-room, agent-portable skill set that drives a tracker issue from requirements to an open PR.
The primary external user is a collaborator at Amazon whose team works in Claude Code or Kiro, tracks issues in Asana with a full read/write Asana MCP, and mixes experience levels (designers through design technologists).

This design replaces the v2 command-based plugin (`issue-start` / `issue-task` / `issue-finish` / `commit`) in this repository.
It is written fresh from learnings; no skill text is copied from any other repository.

## Decisions

| Decision | Choice |
|---|---|
| Baseline | Clean-room rewrite; v2 commands deleted; v2 remains in git history |
| Name | `issue-lifecycle` (unchanged) |
| Placement | `plugins/issue-lifecycle/` in this repo, replacing v2 |
| Skills included | `issue-lifecycle` (issue to PR) and `issue-intake` (requirements to scaffold); no sync-digest in v1 |
| Trackers | Asana and Linear; no Jira in v1 |
| Agents | Claude Code and Kiro, via the shared Agent Skills standard (SKILL.md, agentskills.io) |
| Memory chain | beads if available, else markdown checklist; agent built-in tasks are a display overlay only, never source of truth |
| Frontier-model constraint | The skills assume a frontier model at the base; no degraded small-model mode |

## Section 1: Repo layout and packaging

```
plugins/issue-lifecycle/
├── .claude-plugin/plugin.json        # Claude Code packaging, version 3.0.0
├── README.md                         # install paths for both agents
├── skills/
│   ├── issue-lifecycle/SKILL.md      # core: issue to PR
│   ├── issue-intake/SKILL.md         # core: requirements to issue + sub-issues
│   └── shared/
│       ├── trackers.md               # provider contract + runtime resolution
│       ├── trackers/asana.md         # Asana mapping
│       ├── trackers/linear.md        # Linear mapping
│       ├── memory.md                 # memory contract + fallback resolution
│       ├── memory/beads.md           # beads mapping
│       ├── memory/checklist.md       # markdown checklist mapping
│       └── agents.md                 # per-agent notes: install, task display overlay, MCP naming, permissions
```

One plugin directory replaces v2.
Claude Code installs it as a plugin from this marketplace repo.
Kiro users copy or symlink `skills/` into `.kiro/skills/` (workspace) or `~/.kiro/skills/` (global).
Adding a tracker or memory backend means one new adapter file plus one row in the corresponding contract doc.
Version bumps must respect the repo's version-sync tooling (`bin/sync-versions.sh`, pre-commit hook) which aligns plugin.json, README, and marketplace.json.

## Section 2: Core skills (clean-room)

Both core skills are written fresh in capability language.
They reference adapters by capability only (for example "create a sub-issue via the tracker adapter") and contain zero tool names.
Every step is guarded by an observable artifact, so re-invoking a skill resumes wherever the previous run stopped.
Target length is under roughly 100 lines each, with detail pushed into the shared reference docs (progressive disclosure).

### issue-lifecycle: "work on this issue" to open PR

1. Resolve tracker and memory backend by runtime probe; no config file required.
2. Fetch the issue; research the codebase for relevant files and patterns.
3. Ensure the feature branch (guarded; existing branch is adopted).
4. Breakdown: create a parent task for the overarching issue plus child tasks in the memory backend, and 1:1 linked sub-issues in the tracker; adopt existing sub-issues when present.
5. Move the issue to In Progress.
6. Implementation loop: claim the first open unblocked task, implement, run related tests, commit on pass, close the task, move its sub-issue to Done.
   If tests cannot pass after reasonable effort: stop and hold, keep changes, leave the task in progress, report, exit resumably.
7. Finish: push the branch, open the PR (body includes `Closes <issue ref>`), move the issue to In Review, post a completion comment.

### issue-intake: requirements to scaffold

1. Resolve tracker and destination (Asana project or Linear team), consulting the tracker profile first.
2. Draft the main issue and a sub-issue breakdown; show the user before creating anything.
3. Create the main issue and linked sub-issues.
4. Offer a handoff to issue-lifecycle.

## Section 3: Tracker adapter axis

### Contract (8 operations)

`getIssue`, `listSubIssues`, `listDestinations`, `resolveDestination`, `createIssue`, `createSubIssue`, `updateState(inProgress | inReview | done)`, `comment`.

### Runtime resolution

The shape of the issue reference decides the provider: a key like `ABC-123` means Linear; an Asana URL or GID means Asana.
If ambiguous, check which tracker MCP is connected; if both are, ask the user once.
Adapter docs instruct verifying the connected MCP's actual tool names at runtime rather than hardcoding a specific build.
If the resolved tracker's MCP is not connected, stop with a clear message; never fall back silently.

### First-run tracker profile

On first use of a tracker project in a repo, the adapter runs a one-time setup:

1. List what the project actually has (Linear: workflow states; Asana: board sections and status custom fields).
2. Propose a mapping for the three phases (inProgress, inReview, done) and ask the user to confirm or correct it.
3. Save the confirmed mapping to `.issue-lifecycle/config.md`, committed to the repo.

The profile also stores the default destination (Asana project or Linear team) used by issue-intake.
Because the profile is committed, teammates who clone the repo inherit the mapping and are never prompted.
Subsequent runs read the profile silently, preserving zero mid-run confirmation.
If a mapped state no longer exists, or the user asks to remap, re-run setup.

Propagation caveat: the profile is first written on a feature branch and only reaches the default branch when that PR merges.
A run started from the default branch before then will not find the profile; the skill first checks other local branches for a newer `.issue-lifecycle/config.md` and reuses it, and only prompts if none exists.
Profile merge conflicts are resolved by re-running setup.

### Linear adapter

Direct mapping to the Linear MCP: issue fetch, sub-issue creation via parent linkage, state transitions using the profile's state names, comments.
Linear closes issues automatically when a linked PR merges; the skill does not force a Done transition at PR time.

### Asana adapter

Asana has no workflow states and no human-readable issue keys, which drives two behaviors:

- State transitions use the tracker profile: move the task between mapped board sections or set the mapped status custom field; `done` also marks the task completed.
- Invocation is by pasted task URL (natural for designers living in the Asana UI), with name search as a fallback.

Sub-issues are native Asana subtasks (tasks with a parent).
Subtasks do not appear in the project's board sections unless explicitly added, so sub-issue state transitions degrade to the completed flag: In Progress is a no-op (optionally a comment), Done marks the subtask complete.
Section and status-field mapping applies to the main issue only.

Asana has no equivalent of Linear's done-on-merge GitHub integration.
At PR open the main task moves to the mapped In Review state; after the PR merges, the next invocation of any skill in the repo detects the merged PR and applies the mapped done state and completed flag.
The completion comment posted at PR open states this explicitly so the team knows the task closes on the next run rather than instantly at merge.

### Issue reference scheme

Every issue gets a short stable ref used in branch names, checklist filenames, commit messages, and the PR body.
Linear: the native key, lowercased for branches (`feat/onc-5-add-login`).
Asana: `asana-<last 6 digits of the task GID>` plus a title slug (`feat/asana-482913-add-login`), with the full task URL recorded in the checklist file, the tracker profile, and the PR body.
The ref-to-URL mapping in the checklist file is what lets a resumed session find the Asana task again without a human-readable key.

## Section 4: Memory adapter axis

### Contract (6 operations)

`init`, `createTask(title, description, subIssueRef, deps)`, `claimNext` (first open unblocked task), `close`, `status` (open and done counts, current task), `parentTask`.

### Runtime resolution

Probe once per run: if the `bd` binary is present and working, use beads; otherwise use the markdown checklist.
Agent built-in task tools (Claude Code TaskCreate family, Kiro's equivalent) are a display overlay only: they mirror tasks for live progress UI when available, are rebuilt from the durable backend on resume, and are never read as the source of truth.

### beads adapter

`bd init`, `bd create`, claim and close operations, dependency links, and the sub-issue reference stored in the task's external-ref.

### Markdown checklist adapter

State lives at `.issue-lifecycle/tasks/<ISSUE-KEY>.md`, committed on the feature branch.
One file holds the plan summary up top (issue link, approach, testing notes) and the task checklist below (checkboxes with sub-issue links and status markers).
Every claim and close edits the file, and each per-task commit carries it, so resume from any session or machine is: check out the branch, read the file.
Checklist files merge to the default branch with the PR and are kept permanently as the human-readable record of the breakdown and plan; there is no cleanup step.

### No dual truth

When beads is active, the file contains the plan only and statuses live in beads.
In checklist mode, the file holds both plan and statuses.
Task status never lives in two places.

## Section 5: Agent compatibility

Kiro implements the same open Agent Skills standard as Claude Code, so identical SKILL.md files load in both agents; there is no translation layer and no compiled variants.

Install paths (both documented in the README):

- Claude Code: plugin install from this marketplace repo.
- Kiro: copy or symlink `skills/` into `.kiro/skills/` (workspace) or `~/.kiro/skills/` (global).

`shared/agents.md` covers only what actually differs per agent:

- Built-in task display overlay: which tool family to use per agent, and skip the overlay if none is exposed.
- MCP naming: tool prefixes differ per agent; tracker adapters name canonical operations and instruct discovering the connected server's actual tool names at runtime.
- Permissions: what to pre-approve per agent for smooth autonomous runs (git, gh, bd, tracker MCP).

Core skills use capability language (search, read, edit, run shell) that both agents satisfy.
PR creation uses the `gh` CLI via shell, identical in both agents.

## Section 6: Testing and validation

### Static validation

- Skill Spector pass, plus the plugin-dev validator and skill-reviewer agents available in this environment.
- Frontmatter and description lint: triggering phrases match how designers will actually ask.

### E2E matrix

The full matrix is 2 agents x 2 trackers x 2 memory tiers; the prioritized 4 combos map to real users:

| Combo | Represents |
|---|---|
| Claude Code + Linear + beads | the author today (parity baseline) |
| Claude Code + Asana + checklist | designers on Claude Code |
| Kiro + Asana + checklist | the collaborating designers (primary demo target) |
| Kiro + Asana + beads | the collaborator himself |

Fixtures: a throwaway test repo with real passing and failing tests, a free Asana workspace with its MCP connected, and a Linear test team.

### Scenario tests (per combo)

- Full run: intake, scaffold, lifecycle, PR open; verify tracker states and linked sub-issues.
- Resume: kill the session mid-loop at task N; a fresh session re-invoke must continue from task N.
- First-run setup: the state-mapping prompt appears exactly once, `.issue-lifecycle/config.md` is written, the second run is silent, and a fresh clone inherits the mapping without prompting.
- Failure paths: tracker MCP disconnected produces a clean stop; an unfixable test produces stop-and-hold with a report.
- Post-merge close (Asana combos): merge the PR, invoke any skill in the repo, and verify the main task receives the mapped done state and completed flag.

## Out of scope for v1

- Jira adapter.
- sync-digest skill.
- Hosted or SaaS delivery of any kind.
- Small-model support.
