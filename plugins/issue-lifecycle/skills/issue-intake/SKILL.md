---
name: Issue Intake
description: This skill should be used when the user asks to "turn these requirements into an issue", "create an issue and sub-issues", "scaffold an issue from this PRD or spec", or "break these requirements into tickets" for Asana or Linear. Creates a main issue plus linked sub-issues, then offers to hand off to the issue-lifecycle skill.
version: 3.0.0
---

# Issue Intake

This skill turns requirements text into a scaffolded tracker issue plus its sub-issues.
Requirements text goes in; a main issue and its linked sub-issues come out.
Nothing is created in the tracker before the user approves the draft.

## Read first

Before doing any tracker work, read:

- `../shared/trackers.md` for the tracker contract and the tracker profile default destination.
- `../shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.

## Procedure

1. Run the Asana done-on-merge sweep described in `../shared/trackers/asana.md` before any other tracker work in this repository.
2. Resolve the tracker, then the destination.
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
3. Draft the scaffold from the requirements text.
   - Write a main issue title and a description that summarizes the requirements.
   - Infer the main issue's type from the requirements, one of feature, bug, chore, or docs, defaulting to feature when the requirements do not indicate one.
   - Break the requirements into three to seven sub-issue drafts, each sized as an independently implementable unit of work.
   - Show the full draft, main issue title, type, description, and every sub-issue, to the user and wait for approval before creating anything.
   - Apply any edits the user requests, then show the revised draft again until it is approved.
4. Create the approved scaffold.
   - Call `createIssue` for the main issue using the approved title, description, type, and resolved destination.
   - Call `createSubIssue` once per approved sub-issue draft, linking each to the newly created main issue.
   - Report the URL for the main issue and for every sub-issue that was created.
5. When the resolved destination differs from the tracker profile's configured default, save the new destination to the tracker profile.
6. Offer the handoff: ask "run issue-lifecycle on <ref> now?", where `<ref>` is the main issue just created.
   - When the user says yes, invoke the issue-lifecycle skill on that ref.
   - When the user says no, stop here and leave the issue in the tracker for a later run.
