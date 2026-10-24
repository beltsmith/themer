# Human review: decisions the numbers can't make

**Decisions so far (2026-10-23).** 1: weights accepted. 2: hue choice belongs to the creator,
except fixed conventions (red = error, green/red = diff). 3: red allowed for syntax.
4: renders use Gruvbox, Monokai, Kanagawa and Zenburn. 5: timed test pending.

Each item gives a recommendation. Reply with *accept*, *change*, or a comment. Items 1–4
take a few minutes each. Item 5 is the only source of performance data and takes about 10
minutes.

## 1. Value weights (`patterns/weights.yaml`)

These encode *how much it matters* if two roles are confused, plus each role's value as a
landmark. The literature sets their order but not their size. They drive the confusion
cost, the ladder and assignment.

**Recommendation:** check the `pairs` list in particular. The top weights are
string/comment = 3 and comment/code = 3. Is anything missing that has bitten you in practice?

## 2. Hue assignment: habit vs optimisation (H10)

- **Mode B (habit):** hues follow common conventions (values green-ish, definitions blue-ish), so meanings carry over between themes.
- **Mode A:** gives the loudest accent to the family that most needs salience.

On v2.1 they tie on every metric (C1 −0.46 vs −0.44, same confusion cost). Habit fit is 0.72 vs 0.22.

**Recommendation:** mode B. Confirm that cross-theme consistency is worth keeping.

## 3. Reserving the error hue

Reserving red (and any colour with the same hue name) for diagnostics follows the
evidence that a pop-out cue works only while it stays rare. The cost: the share of palettes
that can carry all 4 loud families falls from 80% to 68%. Losses are
ladder-ordered: *meta* (decorators and macros) goes first, then *exit*. Definitions keep bold
even when their hue goes.

**Recommendation:** keep the reservation.

## 4. Look and feel

Open `out/renders/grid_<lang>.html` for python, typescript, rust, go and c. Each row is a
palette (a stratified random sample: dark/light × low/mid/high capacity). The columns are
*plain*, *landmark A*, *landmark B*, *hybrid A*, *label B* (the conventional control) and
*landmark v1*. Judge only what metrics can't capture:

- Do quiet strings read as strings at a glance, without shouting?
- Are dim comments comfortable to read? Tokyo-night-storm is a known bad case, because its fg is low-contrast.
- Should comments be italic? This is the only place italic is allowed. Default: off.
- Does anything look *wrong*, such as a role in a surprising colour? That usually means a selector bug.

Don't vote on which column is prettiest. Preference doesn't track performance (Beelders;
Feigenspan): people consistently prefer more colour.

## 5. Timed search test (optional, ~10 min)

Open `out/renders/tasks.html` in a browser: 27 trials covering 3 languages × 3 tasks
(find definitions / exits / literals) × 3 conditions (plain / landmark / label). The trials
are Latin-squared over different snippets, so you don't learn positions. Click every match,
press Done, and at the end save `task_results.json` into `research/out/`.

With one subject this is a sanity check, not a study. It still tests the core claim (H4/H12)
that landmark makes searching faster or more accurate than both plain and label.

## 6. Open design questions (answer if you have an opinion)

- Should parameters get a quiet tint when LSP semantic tokens are available? They are 1.9% of ink, and Lua can't tell them from locals.
- Should `await` count as an exit? It is currently *not* one: it resumes, and it is 1.3% of TypeScript ink.
- Should commented-out code be faded (needs a detection heuristic)?
