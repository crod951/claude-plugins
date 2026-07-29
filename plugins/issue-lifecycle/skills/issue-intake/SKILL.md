---
name: issue-intake
description: This skill should be used when the user asks to "turn these requirements into an issue", "create an issue and sub-issues", "scaffold an issue from this PRD or spec", or "break these requirements into tickets" for Asana or Linear. Creates a main issue plus linked sub-issues, then offers to hand off to the issue-lifecycle skill.
version: 3.0.0
---

# Issue Intake

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse the request and stop.
Say which MCP is missing and that the user must connect it before this skill can continue.
Refuse even when a bypass looks possible and helpful.
Do not read or search for credentials in files, environment variables, or token caches.
Do not call tracker HTTP APIs.
Do not edit MCP or agent configuration.
Treat a disabled server as a deliberate user decision, a stop condition, never an obstacle to route around.

This skill turns requirements text into a scaffolded tracker issue plus its sub-issues.
Requirements text goes in; a main issue and its linked sub-issues come out.
Nothing is created in the tracker before the user approves the draft.
Tracker access goes only through the connected tracker MCP; when it is missing, stop and say so; never hunt for credentials on disk or call tracker APIs directly.
This skill does not create or write any task-memory or checklist files.
The issue-lifecycle skill creates task memory itself when it runs its breakdown.

## Read first

Before doing any tracker work, read:

These paths are relative to the directory containing this SKILL.md file, not the current workspace.
In a global Kiro install they resolve under `~/.kiro/skills/` (for example `~/.kiro/skills/shared/trackers.md`); in a Claude Code plugin install they resolve inside the plugin's `skills/` directory.

- `../shared/trackers.md` for the tracker contract and the tracker profile default destination.
- `../shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.

If any of these files cannot be found and read, stop immediately and report which paths were tried - never improvise their contracts from memory or proceed without them.

## Procedure

1. Run preflight verification as described in `../shared/trackers.md` before any other step; stop there when the tracker's MCP does not verify.
2. Run the Asana done-on-merge sweep described in `../shared/trackers/asana.md`; this sweep is itself tracker work, so it only runs once preflight has verified the MCP.
3. Resolve the tracker, then the destination.
   - There is no existing issue ref to infer the tracker from, so resolve it explicitly before anything else.
   - When the invocation names a tracker, use that tracker.
   - Otherwise, when the tracker profile records a tracker, use that tracker.
   - Otherwise, check which tracker MCP is connected.
   - When exactly one tracker MCP is connected, use that tracker.
   - When both tracker MCPs are connected, ask the user once which one to use.
   - When neither tracker MCP is connected, stop and report a clear message naming both supported trackers, Asana and Linear.
   - Once the tracker is resolved, when the user gave an explicit destination hint, resolve it with `resolveDestination`.
   - Otherwise resolve the tracker profile's configured default destination.
   - When there is no hint and no configured default, call `listDestinations` and ask the user once which one to use.
4. Draft the scaffold from the requirements text.
   - Write a main issue title and a description that summarizes the requirements.
   - Infer the main issue's type from the requirements, one of feature, bug, chore, or docs, defaulting to feature when the requirements do not indicate one.
   - Break the requirements into three to seven sub-issue drafts, each sized as an independently implementable unit of work.
   - Show the full draft, main issue title, type, description, and every sub-issue, to the user and wait for approval before creating anything.
   - Apply any edits the user requests, then show the revised draft again until it is approved.
5. Create the approved scaffold.
   - Call `createIssue` for the main issue using the approved title, description, type, and resolved destination.
   - Call `createSubIssue` once per approved sub-issue draft, linking each to the newly created main issue.
   - Report the URL for the main issue and for every sub-issue that was created.
   - Report each issue's ref using that tracker's issue ref scheme, as defined in that tracker's adapter file, and hand off using that ref; for Asana this is the short `asana-<last six digits of the GID>` form, never the full GID.
6. A per-invocation destination hint applies only to the issue just created; do not overwrite the tracker profile's saved default because of it.
   Write `default-destination` into the tracker profile only when the profile currently has none, or when the user explicitly asks to change the default.
7. Offer the handoff: ask "run issue-lifecycle on <ref> now?", where `<ref>` is the main issue just created.
   - When the user says yes, invoke the issue-lifecycle skill on that ref.
   - When the user says no, stop here and leave the issue in the tracker for a later run.
