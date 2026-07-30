# claude-plugins

[![SkillSpector](https://github.com/crod951/claude-plugins/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crod951/claude-plugins/actions/workflows/skillspector.yml)

Custom Claude Code plugins for issue-driven development workflow automation.
All plugin skills are scanned with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on every change; the build fails on any non-suppressed security finding.

## Installation (inside Claude Code)

Run these commands **inside a Claude Code session** (they start with `/`):

```text
/plugin marketplace add crod951/claude-plugins
/plugin install workbench@crod951
```

> Individual plugins may have additional prerequisites that run in your **terminal** (e.g., `brew install`). See each plugin's README for details.

## Available Plugins

### workbench (v1.0.0)

Workbench provides two agent skills, execute and scaffold, that carry a tracker issue from requirements to an open pull request.
It works with Asana or Linear as your issue tracker, and both skills run unchanged on Claude Code and Kiro.

#### Prerequisites

- An Asana or Linear MCP plugin installed and authenticated
- [Beads CLI](https://github.com/steveyegge/beads) installed (`bd` command available); optional, but recommended for the richest task memory
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh` command available)

#### Install

```bash
/plugin install workbench@crod951
```

#### Skills

| Skill | Description |
|-------|-------------|
| `execute` | Drives one tracker issue through a single resumable pass: breakdown, implementation, tests, commits, and an open PR. |
| `scaffold` | Turns requirements text into a scaffolded main issue plus linked sub-issues, then offers to hand off to execute. |

Talk to either skill in plain language; there are no slash commands to memorize.

```bash
execute ONC-5
work on <asana task url>
scaffold these requirements
```

#### Features

- **Resumable pass** - execute reads durable state from disk and the tracker on every invocation, never from memory of a previous run
- **Scaffold-to-execute handoff** - scaffold drafts a main issue plus sub-issues, then offers to hand straight into execute
- **Task memory** - beads-backed when available, with a plain checklist file fallback
- **Conventional Commits** - one commit per task, referencing the issue ref
- **Tracker-only access** - tracker work only happens through the connected tracker MCP; when it is missing, the skill refuses and stops

#### Tracker Status Lifecycle

```text
Todo → In Progress (execute starts) → In Review (PR opened) → Done (PR merge)
```

See the [full guide](./plugins/workbench/README.md) for setup, task memory, and the security boundary.

---

## Workflow

1. **Scaffold requirements**: talk to the scaffold skill, for example "scaffold these requirements"
2. **Execute the issue**: talk to the execute skill, for example "execute ONC-5"
3. **Resume if interrupted**: re-invoke execute on the same issue; it picks up where the last run left off

## License

MIT
