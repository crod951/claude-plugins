# Issue Lifecycle

Issue Lifecycle is a pair of agent skills that carry a tracker issue from intake through an open pull request.
It works with Asana or Linear as your issue tracker.
Both skills follow the open Agent Skills standard, so they run unchanged on Claude Code and Kiro.

> Built for frontier-model agents. There is no small-model mode.

## What it is

- **issue-lifecycle** - drives one tracker issue through a single resumable pass: breakdown, implementation, tests, commits, and an open PR.
  Re-invoke it on the same issue to resume wherever the last run left off; it never relies on memory of a previous run, only on what is saved to disk and in the tracker.
- **issue-intake** - turns requirements text (a PRD, a spec, a paragraph) into a scaffolded main issue plus linked sub-issues, then offers to hand off to issue-lifecycle.

**Trackers supported:** Asana, Linear.
**Agents supported:** Claude Code, Kiro.

## Install

### Claude Code

Run these commands inside a Claude Code session (they start with `/`):

```
/plugin marketplace add crod951/claude-plugins
/plugin install issue-lifecycle@crod951
```

### Kiro

Copy or symlink this plugin's `skills/` directory contents into `.kiro/skills/` for a workspace install, or into `~/.kiro/skills/` for a global install.
Keep `issue-lifecycle/`, `issue-intake/`, and `shared/` as siblings at the top level of that destination, since each skill references `../shared/` files by relative path.

```bash
cp -r plugins/issue-lifecycle/skills/. ~/.kiro/skills/
```

## Setup

1. **Connect your tracker's MCP.**
   Asana or Linear, whichever you use.
   In Claude Code, install and authenticate the matching MCP plugin before running either skill.
   In Kiro, configure the equivalent MCP server.
   Tool names are discovered at runtime, so any recent build of either MCP works.
2. **Optionally install beads (`bd`) for the richest task memory.**
   Without it, task tracking falls back to a plain checklist file committed on the branch, which works fine for solo or small-scale use.
   Beads adds dependency-aware task claiming and is recommended once a project has more than a handful of tasks per issue.
   ```bash
   brew install beads
   bd version
   ```
3. **First run asks once about state mapping.**
   The first time either skill runs in a repository, it inspects your tracker's actual states and proposes a mapping to the three phases it needs: `inProgress`, `inReview`, and `done`.
   You confirm or correct that mapping, and it is saved to `.issue-lifecycle/config.md` so every later run uses it silently.

## Usage examples

Talk to either skill in plain language; there are no slash commands to memorize.

- `work on ONC-5`
- `work on <asana task url>`
- `turn these requirements into an issue`

## How task memory works

Task state for an issue lives in exactly one durable backend, chosen automatically and never switched mid-issue.

| Tier | Role |
| --- | --- |
| beads (`bd`) | Preferred backend when the `bd` CLI is available. Stores tasks with dependencies in `.beads/` inside your repo. |
| checklist file | Fallback backend used when beads is not installed. The plan and every task's status live together in `.issue-lifecycle/tasks/<ref>.md`. |
| built-in display overlay | Optional live progress view mirrored into the running agent's own task-list tools (for example Claude Code's task list). Always rebuilt from whichever backend above is active; never treated as the source of truth. |

## What lands in your repo

- `.issue-lifecycle/config.md` - the committed tracker profile: which tracker, which default destination, and the state mapping confirmed on first run.
- `.issue-lifecycle/tasks/<ref>.md` - the per-issue plan and checklist.
  This file is a permanent record and stays in the repo after the pull request merges.

## Migrating from v2

Version 3 removes the v2 slash commands: `/issue-start`, `/issue-task`, `/commit`, and `/issue-finish`.
In their place, the issue-lifecycle skill covers the same ground with one instruction: "work on ONC-5" now does what used to take `/issue-start`, then `/issue-task` and `/commit` repeated per task, then `/issue-finish`.
v2 remains available in this repository's git history if you need to reference it.
