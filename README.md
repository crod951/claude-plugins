# claude-plugins

Custom Claude Code plugins for codebase analysis, skill generation, and workflow automation.

## Installation (inside Claude Code)

Run these commands **inside a Claude Code session** (they start with `/`):

```
/plugin marketplace add crod951/claude-plugins
/plugin install stackgen@crod951
```

> Individual plugins may have additional prerequisites that run in your **terminal** (e.g., `brew install`). See each plugin's README for details.

## Available Plugins

### stackgen (v2.0.0)

Analyzes codebases and generates tailored Claude Code skills. **11 specialized agents** with optimized context passing.

#### Features

- **Fast Detection** - Single stack-detector (Haiku) analyzes dependencies, configs, structure
- **Context Passing** - Detector findings passed to analyzers to avoid redundant reads
- **Tech Gating** - Only spawns analyzers for detected technologies
- **8-File Limits** - Each analyzer reads max 8 files for efficiency

#### Commands

| Command | Description |
|---------|-------------|
| `/stackgen:analyze` | Full codebase analysis and skill generation |
| `/stackgen:quick` | Quick tech stack overview |
| `/stackgen:refresh` | Update existing skills |
| `/stackgen:check` | Audit skills for issues |

#### Agents

**Detection (1):**
- `stack-detector` - Comprehensive dependency/config/pattern analysis (Haiku)

**Core Analyzers (4, always run):**
- `security-analyzer` - Security patterns and best practices
- `architecture-analyzer` - Code structure and organization
- `code-quality-analyzer` - Linting, formatting, types, dependencies
- `performance-analyzer` - Performance optimization

**Conditional Analyzers (6, gated by detection):**
- `frontend-analyzer` - UI framework patterns (React, Vue, Angular)
- `backend-analyzer` - Server patterns (APIs, Server Actions)
- `database-analyzer` - ORM/database patterns
- `testing-analyzer` - Unit, integration, E2E tests
- `devops-analyzer` - CI/CD, Docker, deployment
- `monitoring-analyzer` - Logging, error tracking, analytics

#### Generated Skills

```
.claude/skills/
├── security/
├── architecture/
├── code-quality/
├── performance/
├── frontend/       (if detected)
├── backend/        (if detected)
├── database/       (if detected)
├── testing/        (if detected)
├── devops/         (if detected)
└── monitoring/     (if detected)
```

---

### issue-lifecycle (v2.1.0)

Automates the full lifecycle of working on Linear issues — from planning through PR creation. Integrates **Linear**, **Beads task tracking**, and **GitHub PRs** with Conventional Commits.

#### Prerequisites

