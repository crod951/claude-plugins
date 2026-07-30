---
name: scaffold
description: This skill should be used when the user asks to "scaffold these requirements", "scaffold an issue from this PRD or spec", "turn these requirements into an issue", "create an issue and sub-issues", or "break these requirements into tickets" for Asana or Linear. Creates a main issue plus linked sub-issues, then offers to hand off to the execute skill.
version: 1.0.0
---

# Scaffold

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse the request and stop.
Say which MCP is missing and that the user must connect it before this skill can continue.
Refuse even when a bypass looks possible and helpful.
Do not read or search for credentials in files, environment variables, or token caches.
Do not call tracker HTTP APIs.
Do not edit MCP or agent configuration.
Treat a disabled server as a deliberate user decision, a stop condition, never an obstacle to route around.

This skill turns requirements into a scaffolded tracker issue plus its linked sub-issues.
In ask mode nothing is created in the tracker before the user approves the draft; in auto mode the scaffold is created without that approval, per `../shared/approval.md`.
Tracker access goes only through the connected tracker MCP; when it is missing, stop and say so; never hunt for credentials on disk or call tracker APIs directly.
This skill never writes task-memory or checklist files; the execute skill creates task memory when it runs its breakdown.

## Read first

Before doing any tracker work, read:

These paths are relative to the directory containing this SKILL.md file, not the current workspace.
In a global Kiro install they resolve under `~/.kiro/skills/` (for example `~/.kiro/skills/shared/trackers.md`); in a Claude Code plugin install they resolve inside the plugin's `skills/` directory.

- `../shared/trackers.md` for the tracker contract and the tracker profile default destination.
- `../shared/agents.md` for the per-agent notes, including the structured question mechanism to prefer whenever this procedure asks the user anything.
- `../shared/approval.md` for the two approval modes, and for the stops that hold in both.

If any of these files cannot be found and read, stop immediately and report which paths were tried - never improvise their contracts from memory or proceed without them.

## Procedure

1. Resolve the approval mode per `../shared/approval.md` and state it.
   Then determine whether the tracker is already settled: a profile records one, or exactly one tracker MCP is connected.
   When it is settled, run preflight verification against that tracker as described in `../shared/trackers.md`; stop there when the tracker's MCP does not verify.
   When it is not settled, because no profile exists and both tracker MCPs are connected, do not guess which MCP to verify: defer preflight to step 3, which asks the tie-break question first and then runs preflight against the answer.
2. Run the done-on-merge sweep for the resolved tracker, whose mechanics are in `../shared/trackers/asana.md` and apply to Linear too; it is tracker work, so it only runs once preflight has verified the MCP.
   When preflight was deferred in step 1, defer this sweep with it; step 3 runs both once the tracker is chosen.
3. Resolve the tracker, then the destination.
   - There is no existing issue ref to infer the tracker from, so this step settles the tracker explicitly.
   - Preflight and the sweep in the previous steps run against the tracker inferred from the profile, or from the single connected MCP when there is no profile; when neither settles it, do the tie-break question here first and then run preflight and the sweep against the answer before continuing.
   - Use the tracker the invocation names; otherwise the one the tracker profile records; otherwise check which tracker MCPs are connected.
   - With exactly one connected, use it; with both connected, ask the user once which one to use.
   - When neither tracker MCP is connected, stop and report a clear message naming both supported trackers, Asana and Linear.
   - Once the tracker is resolved, when the user gave an explicit destination hint, resolve it with `resolveDestination`.
   - Otherwise resolve the tracker profile's configured default destination.
   - When there is no hint and no configured default, call `listDestinations`, list them to the user, and ask once which one to use; do not infer a destination from any other source.
   - A suggestion drawn from prior issues in the repo may accompany that question, but the question must still be asked and answered before anything is created.
   - When the repository has no tracker profile at all, run first-run setup from `../shared/trackers.md` to completion before showing the issue draft: confirm the destination, confirm the state mapping, then run the adapter's profile-load offers, such as the merge-closer Action.
     Ask each setup question on its own and get its answer before asking the next; never show the issue draft while a setup question is still unanswered.
4. Gather the requirements before drafting.
   - Take them from the invocation itself when the text is there.
   - When the invocation names or points at a file, such as a PRD, spec, or design doc, read that file and use it as the requirements; a path or filename in the request means read it rather than working from the filename alone.
   - Otherwise use the requirements established earlier in this conversation.
   - Summarize what you understood in one or two sentences so the user can catch a misread before any drafting happens.
5. Ground the breakdown in the codebase before drafting.
   - Search and read the files the requirements would touch, and note the existing patterns, module boundaries, and test style you find.
   - Use that to name real files and real functions in the sub-issue drafts, since a breakdown that names actual paths is actionable and one written from prose alone is generic.
   - When the repository has nothing related yet, say so and draft from the requirements alone.
6. Judge whether the requirements can carry a breakdown at all.
   - When they are too thin to split sensibly, when scope is unclear, or when two incompatible readings are both plausible, do not invent a confident breakdown.
   - Ask targeted questions about exactly what is missing, one question at a time, and wait for answers before drafting.
   - Prefer the structured question mechanism named in `agents.md` for those questions.
7. Draft the scaffold from the gathered requirements and the codebase context.
   - Write a main issue title and a description that summarizes the requirements.
   - Infer the main issue's type from the requirements, one of feature, bug, chore, or docs, defaulting to feature when the requirements do not indicate one.
   - Break the requirements into three to seven sub-issue drafts, each sized as an independently implementable unit of work.
   - In ask mode, show the full draft, main issue title, type, description, and every sub-issue, to the user and wait for approval before creating anything.
   - In auto mode, skip that approval: create the scaffold immediately and report the same draft content as what was created.
   - Draft approval must be the only open question in that turn; never show it alongside a setup question or any other unanswered question.
   - In ask mode, apply any edits the user requests, then show the revised draft again until it is approved.
   - When a reply could answer more than one open question, or its target is unclear, stop and ask which question it answered; do not guess.
   - In ask mode, treat only an explicit, unambiguous approval of the draft as permission to create anything; never treat an ambiguous or negative reply, such as a bare "decline", as draft approval.
8. Create the scaffold, once approved in ask mode or immediately in auto mode.
   - Call `createIssue` for the main issue using the approved title, description, type, and resolved destination.
   - Call `createSubIssue` once per approved sub-issue draft, linking each to the newly created main issue.
   - Report the result as a compact block listing the tracker, the main issue ref, title and URL, then one line per sub-issue with its ref and URL, so the scaffold is scannable at a glance.
   - Report each issue's ref using that tracker's issue ref scheme, as defined in that tracker's adapter file, and hand off using that ref; for Asana this is the short `asana-<last six digits of the GID>` form, never the full GID.
9. A per-invocation destination hint applies only to the issue just created; do not overwrite the tracker profile's saved default because of it.
   Write `default-destination` into the tracker profile only when the profile currently has none, or when the user explicitly asks to change the default.
10. Hand off. In ask mode, ask "run execute on <ref> now?"; in auto mode, invoke the execute skill on that ref without asking and say that you are doing so.
   - When the user says yes, invoke the execute skill on that ref.
   - When the user says no, stop here and leave the issue in the tracker for a later run.
