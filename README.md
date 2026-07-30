# claude-plugins

[![SkillSpector](https://github.com/crod951/claude-plugins/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crod951/claude-plugins/actions/workflows/skillspector.yml)

Custom Claude Code plugins for issue-driven development workflow automation.
All plugin skills are scanned with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on every change; the build fails on any non-suppressed security finding.

## Installation (inside Claude Code)

Run these commands **inside a Claude Code session** (they start with `/`):

```
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

```
Todo → In Progress (execute starts) → In Review (PR opened) → Done (PR merge)
```

See the [full guide](./plugins/workbench/README.md) for setup, task memory, and the security boundary.

---

## Workflow

1. **Scaffold requirements**: talk to the scaffold skill, for example "scaffold these requirements"
2. **Execute the issue**: talk to the execute skill, for example "execute ONC-5"
3. **Resume if interrupted**: re-invoke execute on the same issue; it picks up where the last run left off

---

## Developer Setup

After cloning the repo, configure Git to use the version-controlled hooks:

```bash
git config core.hooksPath bin/hooks
```

This enables a pre-commit hook that automatically syncs plugin versions from each `plugin.json` (source of truth) into `marketplace.json` and `README.md`.

---

## Contributing: Adding Plugins and Skills

This section is a reference for adding new plugins or skills to this repo.
You can paste these instructions into Claude Code to have it build new components for you.

### Repository Structure

```text
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json           # Registry - lists all plugins in this marketplace
├── bin/
│   └── scan-skills.sh             # SkillSpector runner used locally and in CI
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json        # Plugin manifest (name, version, description)
│       ├── README.md              # Plugin documentation
│       ├── .skillspector-baseline.yaml   # Optional: reviewed false-positive suppressions
│       └── skills/
│           ├── <skill-name>/
│           │   └── SKILL.md       # One agent skill (Agent Skills standard)
│           └── shared/            # Optional: contracts shared between skills
│               └── <topic>.md
```

### How It All Fits Together

- **Marketplace** (`.claude-plugin/marketplace.json`) - the top-level registry that tells Claude Code which plugins exist in this repo and where to find them.
- **Plugin** (`plugins/<name>/.claude-plugin/plugin.json`) - a self-contained package of skills.
- **Skill** (`plugins/<name>/skills/<skill>/SKILL.md`) - a markdown file following the open [Agent Skills](https://agentskills.io) standard.
  The frontmatter's `name` and `description` decide when an agent invokes the skill; the body is the procedure it follows.
  See `plugins/workbench/skills/` for the reference example, including the `shared/` pattern for contracts used by more than one skill.

### Adding a New Skill to an Existing Plugin

Create `plugins/<name>/skills/<skill-name>/SKILL.md`:

```markdown
---
name: my-skill
description: This skill should be used when the user asks to "do X", "run X on this", or names an X-shaped target. One or two more sentences on what it does.
version: 1.0.0
---

# My Skill

## Procedure

1. First step, written as an instruction to the executing agent.
2. Next step.
```

Skill-writing rules that hold across this repo:

- **The description triggers the skill** - write it around the phrases users actually say, and keep it honest about scope.
- **Reference shared contracts instead of restating them** - a skill that needs a convention another skill also needs should read a `shared/` file, so the two cannot drift apart.
- **State stop conditions explicitly** - say when the skill must stop and ask rather than guess.
- **Keep paths relative to the SKILL.md file** - skills may be installed outside this repo, so `../shared/foo.md` works and repo-rooted paths do not.

### Creating a New Plugin from Scratch

1. Create the directory structure shown above, with at least one skill under `skills/`.
2. Write `plugin.json`:

```json
{
  "name": "<plugin-name>",
  "version": "1.0.0",
  "description": "What this plugin does in one sentence",
  "author": {
    "name": "<your-name>",
    "email": "<your-email>"
  },
  "homepage": "https://github.com/<org>/claude-plugins",
  "repository": "https://github.com/<org>/claude-plugins",
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"]
}
```

3. Register it in `.claude-plugin/marketplace.json` in the `plugins` array:

```json
{
  "name": "<plugin-name>",
  "source": "./plugins/<plugin-name>",
  "description": "Same as plugin.json description",
  "version": "1.0.0",
  "author": { "name": "<your-name>" },
  "repository": "https://github.com/<org>/claude-plugins",
  "keywords": ["keyword1", "keyword2"]
}
```

4. Write a `README.md` with installation instructions, a skill reference, and usage examples.
5. Bump the version in `plugin.json` whenever you make changes; the pre-commit hook syncs it into `marketplace.json` and this README.

### Security Scanning

Every skill in `plugins/*/skills/` is scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) in CI, and the build fails on any non-suppressed finding.
Run the same scan locally before opening a pull request:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git
bin/scan-skills.sh <plugin-name>
```

When a finding is a reviewed false positive, suppress it in the plugin's `.skillspector-baseline.yaml` with a written reason; never suppress a finding you have not understood.

### Quick Reference: Asking Claude to Build a Plugin

Paste this into Claude Code to have it scaffold a new plugin for you:

```
Create a new Claude Code plugin called "<plugin-name>" in this repo.

It should have the following skills:
- <skill-1>: <what it does and what phrases trigger it>
- <skill-2>: <what it does and what phrases trigger it>

Follow the existing plugin patterns in this repo (plugins/workbench is the reference):
- Create plugins/<plugin-name>/.claude-plugin/plugin.json
- Create plugins/<plugin-name>/skills/<skill>/SKILL.md for each skill,
  with name/description/version frontmatter written to trigger on the phrases above
- Put contracts shared between skills in plugins/<plugin-name>/skills/shared/
- Create plugins/<plugin-name>/README.md with install instructions and usage
- Register in .claude-plugin/marketplace.json
- Run bin/scan-skills.sh <plugin-name> and resolve any SkillSpector findings
```

## License

MIT
