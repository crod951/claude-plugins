# skills

[![SkillSpector](https://github.com/crod951/skills/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crod951/skills/actions/workflows/skillspector.yml)

Personal agent skills for issue-driven development workflow automation, installable as Claude Code plugins or onto any agent via [skills.sh](https://www.skills.sh).
All skills are scanned with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on every change; the build fails on any non-suppressed security finding.

## Installation (30-second setup)

**Claude Code** - run these inside a session for a managed install that updates when this repo ships:

```text
/plugin marketplace add crod951/skills
/plugin install fathom@crod951
/plugin install ship@crod951
```

The two plugins are independent: install either one alone.
Fathom needs a tracker MCP. Ship needs a git repository with a remote.

**Kiro, Codex, and other agents** - use [skills.sh](https://www.skills.sh) for an editable copy on any agent:

```bash
npx skills@latest add crod951/skills
```

The installer lists every skill in `skills/` regardless of which plugin owns it.
Take `ship` or `review` on its own if that is all you want; take `execute`, `scaffold`, and `fathom-shared` together, since `fathom-shared` carries the contract files the other two read.

`review` belongs to no plugin on purpose, so it installs through skills.sh and not through `/plugin install`.

> Individual plugins may have additional prerequisites that run in your **terminal** (e.g., `brew install`). See each plugin's README for details.

## Available Plugins

### fathom (v2.2.0)

Fathom provides two agent skills, execute and scaffold, that carry a tracker issue from requirements to an open code review, on GitHub or any other forge with an adapter.
It works with Asana or Linear as your issue tracker, and both skills run unchanged on Claude Code and Kiro.

#### Prerequisites

- An Asana or Linear MCP plugin installed and authenticated
- [Beads CLI](https://github.com/gastownhall/beads) installed (`bd` command available); optional, but recommended for the richest task memory
- A forge adapter for wherever your reviews live. Two ship built in: GitHub, which needs the [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh` command available), and a generic-git fallback that pushes the branch and hands the review off to you. Write a `.fathom/forge.md` from the bundled template only for a forge Fathom does not ship.

#### Install

```bash
/plugin install fathom@crod951
```

#### Skills

| Skill | Description |
|-------|-------------|
| `execute` | Drives one tracker issue through a single resumable pass: breakdown, implementation, tests, commits, and an open code review. |
| `scaffold` | Turns requirements text into a scaffolded main issue plus linked sub-issues, then offers to hand off to execute. |

Talk to either skill in plain language; there are no slash commands to memorize.

```bash
execute ONC-5
work on <asana task url>
scaffold these requirements
```

#### Features

- **Resumable pass** - execute reads durable state from disk and the tracker on every invocation, never from memory of a previous run
- **Scaffold-to-execute handoff** - scaffold drafts a main issue plus sub-issues, then offers to hand straight into execute
- **Task memory** - beads-backed when available, with a plain checklist file fallback
- **Conventional Commits** - one commit per task, referencing the issue ref
- **Tracker-only access** - tracker work only happens through the connected tracker MCP; when it is missing, the skill refuses and stops
- **Forge-portable** - reviews go through a five-operation forge contract; GitHub and a generic-git fallback ship built in, and any other forge is a `.fathom/forge.md` you write without forking

#### Tracker Status Lifecycle

```text
Todo → In Progress (execute starts) → In Review (review opened) → Done (review merged)
```

See the [full guide](./docs/fathom.md) for setup, task memory, and the security boundary.

---

### ship (v1.1.0)

Ship takes the current branch from working tree to merged release in one pass: review and verification run in parallel with a batched fix loop until both are clean, then commit, push, pull request, automated-review loop, squash-merge, release watch, and post-merge cleanup.
Everything from the pull request onward needs an installed and authenticated GitHub CLI; without one, ship stops after pushing the branch and printing the compare URL, and the review, merge, and release are yours to drive.

#### Prerequisites

- A git repository with a remote
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh`) for the pull request, merge, and check-polling stages; without it ship pushes the branch, prints the compare URL, and hands the review off to you

#### Install

```bash
/plugin install ship@crod951
```

#### Skills

| Skill | Description |
|-------|-------------|
| `ship` | Resolves the project's own verification pipeline, then drives the branch through review, CI, pull request, merge, release, and cleanup without stopping between stages. |

```bash
ship
ship it
```

#### Features

- **Project-resolved pipeline** - the verify command comes from `.ship/config.md`, then the project's docs, then a declared aggregate task, then the pull-request CI job, then a composed fallback; the first tier that answers wins
- **Asks once, remembers** - when detection is ambiguous ship asks a single question before touching the tree, then records the answer in `.ship/config.md` and commits it on its own, so the decision reaches the next branch, clone, and teammate; the commit keeps it separable from the change it rode in with, and it is still reviewed and merged as part of the pull request
- **No config for free answers** - a pipeline detection resolved on its own gets no file, because a file that restates what is already discoverable only goes stale; `.ship/config.md` exists to preserve a human decision
- **Parallel gates** - review and verification diagnose the same HEAD concurrently, with fixes batched between rounds so neither gate ever reads a stale tree
- **Exit only on an untouched round** - the last round has to pass both gates with no fixes applied, so a green result always describes the code that actually merges
- **A blocking bar, not a nit hunt** - stage 1 fixes verify failures and confirmed critical or major findings, records the disposition of everything else into the pull request body, and terminates; fixing every nit hands the next round fresh code to find fault with, which is how a review loop never converges
- **Two reviewers, not one twice** - the pre-push review is a Code Reviewer subagent reading this run's intent, and the pull-request bot is the final bar that still has to settle green; ship never shells out to a review CLI, because the vendors that ship one also run the bot and the CLI would spend that quota on a judgment the bot reaches anyway
- **Project-local override** - a repository that ships its own `.claude/skills/ship/SKILL.md` takes precedence, carrying its specialized pipeline

---

## Standalone Skills

Skills here that no plugin claims. They install through [skills.sh](https://www.skills.sh) (`npx skills@latest add crod951/skills`) rather than `/plugin install`.

### review (v1.0.0)

Review verifies a pull request against the tracker issue it claims to close, on a build it actually runs, and posts one review with line-specific findings anchored inline and general findings in the summary body.

Its premise is that a diff review cannot see the things worth catching. The findings it was built from were a border removal that read as correct in light mode and gutted the card edge in dark, two halves of one panel whose content sat 388px apart at wide viewports, a dropdown that `toBeVisible()` reported as visible while it was clipped, and an animation that un-clipped a zero-height node one frame before unmount. So it builds the branch and its merge-base side by side, measures both, and reports the difference.

#### Prerequisites

- A git repository with a remote
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh`) for reading pull request metadata and posting the review
- A browser driver for the visual stages, such as Playwright or a browser MCP; a purely behavioural pull request needs neither

#### Install

```bash
npx skills@latest add crod951/skills
```

#### Skills

| Skill | Description |
|-------|-------------|
| `review` | Builds the pull request and its merge-base, measures both, proves the new tests are load-bearing, then posts one review with severity-marked findings. |

```bash
review this PR
review #107
```

#### Features

- **Never concludes from the diff** - the branch and its merge-base are built and served side by side, so every claim comes from a running app rather than from reading a change
- **A/B before blame** - a finding measured on the base build too is reported as pre-existing, which is the difference between telling an author they broke something and telling them they inherited it
- **Pixels over computed styles** - for any claim that something is or is not visible, the screenshot is decoded and the painted colours compared; `border: 0` plus a 1.1:1 background step reads as conclusive and is routinely wrong
- **Tests the tests** - reverts the changed source to confirm the new assertions fail without it, then adversarially checks the ones that pass either way by making the exact change they claim to catch
- **Fails closed on a moved head** - the fetched ref is verified against the pull request's reported head before anything is measured, so a re-review never silently describes yesterday's commit
- **Severity that means something** - 🔴 is reserved for a regression the pull request introduces with a cheap fix, and findings are deduped to root causes first, so a good pull request does not read as riddled with defects
- **Costs what it should** - both builds stay warm, every measurement batches through one browser session, and the gates come from CI rather than being re-derived locally

---

## Workflow

1. **Scaffold requirements**: talk to the scaffold skill, for example "scaffold these requirements"
2. **Execute the issue**: talk to the execute skill, for example "execute ONC-5"
3. **Resume if interrupted**: re-invoke execute on the same issue; it picks up where the last run left off
4. **Review the pull request**: talk to the review skill, for example "review #107", to verify it against its issue on a running build
5. **Ship the branch**: talk to the ship skill, for example "ship it", to carry the reviewed branch through merge and release

## Repository Layout

Every skill lives in a flat `skills/<name>/` directory, and `.claude-plugin/marketplace.json` decides which plugin owns which skill through a per-entry `skills` array.
A skill claimed by no entry, such as `review`, is still published by skills.sh and is simply unreachable through `/plugin install`; `bin/sync-versions.sh` reports it so the omission stays deliberate rather than accidental.
Both plugins therefore share one marketplace root (`source: "./"`), and there is deliberately no `.claude-plugin/plugin.json`: with that source a single root manifest would apply to every entry and its version would silently win over each entry's own.
`bin/sync-versions.sh` syncs the versions into this README and fails when a skill directory is claimed by no plugin, by more than one, or is claimed but missing.

## Security Scanning

Every skill in `skills/` is scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) in CI, and the build fails on any non-suppressed finding.
Run the same scan locally before committing:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git
bin/scan-skills.sh            # all skills; or name specific ones: bin/scan-skills.sh execute
```

When a finding is a reviewed false positive, suppress it in the repo-root `.skillspector-baseline.yaml` with a written reason; never suppress a finding you have not understood.

## License

MIT
