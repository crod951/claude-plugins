---
name: review
description: This skill should be used when the user asks to "review this PR", "review #107", "review these PRs the same way", "do a visual pass on this branch", "verify this against the issue", pastes a pull request URL to review, or asks for a UI change to be checked before merge. Also use when the user asks whether a reviewed PR is safe to merge, or asks to escalate or downgrade a finding's severity. Verifies a pull request against the tracker issue it claims to close, on a running build, with measured evidence, then posts one review with line-specific findings inline and general findings in the summary body.
version: 1.0.0
---

# Review

Verify that a pull request does what its issue asked, on a build you are actually running, and report it as one review that a reader can act on without re-deriving anything.

## Precedence

User instructions beat this skill. This skill beats your defaults.

If the user asks for a lighter pass ("just read the diff", "quick look"), give them that and say which stages you skipped. Do not silently downgrade a full review into a diff read.

## The one rule that makes this different

**Never conclude from the diff alone. Build the branch, run it, and measure.**

Every finding in this skill's corpus that mattered was invisible in the diff:

- a border removal that read as correct in light mode and erased the card's edge in dark mode
- two halves of one panel whose contents were 395px apart at wide viewports
- a dropdown that `toBeVisible()` reported as visible while it was clipped
- an animation that un-clipped a zero-height node one frame before unmount

A diff review finds none of these. A running build finds all four.

## Cost discipline

A two-file UI PR should take about five minutes. If you are past ten, you are almost certainly rebuilding when you should be re-measuring.

The cost is never the measuring. It is the number of build → serve → launch-browser cycles you pay for. Measured on a real run: 53 tool calls, 15 minutes, and roughly thirty of those cycles — to read values that fit in one page session.

**Build once per side. Serve both. Keep them warm.**

Bring up one preview for the PR and one for base, on two verified-free ports, and leave them running for the whole review. Rebuild **only** after you change source on disk (stage 8), and re-assert build identity when you do.

**One browser session, one measurement script.**

Every viewport, both themes, all geometry, contrast and hit-testing go through a single pass that returns one structured object. Do not write throwaway spec files to read a handful of values — each one is a whole build-and-serve cycle for a few numbers. Drive the page directly.

**Take the gates from CI.**

```bash
gh pr view <n> --json statusCheckRollup   # ~1 second
```

If CI already ran lint, typecheck, unit and e2e, that is your gate result — report it as such. Locally, run only what CI cannot give you:

- the specific specs needed for the load-bearing proof (stage 8)
- anything you must run to measure

Re-running a full suite locally to confirm a green CI check buys nothing and costs minutes.

**These are opt-in, not per-PR requirements.** Do them when something specific prompts it, and say why:

- trial-merging a moved base branch
- flakiness sweeps (`--repeat-each`)
- full-suite runs beyond the touched specs
- cross-browser checks when the config defines one project

Thoroughness that nobody asked for is still cost. Spend it on the surfaces the PR touched.

## Stages

Work them in order. Later stages depend on earlier ones.

### 1. Establish what the PR claims

Pull the metadata and the issue(s) it closes before reading any code.

```bash
gh pr view <n> --json number,title,author,headRefName,baseRefName,state,additions,deletions,changedFiles,body
gh pr diff <n> --name-only
```

Read the PR body against the tracker issue. You are going to produce a scope-vs-landed table, so capture:

- what each issue actually asked for, in the issue's own terms
- what the author says they did, and what they say they deliberately did **not** do
- anything the author flagged as a known open item (do not re-raise these as new findings)

**Read prior reviews on OTHER pull requests** — two or three — to match the house voice and severity conventions.

**If the PR under review already has a review, do not read it yet.** It is an answer key, and reading it first replaces your judgement with someone else's while leaving you convinced you agreed independently. Note that it exists, finish every measurement, draft your own findings, and *then* read it and reconcile: drop what is already communicated, keep what you found that it missed, and where you disagree, say so and go with your own measurement. Never quote its numbers as yours.

### 2. Get two isolated builds

Never review in the user's working tree. It has their uncommitted work in it.

**One PR needs two worktrees, not one:** the PR head, and the merge-base. You need the base one for stage 7's A/B and for the before half of every screenshot pair — and stage 8 destroys and rebuilds the PR worktree, so a single worktree cannot serve as your baseline.

