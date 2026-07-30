# Agent notes

These skills follow the open Agent Skills standard (SKILL.md, agentskills.io) and run unchanged in Claude Code and Kiro.
This file holds only the differences that are specific to each agent.
Read the rest of this plugin's skills as agent-neutral; when you need an agent-specific detail, come back here.

## Install

Claude Code: install this plugin from its marketplace repo.
Kiro: copy or symlink the contents of this plugin's `skills/` directory into `.kiro/skills/` for a workspace install, or into `~/.kiro/skills/` for a global install, so that `execute/`, `scaffold/`, and `shared/` sit as siblings directly under the destination; copying the `skills/` directory itself would nest them one level too deep and break every `../shared/` reference.

## Task display overlay

The shared memory contract defines a durable backend as the only source of truth for task state, plus an optional display overlay for a live progress UI.
Read `memory.md` before this section; do not treat what follows as a replacement for its display-overlay rule.

Claude Code: mirror tasks into the TaskCreate/TaskUpdate/TaskList/TaskGet tool family.
Kiro: use its built-in todo/task tools when the workspace exposes them; when it does not expose such tools, skip the overlay silently.

The rules governing the overlay live in `memory.md` and are not restated here, so the two files cannot drift apart.
This file only names which tools each agent offers for it.

## MCP tool naming

Tool name prefixes for a connected tracker MCP server differ per agent and per MCP build.
Do not hardcode any tracker tool name in any skill, script, or note.
Discover the connected tracker server's actual tool names at runtime, every run, before calling any of them.

Tool coverage also differs, not just tool names.
One Asana build exposed a section-move tool and moved tasks between board sections, while another exposed none and correctly degraded to a phase comment through the adapter's fallback chain.
Expect that variation, and see `trackers/asana.md` for the details.

## Structured questions

Prefer a structured, multiple-choice question over free prose whenever this plugin asks the user to choose something, such as the tracker, the destination, the state mapping, or a one-time offer.
Concrete options are easier to answer unambiguously, which matters because an ambiguous reply must never be treated as approval.

Claude Code: use its built-in question tool that renders selectable options.
Kiro: use an equivalent structured prompt when the workspace exposes one; otherwise ask in prose, numbering the options so the reply can name one.

## Permissions

For smooth autonomous runs, pre-approve these command families ahead of time: `git`, `gh`, `bd`, and whichever tool names the runtime discovery step in the previous section resolves for the connected tracker MCP server.

Claude Code: add these to the permissions allowlist in settings (project or user settings.json).
Kiro: add these to its trusted/allowed command configuration.

Without this pre-approval, each command triggers an interactive confirmation prompt and breaks autonomous execution.
