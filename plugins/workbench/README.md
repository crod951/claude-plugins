# Workbench

Workbench is a pair of agent skills that carry a tracker issue from requirements to an open pull request.

- **scaffold** turns requirements into a tracker issue plus linked sub-issues.
- **execute** drives an existing issue through implementation to a pull request, one task at a time.

It works with **Asana** or **Linear**, and runs unchanged on **Claude Code** and **Kiro** because both follow the open Agent Skills standard.

> Built for frontier-model agents.
> There is no small-model mode.

## Contents

- [What you get](#what-you-get)
- [Install](#install)
- [Setup, step by step](#setup-step-by-step)
- [Using scaffold](#using-scaffold)
- [Using execute](#using-execute)
- [Approval modes](#approval-modes)
- [Decision trees](#decision-trees)
- [What lands in your repo](#what-lands-in-your-repo)
- [How the tracker learns a PR merged](#how-the-tracker-learns-a-pr-merged)
- [Working conventions](#working-conventions)
- [Security boundary](#security-boundary)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Developing this plugin](#developing-this-plugin)
- [Upgrading](#upgrading)

## What you get

A run of the two skills back to back produces: a tracker issue with sub-issues, a feature branch, a plan document a reviewer can read before any code exists, one commit per unit of work, a pull request whose body links the issue and lists what was verified, and the issue sitting in review.

The design goal is that **nothing is remembered between invocations**.
Every run reads state from your repository and your tracker, so an interrupted run resumes by being re-invoked, in either agent.

Resuming on a *different* machine works for whatever was committed and pushed.
The checklist backend travels with each task commit; beads keeps its database out of git by design and shares only its export, so a beads run commits that export alongside each task for the same reason.

**Requirements:** an Asana or Linear MCP connected in your agent, the GitHub CLI (`gh`) authenticated, and optionally the beads CLI (`bd`) for richer task memory.

## Install

### Claude Code

Run these inside a Claude Code session:

```
/plugin marketplace add crod951/claude-plugins
/plugin install workbench@crod951
/reload-plugins
```

Confirm both skills loaded by asking for the skill list; you should see `workbench:execute` and `workbench:scaffold`.

### Kiro

Kiro reads skills from a directory, so copy or symlink them.
Keep `execute/`, `scaffold/`, and `shared/` as siblings at the destination's top level, because each skill reaches its shared references with `../shared/`.

```bash
# global install, available in every workspace
cp -r plugins/workbench/skills/. ~/.kiro/skills/

# or workspace-only
cp -r plugins/workbench/skills/. .kiro/skills/
```

Symlinking instead of copying is better while iterating, since edits take effect immediately:

```bash
ln -s "$PWD/plugins/workbench/skills/execute"  ~/.kiro/skills/execute
ln -s "$PWD/plugins/workbench/skills/scaffold" ~/.kiro/skills/scaffold
ln -s "$PWD/plugins/workbench/skills/shared"   ~/.kiro/skills/shared
```

## Setup, step by step

### 1. Connect your tracker's MCP

Asana or Linear, whichever you use.
In Claude Code install and authenticate the matching MCP plugin; in Kiro add the server to `mcp.json`.

Tool names are discovered at runtime, so any recent build works.
If a server exists but is disabled, that counts as missing: the skills refuse to run rather than guess.

For Asana specifically, prefer the **V2** server (`https://mcp.asana.com/v2/mcp`).
The V1 beta server is deprecated and, in testing, exposed no tool for moving a task between board sections, which downgrades phase transitions to comments.

### 2. Authenticate the GitHub CLI

`execute` opens pull requests with `gh`, so this is not optional.

```bash
brew install gh
gh auth login
```

### 3. Optionally install beads

Without beads, task state lives in a markdown checklist committed on your branch, which is fine for solo work and small issues.
Both backends honor task dependencies, so a task cannot be started before the work it depends on is finished; beads adds atomic claiming, a queryable ready-work view, and a notes field for commit hashes.

```bash
brew install beads
bd version
```

### 4. Answer the first-run questions

The first time either skill runs in a repository it asks a short series of questions, one at a time, and writes the answers to `.workbench/config.md`.
Because that file is committed, **teammates who clone the repo are never asked any of it**.

| Question | Why it is asked |
| --- | --- |
| Which tracker? | Only when both MCPs are connected and nothing else settles it. |
| Which destination? | The Asana project or Linear team new issues go to. |
| How do your states map? | Your real board sections or workflow states get mapped to three phases: in progress, in review, done. |
| How should the tracker learn a PR merged? | Asana and Linear differ; see [How the tracker learns a PR merged](#how-the-tracker-learns-a-pr-merged). |
| Which base branch? | Feature branches start from it and pull requests target it. Defaults to your current branch, unless that is itself a workbench branch. |
| Stop for approval, or run straight through? | Sets the default approval mode for future runs. See [Approval modes](#approval-modes). |

If your tracker has no state for a phase, which is common for review states in a fresh Linear team, the skill says so and offers real choices rather than silently picking the nearest state.

### 5. Pre-approve the commands

Autonomous runs stall on permission prompts.
Pre-approve `git`, `gh`, `bd`, and your tracker MCP's tools: in Claude Code through the permissions allowlist, in Kiro through trusted commands.

Read [Security boundary](#security-boundary) before blanket-approving shell access.

## Using scaffold

Give it requirements in any of these forms:

```
scaffold these requirements: <paste a paragraph>
scaffold an issue from docs/prd-checkout.md
turn these requirements into an issue
break this spec into tickets
```

It reads a file when you point at one, rather than working from the filename.
It then **reads your codebase before drafting**, so sub-issues name real files and follow patterns that already exist.
In the default mode it shows you a draft and creates nothing until you approve it.
In auto mode it creates the scaffold immediately and reports what it made.

If your requirements are too thin to split sensibly, it will not invent a breakdown.
It asks targeted questions instead, one at a time.
Asking "make the cart better" gets you questions, not five fabricated tickets.

When the scaffold exists, it offers to hand straight off to `execute`, or does so without asking in auto mode.

## Using execute

```
execute TES-5
work on TES-5
work on https://app.asana.com/1/…/task/1217003545553983
run execute on this issue
```

It also handles cleanup on demand.
Tell it a pull request merged, was closed, or was abandoned, and it runs only the sweep.
It confirms the real state with `gh` rather than trusting the claim, and tells you when reality differs from what you said:

```
the PR for TES-5 merged
clean up merged issues
that PR got abandoned
```

A run does this: verifies the tracker MCP, sweeps for merged work, resolves tracker and task memory, fetches the issue, reads relevant code, creates the branch from a freshly fetched base, builds the breakdown and plan document, moves the issue to in progress, then loops one task at a time.
Each task gets claimed, implemented, tested, committed on its own, and closed in both task memory and the tracker.
At the end it pushes, opens the pull request, and moves the issue to in review.

Re-invoking on the same issue resumes it.
Guards see what already exists and skip it.

**When tests cannot pass**, the run stops and holds: the work stays, the task stays open, and you get told what failed.
It does not push broken work or a misleading pull request.

## Approval modes

Two modes, and the difference is only how many questions you get.

**Ask mode**, the default, stops for the issue draft, the handoff, and any genuinely ambiguous choice.

**Auto mode** runs straight through.
It skips the draft approval, the handoff question, ties that the documented precedence can settle on its own, and the two first-run answers that are genuinely determinate: exactly one available destination, or state names that match the three phases exactly.
Everything else is asked even in auto mode.

Auto mode removes friction, not judgment.
**Every safety stop still fires in both modes:**

- An unverified or disabled tracker MCP still refuses and prints setup instructions.
- A test failure that cannot be fixed still stops and holds, with the work kept and nothing pushed.
- A conflict while updating from the base branch still stops, naming the conflicting files.
- A pull request closed without merging still gets reported and asked about.
- A phase with no matching tracker state still asks, rather than mapping review onto something that means something else.
- An ambiguous setup answer still asks that one question, because a wrong destination misfiles every future issue in the repo.
- A reply whose target is unclear, an issue ref that disagrees with the branch, an issue already done, and requirements too thin to break down all still stop and ask.

Set the default during first-run setup, or edit `approval` in `.workbench/config.md`.
Override it per run from the prompt, in either direction:

```
scaffold these requirements, auto approve
work on TES-5, ask me first
```

Every run states which mode it resolved and why, so the mode is never a silent assumption.
When auto mode accepts a setup answer rather than having you confirm it, the profile records that it was auto-accepted, so a wrong value is traceable to the decision rather than looking like a human choice.

## Decision trees

### Which tracker

```
Did the invocation name one?            -> use it
Does .workbench/config.md name one?     -> use it
Is exactly one tracker MCP connected?   -> use it
Are both connected?                     -> ask once, save the answer
Is neither connected?                   -> stop, name both, print setup steps
```

### Which task memory backend, decided per issue

```
Does this issue already have a checklist file?  -> checklist, even if beads is installed
Does the repo have beads state?
    and bd works?                               -> beads
    and bd is missing?                          -> stop and say so, never switch backends
Neither, so a fresh issue?
    bd available?                               -> beads
    bd absent?                                  -> checklist
```

An issue keeps the backend it started with for life.
Adding beads to a repository later only affects issues started afterwards, so a mixed period is normal rather than broken.

### Which base branch

```
Named in the invocation?                        -> use it, this run only
Recorded as base-branch in the profile?         -> use it
Current branch is itself a workbench branch?    -> ask, never stack one issue on another
Otherwise                                       -> the current branch, reported so you see it
```

The base branch is always fetched before branching from it.
Branching from a stale local copy is the usual cause of conflicts at merge time.

### Which approval mode

```
Does the prompt say auto approve, or ask me first?  -> that, this run only
Does .workbench/config.md set approval?             -> that
Otherwise                                           -> ask
```

Whichever resolves, the safety stops above are unaffected.

### What happens to the tracker issue

```
Work starts                     -> in progress
Pull request opened             -> in review
Pull request merged             -> done, by whichever closer you configured
Pull request closed unmerged    -> nothing automatic; you are told and asked what to do
Tests cannot pass               -> stays in progress, run stops and holds
```

## What lands in your repo

| Path | What it is |
| --- | --- |
| `.workbench/config.md` | The committed profile: tracker, destination, state mapping, base branch, closer choice. |
| `.workbench/plans/<ref>.md` | The per-issue plan: issue link, codebase context, approach, tasks, testing strategy. Written for people, never carries status. |
| `.workbench/tasks/<ref>.md` | Task statuses as checkboxes. Only when the checklist backend is active. |
| `.beads/` | Beads task database and its JSONL export, when beads is the backend. |
| `.github/workflows/workbench-close.yml` | Only if you accepted the optional merge-closer Action. |

Plans and task files stay after the pull request merges; they are the record of how the work was broken down.

## How the tracker learns a PR merged

Linear can close issues natively, Asana cannot, so workbench supports several arrangements.
It asks once which one you use and records the answer.

1. **The tracker's own GitHub integration.** Linear closes an issue when a pull request body contains `Closes TES-5`.
   Asana can do the equivalent with its free GitHub App plus a rule that completes a task when its linked pull request merges.
   Nothing from this plugin runs.
   Best option when your organization allows the app.
2. **The optional merge-closer Action.** If you cannot install an integration, the skills offer a small workflow that closes the issue on merge using a repository secret.
   Server-side, no agent needed at merge time.
3. **The sweep.** Whatever you choose, every run checks the repository for issues whose pull requests have since merged and closes anything the first two missed.
   This is the backstop.

You can also just say so, and the skill verifies with `gh` before acting.

A pull request **closed without merging** is never treated as done.
You get told which issue and pull request were abandoned and asked whether to resume or move the issue back, and the observation is recorded so you are not told twice.

## Working conventions

Applied to every run:

- **Staging safety.** Never `git add -A` or `git add .`, and never stage environment files, credential files, or key material.
  Staged paths are checked against the task before committing.
- **Commit messages.** Conventional subjects scoped by the issue ref, for example `feat(TES-5): add celsiusToKelvin with absolute-zero validation`, with the task named in the body.
- **One commit per task.** Even when two tasks touch the same file.
  Before finishing, the run reconciles the number of task commits against tasks closed and stops if they disagree.
- **Commit hashes recorded at close.** A task's close carries the hash of the commit that implemented it, so a task cannot be closed for work that was never committed.
- **A progress line per task**, so a long run stays legible.

## Security boundary

Tracker work happens only through the connected tracker MCP.
When that MCP is missing or disabled, the skills refuse and print setup instructions, naming what is missing.
They are instructed never to read credentials from disk or environment variables, never to call a tracker's HTTP API directly, and never to edit MCP or agent configuration.

**That promise is instructions to a model, not a sandbox.** A model can disregard instructions.
During testing, one run with its tracker MCP disabled tried to edit `mcp.json`, read OAuth token caches, and grep the environment for credentials before attempting a direct API call.
What stopped it was the agent harness's approval prompts and file permissions, not the prose in these skills.

The mitigation that worked was giving the agent something useful to do instead: a preflight check that delivers setup instructions when the MCP is unverified.
After that change, the same scenario produced a clean stop with no bypass attempts.

Configure real enforcement in your harness anyway.
At minimum, require case-by-case approval for:

- Reads of credential stores and token caches, for example `~/.aws`, `~/.kiro/settings`, or OAuth caches.
- `env` and `printenv` style environment dumps.
- Writes to MCP configuration files.
- Outbound `curl` to tracker API hosts.

Both Claude Code and Kiro support rules like these.
Approval prompts are the last line of defense, so do not blanket-approve shell commands during autonomous runs.

In practice this path only triggers when a tracker MCP is missing.
A normal run never reaches it.

## Troubleshooting

**"It says my MCP is not verified but it looks connected."** A disabled server presents exactly like a missing one.
Check for a `disabled` flag on the entry before adding a new server.

**Branch switching fails with beads errors.** Beads runtime files were committed by a previous version.
Ignore rules do not apply to already-tracked files, so untrack them once: `git rm -r --cached .beads` then commit.
`bd init` writes its own `.beads/.gitignore`, so do not duplicate those rules at the repository root.

**Phase transitions show up as comments instead of moving the card.** Your Asana MCP build has no section-move tool.
This is expected and handled, but the V2 server does support real section moves.

**Listing destinations hangs.** On some Asana builds a workspace-wide project listing never returns.
The skills prefer listing per team for this reason; if a call stalls rather than errors, that is the one.

**A merged pull request did not close the issue.** Either no integration is connected, or its secret is missing.
Ask the skill to clean up merged issues and it will close anything outstanding, then fix the arrangement so it happens automatically next time.

**My edits to the plugin are not taking effect.** Marketplace installs copy the plugin into the agent's cache.
See [Developing this plugin](#developing-this-plugin).

## Known limitations

- **Kiro has not been re-verified since the most recent changes.** The skills ran successfully on Kiro earlier in development, and the wiring is unchanged, but the rename, base-branch resolution, and commit-verification work have only been exercised on Claude Code.
  Smoke-test one run before relying on it there.
- **The Linear merge-closer Action template has never been run end to end.** The Asana one has, three times.
  Verify your first merge rather than assuming.
- **The issue type passed to `createIssue` is not stored as a tracker field.** It survives in the issue description and drives the branch prefix, but Linear labels and Asana custom fields are not set from it.
- **Linear suggests its own branch names**, such as `chris/tes-5-slug`, while workbench generates `feat/tes-5-slug`.
  Using Linear's copy-branch-name button will not match.
- **No CI awareness.** Once the pull request is open, a failing CI run is not noticed or reported.
- **Jira is not supported.** Only Asana and Linear.

## Developing this plugin

Installing from a marketplace **copies** the plugin into the agent's cache; it does not live-link your working tree.
Edits do not reach a running agent until you reinstall, and the agent keeps loading the snapshot it installed earlier.
This is easy to miss and will make you think a fix did not work.

Either reinstall after each change:

```
/plugin uninstall workbench
/plugin install workbench@crod951
/reload-plugins
```

Or point the agent at your working tree with the symlinks shown under [Install](#install), which Kiro picks up live.

Before trusting a test run, confirm which copy is live by comparing line counts:

```bash
wc -l ~/.claude/plugins/cache/<marketplace>/workbench/*/skills/execute/SKILL.md \
      plugins/workbench/skills/execute/SKILL.md
```

## Upgrading

Repos set up by an earlier version need four things renamed or added:

1. Rename `.issue-lifecycle/` to `.workbench/`.
2. Rename `.github/workflows/issue-lifecycle-close.yml` to `.github/workflows/workbench-close.yml`, and update the path it greps to `.workbench/`.
3. Change the profile's first line to `# workbench tracker profile`.
4. Add `base-branch` to the profile, or let the next run ask.

If the repo used beads, confirm `.beads/.gitignore` and `.gitattributes` exist, since the beads tooling writes both, and untrack any beads runtime files an earlier version committed.

Version 3 of the predecessor plugin removed its slash commands (`/issue-start`, `/issue-task`, `/commit`, `/issue-finish`).
The `execute` skill covers the issue flow they formed: "execute TES-5" does what the whole sequence used to.
The one gap is `/commit` as a standalone conventional-commit helper outside an issue run; workbench applies its commit conventions only inside execute runs, so for non-issue commits use your agent's normal commit flow, borrowing the rules in `skills/shared/conventions.md` if you want the same style.
