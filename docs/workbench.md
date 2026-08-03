# Workbench

Workbench is a pair of agent skills that carry a tracker issue from requirements to an open code review.

- **scaffold** turns requirements into a tracker issue plus linked sub-issues.
- **execute** drives an existing issue through implementation to a code review, one task at a time.

It works with **Asana** or **Linear**, and runs unchanged on **Claude Code** and **Kiro** because both follow the open Agent Skills standard.

> Built for frontier-model agents.
> There is no small-model mode.

## Contents

- [What you get](#what-you-get)
- [Install (30-second setup)](#install-30-second-setup)
- [Setup, step by step](#setup-step-by-step)
- [Using scaffold](#using-scaffold)
- [Using execute](#using-execute)
- [Approval modes](#approval-modes)
- [Decision trees](#decision-trees)
- [What lands in your repo](#what-lands-in-your-repo)
- [Forges](#forges)
- [How the tracker learns a review merged](#how-the-tracker-learns-a-review-merged)
- [Working conventions](#working-conventions)
- [Security boundary](#security-boundary)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Developing this plugin](#developing-this-plugin)
- [Upgrading](#upgrading)

## What you get

A run of the two skills back to back produces: a tracker issue with sub-issues, a feature branch, a plan document a reviewer can read before any code exists, one commit per unit of work, a code review whose body links the issue and lists what was verified, and the issue sitting in review.

The design goal is that **nothing is remembered between invocations**.
Every run reads state from your repository and your tracker, so an interrupted run resumes by being re-invoked, in either agent.

Resuming on a *different* machine works for whatever was committed and pushed.
The checklist backend travels with each task commit; beads keeps its database out of git by design and shares only its export, so a beads run commits that export alongside each task for the same reason.

**Requirements:** an Asana or Linear MCP connected in your agent, and optionally the beads CLI (`bd`) for richer task memory.
On GitHub, the GitHub CLI (`gh`) authenticated. On another forge, an adapter — see [Forges](#forges); without one, runs still work and hand the review off to you.

## Install (30-second setup)

Two ways in, two philosophies.
**The Claude Code plugin** installs the pair as a managed, read-only bundle that updates when this repo ships - you subscribe rather than fork.
**[skills.sh](https://www.skills.sh)** copies editable skill files onto your machine for any agent, so you can hack on them and make them your own.
Pick one - installing both leaves you with every skill twice.

### 1. Get the skills

<details>
<summary><strong>Claude Code</strong></summary>

Run these inside a Claude Code session:

```text
/plugin marketplace add crod951/skills
/plugin install workbench@crod951
/reload-plugins
```

Confirm both skills loaded by asking for the skill list; you should see `workbench:execute` and `workbench:scaffold`.

</details>

<details>
<summary><strong>Kiro, Codex, and other agents</strong></summary>

```bash
npx skills@latest add crod951/skills
```

Pick which coding agents to install onto - the installer auto-detects what you have.
**Take all three entries when it asks which skills you want: `workbench-shared` carries the contract files the other two read, and an install without it stops at the first step.**

Kiro's default agent auto-loads everything under `~/.kiro/skills/`, so no further configuration is needed there.
Other agents may need the skill added to their config after install; see that agent's page on [skills.sh](https://www.skills.sh).

</details>

<details>
<summary><strong>For tinkerers</strong></summary>

The same installer works on any agent - including Claude Code - and writes the skills as ordinary files you own and can edit.
Nothing updates behind your back; pull the latest changes when you want them with `npx skills update`.

Installing fully by hand also works; keep `execute/`, `scaffold/`, and `workbench-shared/` as siblings at the destination's top level:

```bash
# global install, available in every workspace
cp -r skills/. ~/.kiro/skills/

# or symlink while iterating, so edits take effect immediately
ln -s "$PWD/skills/execute"          ~/.kiro/skills/execute
ln -s "$PWD/skills/scaffold"         ~/.kiro/skills/scaffold
ln -s "$PWD/skills/workbench-shared" ~/.kiro/skills/workbench-shared
```

</details>

### 2. Run either skill once per repo

The first run asks the [setup questions](#setup-step-by-step) - tracker, destination, state mapping, base branch, approval mode - and commits the answers to `.workbench/config.md`, so teammates are never asked again.

### 3. Bam - you're ready to go.

## Setup, step by step

### 1. Connect your tracker's MCP

Asana or Linear, whichever you use.
In Claude Code install and authenticate the matching MCP plugin; in Kiro add the server to `mcp.json`.

Tool names are discovered at runtime, so any recent build works.
If a server exists but is disabled, that counts as missing: the skills refuse to run rather than guess.

For Asana specifically, prefer the **V2** server (`https://mcp.asana.com/v2/mcp`).
The V1 beta server is deprecated and, in testing, exposed no tool for moving a task between board sections, which downgrades phase transitions to comments.

### 2. Set up your forge

On GitHub, authenticate the CLI:

```bash
brew install gh
gh auth login
```

Preflight verifies the forge on every run alongside the tracker MCP.
Unlike the tracker, an unverified forge does not stop the run — it selects a tier, and the run says which one it picked. See [Forges](#forges) for what each tier does and how to support a forge that is not GitHub.

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
| Which forge? | Where your reviews live. Seeded from your `origin` remote, then from CLIs on your `PATH`. See [Forges](#forges). |
| How should the tracker learn a review merged? | Asana and Linear differ; skipped entirely when your forge has no CI hooks. See [How the tracker learns a review merged](#how-the-tracker-learns-a-review-merged). |
| Which base branch? | Feature branches start from it and reviews target it. Defaults to your current branch, unless that is itself a workbench branch. |
| Stop for approval, or run straight through? | Sets the default approval mode for future runs. See [Approval modes](#approval-modes). |

If your tracker has no state for a phase, which is common for review states in a fresh Linear team, the skill says so and offers real choices rather than silently picking the nearest state.

### 5. Pre-approve the commands

Autonomous runs stall on permission prompts.
Pre-approve `git`, `bd`, your forge's CLI (`gh` on GitHub), and your tracker MCP's tools: in Claude Code through the permissions allowlist, in Kiro through trusted commands.

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
Tell it a review merged, was closed, or was abandoned, and it runs only the sweep.
It confirms the real state through the forge rather than trusting the claim, and tells you when reality differs from what you said:

```text
the PR for TES-5 merged
clean up merged issues
that PR got abandoned
```

A run does this: verifies the tracker MCP, sweeps for merged work, resolves tracker and task memory, fetches the issue, reads relevant code, creates the branch from a freshly fetched base, builds the breakdown and plan document, moves the issue to in progress, then loops one task at a time.
Each task gets claimed, implemented, tested, committed on its own, and closed in both task memory and the tracker.
At the end it pushes, opens the review, and moves the issue to in review.

Re-invoking on the same issue resumes it.
Guards see what already exists and skip it.

**When tests cannot pass**, the run stops and holds: the work stays, the task stays open, and you get told what failed.
It does not push broken work or open a misleading review.

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
- A review closed without merging still gets reported and asked about.
- Accepting a forge CLI found on your `PATH` still asks; auto mode never drives an unfamiliar CLI unattended.
- A phase with no matching tracker state still asks, rather than mapping review onto something that means something else.
- An ambiguous setup answer still asks that one question, because a wrong destination misfiles every future issue in the repo.
- A reply whose target is unclear, an issue ref that disagrees with the branch, an issue already done, and requirements too thin to break down all still stop and ask.

Set the default during first-run setup, or edit `approval` in `.workbench/config.md`.
Override it per run from the prompt, in either direction:

```text
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
Work starts               -> in progress
Review opened             -> in review
Review merged             -> done, by whichever closer you configured
Review closed unmerged    -> nothing automatic; you are told once and asked what to do
Tests cannot pass         -> stays in progress, run stops and holds
```

In the manual tier the "review merged" line never fires, because nothing can observe the review. The run tells you that at handoff.

## What lands in your repo

| Path | What it is |
| --- | --- |
| `.workbench/config.md` | The committed profile: tracker, forge, destination, state mapping, base branch, closer choice. |
| `.workbench/forge.md` | Only if you wrote an adapter for a forge workbench does not ship. See [Forges](#forges). |
| `.workbench/plans/<ref>.md` | The per-issue plan: issue link, codebase context, approach, tasks, testing strategy. Written for people, never carries status. |
| `.workbench/tasks/<ref>.md` | Task statuses as checkboxes. Only when the checklist backend is active. |
| `.beads/` | Beads task database and its JSONL export, when beads is the backend. |
| `.github/workflows/workbench-close.yml` | Only if you accepted the optional merge-closer Action. GitHub only; never offered on a forge without CI hooks. |

Plans and task files stay after the review merges; they are the record of how the work was broken down.

## Forges

The forge is where your reviews live: the system that receives the branch and holds the code review. It is resolved separately from the tracker, and GitHub is one option rather than an assumption.

Workbench drives the forge through five operations — verify, resolve base, open review, publish review, read review state — and each adapter declares what its forge can actually do. Capabilities differ in kind, not just in command names, so an adapter that declares no CI hooks simply never gets offered a workflow file.

### The three tiers

Every run lands in one tier and says which:

| Tier | When | What you get |
| --- | --- | --- |
| **Adapter** | An adapter resolved and verified | Everything. Reviews opened automatically, issues closed on merge by the sweep. |
| **Assisted** | No adapter, but a forge CLI is on your `PATH` | The branch is pushed, then you are asked whether to use that CLI once, write an adapter, or hand off manually. Never used unattended. |
| **Manual** | No adapter and no candidate, or you pinned `forge: none` | The branch is pushed and you get the branch, base, title, and body to open the review yourself. The sweep does not run. |

The manual tier has one consequence worth knowing up front: **nothing can observe the review, so no later run will move the issue to done.** Issues accumulate in review until you close them. The run says this at handoff rather than leaving you to discover it.

### Supporting a forge workbench does not ship

Internal and self-hosted forges are the reason the contract exists. Workbench cannot ship an adapter for a forge whose name and CLI it has never seen — but you can write one.

Copy `skills/workbench-shared/forges/TEMPLATE.md` to `.workbench/forge.md` in your repository, fill in the five operations against your forge's CLI, declare the capability table, and commit it. A repo-local adapter beats every bundled one, so nothing else changes and this plugin never needs forking. Your teammates who clone the repo get it automatically.

A partial adapter is fine and often correct. One that opens reviews but declares `reviewLookup: none` still does the useful part; it just leaves the sweep off. That is far better than an adapter that guesses at review state, because a wrong guess marks abandoned work as shipped.

Two rules the skills hold to, no matter the tier: **anything executed against a forge comes from a written adapter file, never from an inference made in the moment**, and credentials are never scavenged from disk, environment, or token caches.

## How the tracker learns a review merged

Linear can close issues natively, Asana cannot, so workbench supports several arrangements.
It asks once which one you use and records the answer — unless your forge declares no CI hooks, in which case the question is skipped and the sweep is the only mechanism.

1. **The tracker's own forge integration.** On GitHub, Linear closes an issue when a review body contains `Closes TES-5`.
   Asana can do the equivalent with its free GitHub App plus a rule that completes a task when its linked pull request merges.
   Nothing from this plugin runs.
   Best option when your organization allows the app.
2. **The optional merge-closer Action.** If you cannot install an integration, the skills offer a small GitHub Actions workflow that closes the issue on merge using a repository secret.
   Server-side, no agent needed at merge time.
   Offered only on a forge with CI hooks; on any other, accepting it would write a file that never runs.
3. **The sweep.** Whatever you choose, every run looks up each recorded review by id and closes anything the first two missed.
   This is the backstop, and it is unavailable in the manual tier.

You can also just say so, and the skill confirms the real state through the forge before acting.

A review **closed without merging** is never treated as done.
You get told which issue and review were abandoned and asked whether to resume or move the issue back. The observation is recorded as a comment on the tracker issue, so you are told once rather than on every run — and because it lives on the tracker, it works even when your base branch is protected.

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

**A merged review did not close the issue.** Either no integration is connected, or its secret is missing.
Ask the skill to clean up merged issues and it will close anything outstanding, then fix the arrangement so it happens automatically next time.
In the manual tier this is expected rather than a fault: nothing can observe the review, so closing is yours to do.

**The same abandoned review is reported on every run.** This was a real defect in earlier versions, where the marker was pushed to the base branch and any branch protection made the push fail silently.
The marker is now a comment on the tracker issue, so it needs no branch write access.
If you still see repeats, your tracker's MCP may expose no way to list comments, which falls back to the old file-based marker; the run says so when it takes that path.

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
- **No CI awareness.** Once the review is open, a failing CI run is not noticed or reported.
- **Forges other than GitHub need an adapter you write.** Workbench ships GitHub and a generic-git fallback; anything else is a `.workbench/forge.md` you author. See [Forges](#forges).
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
      skills/execute/SKILL.md
```

## Upgrading

Repos set up by an earlier version need four things renamed or added:

1. Rename `.issue-lifecycle/` to `.workbench/`.
2. Rename `.github/workflows/issue-lifecycle-close.yml` to `.github/workflows/workbench-close.yml`, and update the path it greps to `.workbench/`.
3. Change the profile's first line to `# workbench tracker profile`.
4. Add `base-branch` to the profile, or let the next run ask.

Repos set up before forge support need nothing. The next run asks which forge you use and adds `forge` to the profile, exactly as it repairs any other missing field. Existing `.workbench/` records that carry a branch and no review id keep working — the sweep falls back to matching by branch and rewrites the record with an id when it finds one.

If the repo used beads, confirm `.beads/.gitignore` and `.gitattributes` exist, since the beads tooling writes both, and untrack any beads runtime files an earlier version committed.

Version 3 of the predecessor plugin removed its slash commands (`/issue-start`, `/issue-task`, `/commit`, `/issue-finish`).
The `execute` skill covers the issue flow they formed: "execute TES-5" does what the whole sequence used to.
The one gap is `/commit` as a standalone conventional-commit helper outside an issue run; workbench applies its commit conventions only inside execute runs, so for non-issue commits use your agent's normal commit flow, borrowing the rules in `skills/workbench-shared/conventions.md` if you want the same style.
