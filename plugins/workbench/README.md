# Workbench

Workbench is a pair of agent skills, execute and scaffold, that carry a tracker issue from intake through an open pull request.
It works with Asana or Linear as your issue tracker.
Both skills follow the open Agent Skills standard, so they run unchanged on Claude Code and Kiro.

> Built for frontier-model agents. There is no small-model mode.

## What it is

- **execute** - drives one tracker issue through a single resumable pass: breakdown, implementation, tests, commits, and an open PR.
  Re-invoke it on the same issue to resume wherever the last run left off; it never relies on memory of a previous run, only on what is saved to disk and in the tracker.
- **scaffold** - turns requirements text (a PRD, a spec, a paragraph) into a scaffolded main issue plus linked sub-issues, then offers to hand off to execute.

**Trackers supported:** Asana, Linear.
**Agents supported:** Claude Code, Kiro.

## Install

### Claude Code

Run these commands inside a Claude Code session (they start with `/`):

```
/plugin marketplace add crod951/claude-plugins
/plugin install workbench@crod951
```

### Kiro

Copy or symlink this plugin's `skills/` directory contents into `.kiro/skills/` for a workspace install, or into `~/.kiro/skills/` for a global install.
Keep `execute/`, `scaffold/`, and `shared/` as siblings at the top level of that destination, since each skill references `../shared/` files by relative path.

```bash
cp -r plugins/workbench/skills/. ~/.kiro/skills/
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
3. **Install and authenticate the GitHub CLI (`gh`).**
   The execute skill opens pull requests with `gh`, so it must be installed and authenticated before your first run.
   ```bash
   brew install gh
   gh auth login
   ```
4. **First run asks once about state mapping.**
   The first time either skill runs in a repository, it inspects your tracker's actual states and proposes a mapping to the three phases it needs: `inProgress`, `inReview`, and `done`.
   You confirm or correct that mapping, and it is saved to `.workbench/config.md` so every later run uses it silently.

## Usage examples

Talk to either skill in plain language, or name it directly; there are no slash commands to memorize.

- `execute ONC-5`
- `run execute on this issue`
- `work on ONC-5`
- `work on <asana task url>`
- `scaffold these requirements`
- `turn these requirements into an issue`

## How task memory works

Task state for an issue lives in exactly one durable backend, chosen automatically and never switched mid-issue.

| Tier | Role |
| --- | --- |
| beads (`bd`) | Preferred backend when the `bd` CLI is available. Stores tasks with dependencies in `.beads/` inside your repo. |
| checklist file | Fallback backend used when beads is not installed. The plan and every task's status live together in `.workbench/tasks/<ref>.md`. |
| built-in display overlay | Optional live progress view mirrored into the running agent's own task-list tools (for example Claude Code's task list). Always rebuilt from whichever backend above is active; never treated as the source of truth. |

## What lands in your repo

- `.workbench/config.md` - the committed tracker profile: which tracker, which default destination, and the state mapping confirmed on first run.
- `.workbench/tasks/<ref>.md` - the per-issue plan and checklist.
  This file is a permanent record and stays in the repo after the pull request merges.

## Security boundary

Both skills promise the same thing about tracker access: tracker work only happens through the connected tracker MCP.
When that MCP is missing or disabled, the skill refuses the request and stops, naming the missing MCP so you know to connect it.
The skills are instructed to never read credentials from disk or environment variables, never call a tracker's HTTP API directly, and never edit MCP or agent configuration.

That promise is a set of instructions to a model, not a sandbox.
A model can disregard instructions.
During testing, one agent run attempted exactly this bypass after its tracker MCP was disabled: it tried editing `mcp.json`, reading OAuth token caches, and grepping the environment for credentials before attempting a direct Asana API call.
What actually stopped it was not the prose in these skills.
It was the agent harness's own approval prompts and file permissions.

So configure real enforcement in your agent harness, not just in the skill text.
At minimum, deny without case-by-case approval:

- Reads of credential stores and token caches, for example `~/.aws`, `~/.kiro/settings`, `~/.mcp-auth`, or similar OAuth caches.
- `env` and `printenv` style environment dumps.
- Writes to MCP configuration files.
- Outbound `curl` (or equivalent) to tracker API hosts.

Both Claude Code (permission settings) and Kiro (trusted command settings) support rules like these.
Agent approval prompts are the last line of defense here, so do not blanket-approve shell commands during autonomous runs; an approval you grant once, without reading it, is an approval you have effectively granted forever for that session.

In practice this path only triggers when a tracker MCP is missing or disabled.
A normal run, with the MCP connected, never reaches any of this.

## Migrating from v2

Version 3 removes the v2 slash commands: `/issue-start`, `/issue-task`, `/commit`, and `/issue-finish`.
In their place, the execute skill covers the same ground with one instruction: "execute ONC-5" (or "work on ONC-5") now does what used to take `/issue-start`, then `/issue-task` and `/commit` repeated per task, then `/issue-finish`.
v2 remains available in this repository's git history if you need to reference it.

## Upgrading from earlier versions

Repos that already have a `.issue-lifecycle/` directory from a previous version should rename it to `.workbench/`.
If you installed the merge-closer GitHub Action, also rename `.github/workflows/issue-lifecycle-close.yml` to `.github/workflows/workbench-close.yml` and update the `grep -rl "$BRANCH" .issue-lifecycle/tasks/` line inside it to point at `.workbench/tasks/`.
Update the profile's first line from the old `# issue-lifecycle tracker profile` heading to `# workbench tracker profile`.
If the repo uses beads for task memory, confirm that `.beads/.gitignore` and `.gitattributes` exist, since the beads tooling writes both, and untrack any beads runtime files that an earlier version committed, because ignore rules never apply to files that are already tracked.
