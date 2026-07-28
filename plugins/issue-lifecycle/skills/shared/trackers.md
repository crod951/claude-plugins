# Tracker adapters

Call the tracker only through the contract below.
Resolve the correct adapter at runtime, before doing any tracker work.
Never call tracker tools directly from a core skill body; always go through the operations named here.

## The contract

Use exactly these eight operations.
Adapter files implement each one against a specific tracker's tools; treat the operation names as the vocabulary for every other skill and adapter in this plugin.

| Operation | Purpose |
| --- | --- |
| `getIssue(ref)` | Fetch one issue's title, description, type/labels, URL, native id, current state, and existing children. |
| `listSubIssues(ref)` | List an issue's existing child issues, each with id, title, and state; use this when adopting an issue that may already have children. |
| `listDestinations()` | List where a new top-level issue can be created (Asana projects, Linear teams), each as a stable id paired with a display name. |
| `resolveDestination(hint?)` | Turn a caller-supplied hint, or the tracker profile's configured default when no hint is given, into one native destination id; return null when the result is ambiguous. |
| `createIssue(title, description, type, destination)` | Create a new top-level issue in the given destination; return its ref and URL. |
| `createSubIssue(parentRef, title, description)` | Create a new child issue under an existing parent; return its ref and URL. |
| `updateState(ref, phase)` | Move an issue to the given phase, where phase is one of `inProgress`, `inReview`, or `done`; apply it through the tracker profile's state mapping rather than a hardcoded status name. |
| `comment(ref, body)` | Post a comment on an issue. |

## Runtime resolution

Follow this procedure to decide which tracker owns a given reference, and to fail safely when that cannot be determined.

Treat a reference shaped like `ABC-123` (a short uppercase prefix, a dash, and digits) as Linear.
Treat an Asana URL or a bare numeric GID as Asana.
When the reference's shape does not clearly indicate a tracker, check which tracker MCP is connected.
When exactly one tracker MCP is connected, use that tracker.
When both tracker MCPs are connected and the reference is still ambiguous, ask the user once which tracker they mean; do not guess.
When the reference is ambiguous and neither tracker MCP is connected, stop immediately and report a clear message naming both supported trackers, Asana and Linear, and telling the user to connect one before retrying.
Never guess a tracker for an ambiguous reference when no tracker MCP is connected, and never proceed as if one were resolved.
Once a tracker is chosen, discover that connected MCP's actual tool names at runtime rather than assuming fixed names.
Adapter files list the typical tool names for each tracker, but real builds vary, so treat those names as a starting hint, not a guarantee.
When the resolved tracker's MCP is not connected, stop immediately and report a clear message naming the specific missing MCP.
Never fall back to the other tracker when the resolved tracker's MCP is unavailable; a Linear reference must never be silently handled by Asana, and vice versa.

## First-run tracker profile

Run this setup procedure once per repository, then reuse its output on every later run.

Trigger setup when the repository has no `.issue-lifecycle/config.md`.
Before prompting the user, check other local branches for a newer `.issue-lifecycle/config.md` and offer to reuse it instead of starting over.
When no existing profile is found anywhere, inspect what the connected tracker actually offers: for Linear, list the team's workflow states; for Asana, list the project's board sections and any status custom fields.
Propose a mapping from those tracker-specific states to the three phases (`inProgress`, `inReview`, `done`).
Show the proposed mapping to the user and let them confirm it or correct it before saving anything.
Save the confirmed profile to `.issue-lifecycle/config.md` and commit that file; include the default destination to use for intake when no explicit destination is given.

Use this format for the profile:

```markdown
# issue-lifecycle tracker profile
tracker: asana
default-destination: Prototypes (1209000000000001)
state-mapping:
  inProgress: section "In Progress"
  inReview: section "Review"
  done: section "Done" + completed
```

On every subsequent run, read the existing profile silently and use it without re-prompting.
Re-run setup when a mapped state no longer exists in the tracker, or when the user explicitly asks to redo it.
Re-run setup to resolve merge conflicts in `.issue-lifecycle/config.md`; do not attempt to hand-merge the conflicting mapping.
