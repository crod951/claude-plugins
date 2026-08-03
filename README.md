# skills

[![SkillSpector](https://github.com/crod951/skills/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crod951/skills/actions/workflows/skillspector.yml)

Personal agent skills for issue-driven development workflow automation, installable as a Claude Code plugin or onto any agent via [skills.sh](https://www.skills.sh).
All skills are scanned with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on every change; the build fails on any non-suppressed security finding.

## Installation (30-second setup)

**Claude Code** - run these inside a session for a managed install that updates when this repo ships:

```text
/plugin marketplace add crod951/skills
/plugin install workbench@crod951
```

**Kiro, Codex, and other agents** - use [skills.sh](https://www.skills.sh) for an editable copy on any agent:

```bash
npx skills@latest add crod951/skills
```

When the installer asks which skills to take, take all of them; `workbench-shared` carries the contract files the other two read.

> Individual plugins may have additional prerequisites that run in your **terminal** (e.g., `brew install`). See each plugin's README for details.

## Available Plugins

### workbench (v1.0.0)

Workbench provides two agent skills, execute and scaffold, that carry a tracker issue from requirements to an open code review, on GitHub or any other forge with an adapter.
It works with Asana or Linear as your issue tracker, and both skills run unchanged on Claude Code and Kiro.

#### Prerequisites

- An Asana or Linear MCP plugin installed and authenticated
- [Beads CLI](https://github.com/steveyegge/beads) installed (`bd` command available); optional, but recommended for the richest task memory
- A forge adapter for wherever your reviews live. GitHub ships built in and needs the [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh` command available); for any other forge, write a `.workbench/forge.md` from the bundled template. Without either, runs still work and hand the review off to you.

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

See the [full guide](./docs/workbench.md) for setup, task memory, and the security boundary.

---

## Workflow

1. **Scaffold requirements**: talk to the scaffold skill, for example "scaffold these requirements"
2. **Execute the issue**: talk to the execute skill, for example "execute ONC-5"
3. **Resume if interrupted**: re-invoke execute on the same issue; it picks up where the last run left off

## Security Scanning

Every skill in `skills/` is scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) in CI, and the build fails on any non-suppressed finding.
Run the same scan locally before committing:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git
bin/scan-skills.sh            # all skills; or name specific ones: bin/scan-skills.sh execute
```

When a finding is a reviewed false positive, suppress it in the repo-root `.skillspector-baseline.yaml` with a written reason; never suppress a finding you have not understood.

## License

MIT
