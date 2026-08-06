# Approval modes

Both skills run in one of two modes.
The mode changes which questions get asked; it never changes which conditions stop a run.

## Resolving the mode

Resolve it once at the start of a run, first match winning.
The profile may not be loaded yet at that point, so read only the `approval` field from `.workbench/config.md` if the file exists, and treat a missing file as no answer.
When first-run setup then establishes a mode later in the same run, that answer governs the rest of that run.

The invocation overrides everything, in either direction.
Phrases like "auto approve", "no need to ask", "just do it", or "run it through" mean auto for this run only.
Phrases like "ask me first", "check with me", or "gated" mean ask for this run only, even when the profile says auto.

Otherwise use the profile's `approval` field, which holds `auto` or `ask`.

Otherwise default to `ask`.

State the resolved mode at the start of the run so it is never a surprise, and say which source decided it.

## What auto mode skips

These are preferences.
Skipping them changes how much the run interrupts you, not whether it is correct.

- The issue draft in `scaffold`.
  Create the scaffold immediately and report what was created instead of asking first.
- The handoff question after scaffolding.
  Continue straight into `execute` on the new issue.
- A tracker or destination tie that the documented precedence can settle on its own.
  Resolve it by that precedence and report the choice rather than asking.
- Any first-run setup question whose answer is unambiguous: one destination available, or tracker state names that match the three phases exactly.
  Record the answer, and note in the profile that it was auto-accepted rather than confirmed, so a wrong destination is traceable later.

## What auto mode never skips

These are safety stops.
Auto mode exists to remove friction, not judgment, so every one of them still fires.

- **An unverified tracker MCP.** Still refuse and deliver setup instructions.
  Auto mode is not permission to work around a missing or disabled server.
  This stop is about the tracker only. An unverified forge is not a stop: it selects a capability tier per `forges.md`, and the run continues in that tier with the tier stated.
- **A test failure that cannot be fixed.** Still stop and hold.
  Never push broken work or open a review that implies verification that did not happen.
- **A conflict while updating from the base branch.** Still stop and hold, naming the conflicting files.
  Resolving a conflict unattended means silently discarding someone's changes.
- **A review closed without merging.** Still report it and ask.
  Whether to retry, rescope, or drop the work is a judgment call with no safe default.
  This now fires once per abandoned review rather than on every run, because the marker is recorded on the tracker instead of pushed to the base branch.
  The once guarantee holds only when the tracker can list comments; on the file-marker fallback the marker must land on the base branch to be seen from other clones, so a protected branch or a different clone can make the same review report again.
- **Accepting a forge CLI found by the tier-2 probe.** Still ask.
  Auto mode must never drive an unfamiliar CLI against the user's server unattended; anything executed against a forge is authorized by a written adapter, or by the user's explicit one-run acceptance of a named candidate at this stop, never by an inference made in the moment.
- **A phase with no matching tracker state.** Still ask.
  The alternative is silently mapping review onto a state that means something else.
- **An ambiguous first-run setup answer.** Still ask that specific question.
  A wrong destination sends every future issue in the repository to the wrong place, and a wrong state mapping misreports every issue's progress.
- **A reply whose target is unclear.** Still stop and ask which question it answered.
  Auto mode removes questions; it does not license guessing at answers.
- **An issue ref that disagrees with the current branch.** Still stop and ask which one to work.
  Guessing here means implementing the wrong issue, the same hazard as an unscoped task claim.
- **An issue already in the `done` phase.** Still stop and ask whether to reopen it or pick another.
  Auto mode has nothing safe to infer, since reopening finished work and silently doing nothing are both wrong.
- **Requirements too thin to break down.** Still ask the targeted questions.
  Auto mode skips approval of a draft; it never licenses inventing a breakdown that the requirements do not support.

This list exhausts the approval-mode stops by intent: everything auto mode is allowed to skip appears in the previous section, and any stop not listed there fires in both modes.
It does not enumerate every stop the skills define; unconditional stops that have nothing to do with approval, such as a required shared contract file that cannot be read, beads being unavailable for a repository whose task state lives in beads, or a task/commit reconciliation that fails, live with the procedures that define them and also fire in both modes.
When a new stop is added to either skill, decide explicitly whether it belongs to the skip list, this list, or the unconditional stops in the defining procedure.

## Recording it

First-run setup asks for the mode as its own question, after the tracker questions, and records it as `approval: auto` or `approval: ask` in `.workbench/config.md`.
Because the profile is committed, teammates inherit the choice.
Editing that field changes it permanently; an invocation phrase changes it for one run.
When one skill hands off to the other, carry the resolved mode across so a per-run override is not lost at the boundary; say which mode the handed-off run is using.

When auto mode auto-accepted a setup answer rather than having it confirmed, record that alongside the value, for example `default-destination: Prototypes (1209000000000001) # auto-accepted, only option`.
A later reader needs to know which answers a human actually gave.