```bash
git fetch origin "refs/pull/<n>/head:pr-<n>"
git worktree add /path/to/scratch/wt-<n> pr-<n>
ln -s "$(git rev-parse --show-toplevel)/node_modules" /path/to/scratch/wt-<n>/node_modules
cp "$(git rev-parse --show-toplevel)"/.env* /path/to/scratch/wt-<n>/
```

Do the same for the merge-base (`git worktree add ... "$(git merge-base origin/<base> pr-<n>)"`), and give each its own port.

Symlinking `node_modules` is usually safe and saves an install. Copy env files, or the build silently produces a broken app whose every test fails for reasons unrelated to the PR.

### 3. Take the gates

Typecheck, lint, unit, e2e. Report what you got, not what the PR body claims — and **reconcile the two**. Checking the author's own arithmetic is nearly free and tells you how carefully the rest of the description was written; a test count that is off by one is worth a parenthesis, not a finding.

Read them off CI first (`gh pr view <n> --json statusCheckRollup`). Run locally only what CI cannot answer — see Cost discipline. If CI is red, or there is no CI, run them yourself.

### 4. Serve the build — and verify the build's identity

**This is where reviews go wrong most often.** Two traps, both of which produce confident, completely wrong conclusions:

**Trap 1 — port hijack.** Test configs commonly hardcode a port with `reuseExistingServer: !process.env.CI`. Any unrelated dev server already on that port gets tested instead of the PR. Symptom: every test fails, including ones that cannot possibly relate to the change ("home page renders").

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN   # who is actually there?
```

Fix by serving on a port you verified is free, with an override config and `reuseExistingServer: false` plus `--strictPort`. Never assume 5173 is yours.

**Trap 2 — stale `dist/`.** Anything that rebuilds (notably stage 8, which reverts source to prove tests fail) leaves the build output from the *wrong* source. Restarting a preview server does not rebuild.

**After every rebuild, and before believing any screenshot, assert the served build's identity** by checking a computed value only the PR could produce:

```js
// in the page: does the served CSS actually contain this PR's change?
getComputedStyle(document.querySelector('.qb-tab-wrap')).backgroundColor  // PR: card colour, base: transparent
getComputedStyle(document.querySelector('.drug-browse__category-name')).fontSize  // PR: 12px, base: 14px
```

If the answer is the base value, you are looking at the wrong build. Rebuild, then re-verify.

### 5. Visual pass at real breakpoints, in both themes

Narrow (390), standard (1440), and at least one wide (1600, 2200+). Wide viewports expose measure and alignment bugs that never appear at 1440.

Then switch themes and do it again. Dark mode is not a skin — it inverts the logic of elevation:

- a shadow tuned for a light page contributes far less on a dark one
- a borderless card's edge may come down to a background step of ~1.1:1
- a change justified by light-mode parity can gut an edge in dark

Do not turn those into conclusions from the stylesheet alone — measure the painted result (see below). "The shadow contributes nothing" is the kind of claim that is usually *nearly* true and wrong in the detail.

### 6. Measure, do not eyeball

Eyeballing produces "looks a bit off". Measuring produces a finding the author can act on. Read geometry, computed styles, and contrast directly from the running page.

Collect everything in **one** pass over the already-running preview — all viewports, both themes, every element — returning a single structured object. One session, not one per question.

```js
() => {
  const lum = (rgb) => {
    const [r, g, b] = rgb.map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
  const parse = (s) => s.match(/\d+(\.\d+)?/g).slice(0, 3).map(Number)
  // Contrast against the surface the text ACTUALLY sits on — never against a token name,
  // and never by comparing lightness, which inverts between themes.
  const ratio = (fg, bg) => {
    const [hi, lo] = [lum(parse(fg)), lum(parse(bg))].sort((a, b) => b - a)
    return +((hi + 0.05) / (lo + 0.05)).toFixed(2)
  }
  const el = document.querySelector(SELECTOR)
  const r = el.getBoundingClientRect()
  const c = getComputedStyle(el)
  return {
    box: { x: +r.x.toFixed(1), right: +r.right.toFixed(1), y: +r.y.toFixed(1), bottom: +r.bottom.toFixed(1) },
    type: { px: c.fontSize, weight: c.fontWeight, tracking: c.letterSpacing, transform: c.textTransform },
    surface: { bg: c.backgroundColor, radius: c.borderRadius, shadow: c.boxShadow, border: c.borderTopWidth },
    contrast: ratio(c.color, getComputedStyle(el.closest(CARD_SELECTOR)).backgroundColor),
  }
}
```

Four measurement techniques worth reaching for by name:

**Never conclude from computed styles alone that something is or is not visible.** This is the sibling of the one rule, and it fails the same way. `getComputedStyle` reporting `border: 0px` and a 1.095:1 background step reads as an open-and-shut "no edge left" — but a box-shadow still paints a halo the computed value cannot show you, and a neighbouring element's border may be delineating the edge coincidentally. Sample the rendered pixels: screenshot the region, read it back through a canvas, and compare the actual colours either side of the boundary.

```js
// contrast across a boundary, from painted pixels rather than from the stylesheet
const img = await loadScreenshotCrop(box)         // the region spanning the edge
const ctx = Object.assign(document.createElement('canvas'), { width: img.width, height: img.height }).getContext('2d')
ctx.drawImage(img, 0, 0)
const rowAt = (y) => ctx.getImageData(0, y, img.width, 1).data
// walk rows across the boundary, keep the strongest step you find
```

For any claim of the form "you can/cannot see X", this is the evidence. Computed styles tell you what was *asked for*; pixels tell you what *landed*. Reporting an overstated blocker because a shadow was assumed dead is a worse error than missing it.

**Hit-testing beats bounding boxes.** `toBeVisible()` and a bounding-box comparison both pass on clipped content, because an out-of-flow child keeps its geometry while being painted nowhere. `document.elementFromPoint(x, y)` tells you what is *actually painted and clickable* there:

```js
const hit = document.elementFromPoint(x, barBottom + 20)
;({ hit: hit.className, insideDropdown: dropdown.contains(hit) })
```

Use it for clipping, overlap, sticky corners, and anything z-index shaped.

**Trace animation state rather than watching it.** A `MutationObserver` on the `style` attribute gives you a frame-by-frame log, which catches ordering bugs no screenshot can:

```js
new MutationObserver(() => log.push({
  t: Math.round(performance.now()), overflow: el.style.overflow,
  height: el.style.height, opacity: el.style.opacity, connected: el.isConnected,
})).observe(el, { attributes: true, attributeFilter: ['style'] })
```

**Scroll and measure are separate calls.** `scrollIntoView` and smooth scrolling have not settled when the same function reads `getBoundingClientRect()`. Scroll in one call, measure in the next, or every coordinate is stale. Use `behavior: 'instant'`.

### 7. A/B against the base build

**A finding is only this PR's problem if the base build does not have it.** Serve base and PR side by side on separate ports and compare the same measurement.

This is what separates "you introduced this" from "this predates you", and it changes severity, tone, and whether the author owes anything. In the corpus it demoted two findings to "pre-existing, newly visible" and confirmed one as a genuine regression. It also proves the bug the PR claims to fix was real: measure the broken state on base before crediting the fix.

### 8. Prove the new tests are load-bearing

A test that passes with and without the change pins nothing. Revert the changed source, re-run the new tests, and confirm they fail.

```bash
git checkout "$(git merge-base origin/<base> pr-<n>)" -- <changed files>
# re-run the new specs → expect failures
git checkout pr-<n> -- <changed files>   # restore, then REBUILD and re-assert identity
```

Both `git checkout` calls stage into the **worktree's own index**, which is separate from the main clone's — safe, and worth knowing before you run it under a "don't stage anything" constraint.

Expect a mix: the tests that fail are load-bearing, and the ones that pass either way should be the ones the author says pin unchanged behaviour. If *everything* passes, the tests are decorative — say so.

**Then adversarially test the tests that passed either way.** "Passes with and without the change" is not the same as "pins the behaviour it claims to". Take a test's stated guarantee, make the exact change it says it prevents, and confirm it fails.

A real example: a test commented as guarding that a subcategory "stays distinguishable from its parent" asserted a three-way disjunction — `size !== || weight !== || color !==` — so it only rejected total identity on all three axes. Setting the subcategory to the parent's exact size *and* weight, leaving one colour step, still passed. The test pinned nothing, and no amount of revert-and-rerun would have revealed it.

Look hardest at assertions that are disjunctions, `toBeGreaterThanOrEqual` where the interesting case is strict, and equality between two things that are structurally equal anyway (two full-bleed siblings will always share edges, whatever the design intends).

**Re-assert build identity after every state transition, restore included.** Rebuilding is not proof; you can rebuild and still be serving the wrong CSS. The cheapest decisive probe is the built asset hash — it should flip away on revert and flip *back* on restore. If it doesn't, stop and find out why before trusting another measurement.

### 9. Dedupe to root causes

**Markers are not findings.** One root cause stated in a scope-table row, a summary note, and an inline comment is **one** finding with three markers. Collapse them and count the distinct problems before you report anything.

Get this wrong and a good PR reads as riddled with defects, the author cannot tell what to fix first, and the reviewer looks like they padded. This is the single easiest way to make an otherwise accurate review useless. Do it before assigning any severity.

### 9b. Assign severity

For each distinct finding ask, in order:

1. Does the base build have it too? → pre-existing, say so explicitly
2. Is it perceptible to a user? → if it needs a hit-test to detect, it is cosmetic
3. Did the author already file or defer it with the requester's agreement? → do not re-raise
4. Is it a regression **this PR introduces**, and is the fix cheap? → blocking

| Marker | Meaning | Use for |
|---|---|---|
| 🟢 | pass | verified working, and good calls worth naming |
| 🟡 | nitpick, non-blocking | everything that is not a regression this PR introduces |
| 🔴 | blocking | a regression this PR introduces, on a surface that matters, with a cheap fix |

🔴 is rare and should stay rare. Across the corpus's first five reviews it was never used once. Reserve it, and when you do use it, say why it is blocking and hand over the fix.

**The partial case, which question 1 does not resolve:** the PR moves an element onto an existing pattern, and the pattern itself carries the flaw. The element regressed; the codebase did not. Call it 🔴 when the fix also corrects the pattern and the author's instruction is still satisfied — then propose the systemic fix, not a special case for this element. Call it 🟡 when fixing the pattern is a separate project. Either way, **say that the pattern predates the PR**: it changes whether the author is being told they broke something or told they inherited it, and they can argue the severity back with that fact in hand.

Write "non-blocking" in words next to 🟡, not just the emoji. And when a marker you already published turns out to be wrong, say so plainly and re-publish — an under-called regression is worse than an inconsistent history.

### 10. Build the evidence

**If the PR changes anything visual, screenshots are REQUIRED, and every changed surface gets a before/after pair.** Not an after-only shot, and not prose describing what changed. A reader who never checks out the branch has to be able to see the change and judge it.

- **before** = the same surface on the **base** build, at the same viewport and theme
- **after** = the PR build
- one pair per visual surface the PR touches, presented as a two-column table

You already have both builds serving from stage 7, so the before shot costs one navigation. Capture the pair while both are warm — going back for a missing before means rebuilding.

Additional standalone shots are for findings: one annotated capture per finding that has a visual component.

**Annotate everything that supports a finding.** A raw capture asks the reader to find the problem; an annotated one states it. Inject overlays into the page before capturing — guide lines at the two edges that should agree, a labelled band spanning the gap, dashed outlines carrying the measured value in the label. The measurement and the picture should say the same thing.

Then get them hosted. **The GitHub API has no image-upload endpoint** — images must already be hosted. Do not commit screenshots to the repo. Use the browser:

1. open any PR comment box, `find` the "Add files" input, upload every image in one call
2. wait, then read `textarea[name="comment[body]"]` — GitHub has rewritten it into `<img src="https://github.com/user-attachments/assets/...">`; harvest those URLs
3. clear the textarea via the native value setter plus an `input` event, so no draft is left staged
4. post the real comments with `gh api`, embedding the harvested URLs

`curl` on those URLs returns 404 on a private repo even when they are fine. Verify by loading the posted comment in the authenticated browser and checking `img.naturalWidth > 0`.

### 11. Post one review

One review per PR, carrying both halves:

- **line-specific findings → inline comments**, anchored to the exact line. An inline comment points at its subject, so it needs no locating prose.
- **general findings → the review summary body.** Keeping them in the same review lets the summary cross-reference the inline notes ("see note 2") and keeps one timeline entry per PR.

Never inline a general finding just because a plausible line exists. Anchor lines must be part of the diff, so confirm the line is inside a hunk:

```bash
git diff -U0 "$BASE..pr-<n>" -- <file> | grep -E '^(\+\+\+|@@)'
```

Default the event to `COMMENT`. Approve only when the user asks.

Summary body shape:

1. `## Review: verified against <ISSUE-IDs>`
2. one sentence on what you read, what you ran it on, which viewports and themes, and the base branch
3. if anything is 🔴, say so in the second line — never make the reader hunt for it
4. `### What the issue asked for vs what landed` — a table per issue, `| scope | Status |`, every row carrying a marker
5. `### Gates` — marker per gate, plus whether the new tests are load-bearing
6. `### Before / after` — REQUIRED for any visual change: a two-column table, base on the left, PR on the right, one row per changed surface. Omit this section only when nothing visual changed.
7. `### Notes` — numbered, marker-led bullets that the inline comments can be cross-referenced against

Post with a JSON payload rather than shell-quoting bodies that contain backticks, tables and emoji:

```bash
gh api --method POST "repos/<owner>/<repo>/pulls/<n>/reviews" --input payload.json
```

To revise after posting: `PUT .../pulls/<n>/reviews/<review_id>` for the summary, `PATCH .../pulls/comments/<comment_id>` for an inline comment. Both preserve the thread.

### 12. Merge policy

Merging is the user's call. Recommend, then wait for an explicit go-ahead.

Before recommending a merge:

- confirm the status checks actually passed (`gh pr view <n> --json statusCheckRollup`)
- **check mergeability too, not just checks** (`--json mergeable,mergeStateStatus`). Green checks and a blocked merge button are independent facts.
- match the repo's merge style and branch cleanup by looking at how the last few PRs landed (`git log --merges`)

**When GitHub says a merge is dirty but git merges clean, suspect a custom merge driver.** A generated file declared `merge=union` in `.gitattributes` conflicts under the default 3-way driver, and GitHub's mergeability probe does not apply the attribute. Pin it with `git merge-file` under both drivers before reporting it, and check whether the repo's history already works around it by merging base into the branch first.

**File follow-up issues before the merge, not after.** In this skill's corpus a nitpick was raised on two separate PRs, both merged with "worth filing" attached, and the issue was never filed. "We'll file it later" is where findings go to die. If a 🟡 deserves a follow-up, create it while the PR is still open.

If you cannot file — read-only scope, no tracker access, someone else's repo — then **name the exact issues that need filing inside the review**, each with enough detail that filing is mechanical, and say plainly that they are unfiled. Do not let the constraint turn into silence.

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| Reviewing the diff only | Misses everything in stage 5 and 6 | Build and run it |
| Reading the PR's existing review before measuring | Your "independent" findings are someone else's | Read it last, then reconcile |
| Concluding visibility from computed styles | Overstated blockers ("no edge at all" when it is 1.15:1) | Sample painted pixels |
| Trusting a pass-either-way test's comment | A test that pins nothing reads as coverage | Make the change it claims to catch |
| Trusting a preview server after a rebuild | Screenshots of the wrong build, stated as fact | Assert build identity (stage 4) |
| Assuming a port is yours | A different app gets tested; every test "fails" | `lsof` first, dedicated port |
| Comparing lightness instead of contrast | Conclusion inverts between themes | Contrast ratio against the real surface |
| `toBeVisible()` for clipping | Passes while the content is cropped | `elementFromPoint` hit-test |
| Reporting marker count as finding count | A good PR looks broken | Dedupe to root causes first |
| Calling a pre-existing issue a regression | Author owes work they did not create | A/B against base |
| Re-raising what the author already deferred | Noise, and it reads as not having read the PR | Read the body for open items |
| Filing follow-ups "after merge" | They never get filed | File while the PR is open |
| Screenshot with no annotation | Reader has to find the problem themselves | Overlay guides and measured labels |
| After-only screenshots on a visual change | Reader cannot judge what actually changed | Before/after pair per surface, from both warm builds |
| A throwaway spec file per measurement | A full build-and-serve cycle for a few numbers | One browser session, one batched script |
| Re-running a suite CI already passed | Minutes spent re-deriving a known result | Read `statusCheckRollup`; run only the load-bearing proof |
| Rebuilding to take a screenshot | Cycle cost, and a stale-build risk each time | Keep both previews warm; rebuild only after editing source |

## Red flags in your own draft

- "looks a bit off", "seems misaligned", "might be an issue" → you did not measure it
- a severity marker with no number, ratio, or coordinate behind it
- 🔴 on something the base build also does → that is not a regression
- more markers than distinct problems
- a summary that buries a blocker below a table
- "worth filing a follow-up" with no issue created
- an inline comment that opens by explaining which element it is about → it is anchored, delete the preamble
- a visual change reported with no before/after pair
- you are past ten minutes on a small PR → count your build cycles, not your findings
- you are writing a spec file to read a computed value → use the session you already have