- [Linear MCP plugin](https://github.com/anthropics/claude-code-plugins) installed and configured
- [Beads CLI](https://github.com/steveyegge/beads) installed (`bd` command available)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh` command available)

#### Install

```bash
/plugin install issue-lifecycle@crod951
```

#### Commands

| Command | Description |
|---------|-------------|
| `/issue-start <ID>` | Fetch issue, create plan, Beads tasks, branch, update Linear |
| `/issue-task [ID]` | Work on next unblocked task, present for review |
| `/commit` | Semantic commit + close Beads task |
| `/issue-finish [ID]` | Push, create PR, update Linear, post completion comment |

#### Auto-Loop Flags

| Flag | Command | Description |
|------|---------|-------------|
| `--auto` | `/issue-task` | Loop through all tasks: implement, commit, next — automatically |
| `--finish` | `/issue-task` | Also push + PR + Linear update after last task. Requires `--auto` |
| `--on-failure=stop\|skip` | `/issue-task` | Halt on failure (default) or skip and continue. Requires `--auto` |
| `--auto` | `/issue-start` | Chain into auto-loop after plan approval and setup |
| `--no-confirm` | `/issue-start` | Skip plan approval pause. Requires `--auto` |
| `--base <branch>` | `/issue-finish` | Target branch for the PR. Auto-detects repo default if omitted |

```bash
# Fully autonomous, zero pauses
/issue-start ONC-5 --auto --no-confirm

# Auto-loop tasks only (manual start/finish)
/issue-task --auto

# Auto-loop + auto-finish
/issue-task --auto --finish --on-failure=skip
```

#### Features

- **Plan-first workflow** — researches your codebase and writes a plan document before any code changes
- **Review checkpoints** — pauses for your approval after planning and after each task implementation
- **Auto-loop mode** — `--auto` implements all tasks continuously with inline commits, no manual steps between tasks
- **Fully autonomous option** — `/issue-start --auto --no-confirm` runs the entire lifecycle with zero pauses
- **Branch naming** — auto-generates semantic branches from Linear labels (`feat/`, `fix/`, `chore/`, `docs/`)
- **Conventional Commits** — auto-detects commit type and formats as `type(ISSUE-ID): description`
- **Safety rails** — warns on uncommitted changes, incomplete tasks, and issue ID mismatches
- **Linear integration** — updates status to In Progress / In Review and posts completion comments

#### Workflow

**Manual (default):**

```
/issue-start ONC-5       # Fetch issue → research → plan → review → branch
    ↓
/issue-task               # Claim next task → implement → present for review
    ↓
/commit                   # Stage → commit → close Beads task
    ↓
  (repeat /issue-task + /commit for each task)
    ↓
/issue-finish             # Pre-flight checks → push → PR → update Linear
```

**Autonomous:**

```
/issue-start ONC-5 --auto --no-confirm    # Everything, zero pauses
```

#### Linear Status Lifecycle

```
Todo → In Progress (/issue-start) → In Review (/issue-finish) → Done (PR merge)
```

See the [full step-by-step guide](./plugins/issue-lifecycle/README.md) for a detailed walkthrough.

---

## Workflow

**stackgen:**
1. **Analyze project**: `/stackgen:analyze`
2. **Quick context**: `/stackgen:quick`
3. **After upgrades**: `/stackgen:refresh`
4. **Maintenance**: `/stackgen:check`

**issue-lifecycle (manual):**
1. **Start issue**: `/issue-start ONC-5`
2. **Work on tasks**: `/issue-task` (repeat)
3. **Commit work**: `/commit` (after review)
4. **Finish issue**: `/issue-finish`

**issue-lifecycle (autonomous):**
1. **Everything**: `/issue-start ONC-5 --auto --no-confirm`

---

## Contributing: Adding Plugins, Commands, and Agents

This section is a comprehensive reference for adding new plugins, slash commands, or agents to this repo. You can paste these instructions into Claude Code to have it build new components for you.

### Repository Structure

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json           # Registry — lists all plugins in this marketplace
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json        # Plugin manifest (name, version, description)
│       ├── README.md              # Plugin documentation
│       ├── commands/              # Slash commands (each file = one /command)
│       │   └── <command-name>.md
│       └── agents/                # Subagents (optional, used by commands)
│           └── <agent-name>.md
```

### How It All Fits Together

- **Marketplace** (`.claude-plugin/marketplace.json`) — the top-level registry that tells Claude Code which plugins exist in this repo and where to find them
- **Plugin** (`plugins/<name>/.claude-plugin/plugin.json`) — a self-contained package of commands and/or agents
- **Command** (`plugins/<name>/commands/<command>.md`) — a markdown file that becomes a `/command` the user can invoke. The filename becomes the command name (e.g., `commit.md` → `/commit`)
- **Agent** (`plugins/<name>/agents/<agent>.md`) — a markdown file that defines a subagent. Agents are spawned by commands using the Task tool — they can't be invoked directly by users

### Adding a New Slash Command to an Existing Plugin

This is the simplest contribution. Create a new `.md` file in the plugin's `commands/` directory.

**Command file format:**

````markdown
---
description: Short description shown in the command palette
argument-hint: "<REQUIRED_ARG> [optional-arg] [--flag]"
allowed-tools: Bash(git add:*), Bash(git commit:*)
---

## Context

Dynamic values injected at runtime using `!` backtick syntax:

- Current branch: !`git branch --show-current`
- Git status: !`git status`
- Custom check: !`some-cli-command 2>/dev/null || echo "FALLBACK"`

## Instructions

You are doing X. Follow these steps precisely.

### Step 1: Do the first thing

Explain what Claude should do. Use `$ARGUMENTS` to reference user input.

### Step 2: Do the next thing

Include code blocks for commands Claude should run:

```bash
some-command --flag value
```

### Step 3: Present results

```
--- Summary ---
  Result: <value>
---------------
```
````

**Frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `description` | Yes | Help text shown when user types `/` |
| `argument-hint` | No | Describes expected arguments. Use `<REQUIRED>` and `[optional]` |
| `allowed-tools` | No | Restricts which tools Claude can use. Omit to allow all tools. Format: `Bash(pattern:*)` |

**Key patterns:**

- **`$ARGUMENTS`** — replaced with whatever the user types after the command name
- **`!` backtick context** — shell commands in the Context section run at invocation time and inject their output
- **`AskUserQuestion`** — use this tool to ask the user for input during execution
- **MCP tools** — reference them by full name (e.g., `mcp__plugin_linear_linear__get_issue`)
- **Flags** — parse from `$ARGUMENTS` in a dedicated step. Commands don't have built-in flag parsing — you write instructions for Claude to parse them

**Example — a simple deploy command:**

````markdown
---
description: Deploy the current branch to staging
argument-hint: "[--production]"
allowed-tools: Bash(git push:*), Bash(deploy:*)
---

## Context

- Current branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`

## Instructions

### Step 1: Parse flags

Check if `$ARGUMENTS` contains `--production`. If yes, target is production. Otherwise, target is staging.

### Step 2: Confirm with user

Use `AskUserQuestion` to confirm:
- "Deploy `<branch>` (`<last commit>`) to `<target>`?"
- Options: "Deploy", "Cancel"

### Step 3: Deploy

```bash
deploy --target <target> --branch <branch>
```

### Step 4: Show result

```
--- Deployed ---
  Branch:  <branch>
  Target:  <target>
  Commit:  <last commit>
----------------
```
````

### Adding a New Agent to an Existing Plugin

Agents are subagents spawned by commands via the Task tool. They are markdown files with no YAML frontmatter.

**Agent file format:**

```markdown
# Agent Name Agent

You are a specialized agent for [purpose].

## Activation Condition

Only activate if [condition from detector/context].

## Your Mission

[What this agent does]

## Constraints

- **Max 8 files**: Focus on the most representative files
- **Prioritize**: [what to focus on]
- **Use context**: Reference findings passed to you, avoid re-scanning

## Analysis Areas

### 1. Area Name
- Point 1
- Point 2

### 2. Another Area
- Point 1

## Output Format

[Template for what the agent should produce]
```

Agents are invoked from commands like this (in the command's markdown):

```
Spawn the `agent-name` agent with the following context: [data to pass]
```

### Creating a New Plugin from Scratch

Follow these steps:

**1. Create the directory structure:**

```
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json
├── README.md
└── commands/
    └── <first-command>.md
```

**2. Write `plugin.json`:**

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

**3. Register in the marketplace:**

Add an entry to `.claude-plugin/marketplace.json` in the `plugins` array:

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

**4. Write your commands** (see "Adding a New Slash Command" above)

**5. Write a README.md** with installation instructions, command reference, and usage examples

**6. Bump the version** in both `plugin.json` and `marketplace.json` whenever you make changes

### Writing Good Commands: Tips

- **Be precise** — Claude follows your instructions literally. Vague instructions produce vague results.
- **Number your steps** — sequential steps prevent Claude from skipping or reordering.
- **Use conditionals explicitly** — "If X, do Y. Otherwise, do Z." Don't leave ambiguity.
- **Gate dangerous actions** — use `AskUserQuestion` before destructive operations (deletes, force pushes, etc.)
- **Inject context** — use `!` backtick commands to give Claude runtime awareness (branch name, git status, file lists, etc.)
- **Restrict tools when needed** — use `allowed-tools` to prevent Claude from doing things outside the command's scope (e.g., a commit command shouldn't read random files)
- **Show examples in output** — template the exact output format you want Claude to produce
- **Don't commit for the user** — if the command makes code changes, present results and let the user decide. Separate "implement" from "commit" commands.
- **Keep commands focused** — one command should do one thing well. Chain commands together for workflows.

### Quick Reference: Asking Claude to Build a Plugin

Paste this into Claude Code to have it scaffold a new plugin for you:

```
Create a new Claude Code plugin called "<plugin-name>" in this repo.

It should have the following commands:
- /<command-1>: <what it does>
- /<command-2>: <what it does>

Follow the existing plugin patterns in this repo:
- Create plugins/<plugin-name>/.claude-plugin/plugin.json
- Create plugins/<plugin-name>/commands/<command>.md for each command
- Create plugins/<plugin-name>/README.md with install instructions and usage
- Register in .claude-plugin/marketplace.json

Use the same conventions as the existing plugins:
- YAML frontmatter with description and argument-hint
- Context section with runtime shell commands
- Numbered step-by-step instructions
- Output summaries in fenced code blocks
```

## License

MIT
