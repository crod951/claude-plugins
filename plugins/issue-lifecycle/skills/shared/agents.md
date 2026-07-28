# Agent notes

These skills follow the open Agent Skills standard (SKILL.md, agentskills.io) and run unchanged in Claude Code and Kiro.
This file holds only the differences that are specific to each agent.
Read the rest of this plugin's skills as agent-neutral; when you need an agent-specific detail, come back here.

## Install

Claude Code: install this plugin from its marketplace repo.
Kiro: copy or symlink this plugin's `skills/` directory into `.kiro/skills/` for a workspace install, or into `~/.kiro/skills/` for a global install.

## Task display overlay

The shared memory contract defines a durable backend as the only source of truth for task state, plus an optional display overlay for a live progress UI.
Read `shared/memory.md` before this section; do not treat what follows as a replacement for its display-overlay rule.

Claude Code: mirror tasks into the TaskCreate/TaskUpdate/TaskList/TaskGet tool family.
Kiro: use its built-in todo/task tools when the workspace exposes them; when it does not expose such tools, skip the overlay silently.

In both cases, the overlay is display only, never the source of truth.
Rebuild it from the durable backend on every resume.
Skip it silently when the agent exposes no such tools.

## MCP tool naming

Tool name prefixes for a connected tracker MCP server differ per agent and per MCP build.
Do not hardcode any tracker tool name in any skill, script, or note.
Discover the connected tracker server's actual tool names at runtime, every run, before calling any of them.

## Permissions

For smooth autonomous runs, pre-approve these command families ahead of time: `git`, `gh`, `bd`, and whichever tool names the runtime discovery step in the previous section resolves for the connected tracker MCP server.

Claude Code: add these to the permissions allowlist in settings (project or user settings.json).
Kiro: add these to its trusted/allowed command configuration.

Without this pre-approval, each command triggers an interactive confirmation prompt and breaks autonomous execution.
