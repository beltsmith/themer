# 01 — Perceptual and empirical evidence for code colouring

Scope: what controlled studies, vision science and program-comprehension research say about colouring source code. Popular themes are deliberately excluded.

Evidence tags:
- **[strong]**: replicated, large-N, or textbook-level findings
- **[moderate]**: a single solid study, or a consistent pattern across small studies
- **[weak]**: small N, null or underpowered results, or indirect transfer from another domain
- **[opinion]**: practitioner argument with no controlled data

Two verification notes. "Verified" means the primary text was read for these notes. Items marked (secondary) were taken from a citing paper or from memory and should be checked before anyone relies on them.

---

## 1. Empirical studies of syntax highlighting

| Study | N / population | Design | Result | Tag |
|---|---|---|---|---|
| Sarkar 2015, *The impact of syntax colouring on program comprehension*, PPIG 26. https://advait.org/files/sarkar_2015_syntax_colouring.pdf (verified) | 10 Cambridge CS grad students; eye data usable for only 7 | Within-subjects. 6 Python programs, task "predict output", highlighted vs plain | Median task time 8.4 s faster with highlighting (Wilcoxon T=136, p=0.047). Fewer "context switches", i.e. glances back to the prompt to re-check input values (median −23, p=0.045). **No effect on fixation count or fixation duration.** The benefit shrank with experience (Spearman −0.37, p=0.044). | weak |
| Hannebauer, Hesenius & Gruhn 2018, *Does syntax highlighting help programming novices?*, Empirical Software Engineering 23(5):2795–2828. https://doi.org/10.1007/s10664-017-9579-0 (abstract verified; paywalled) | 390 undergraduates in an intro Java course | Within-subjects. Small comprehension tasks with and without highlighting; correctness measured | **No evidence** that highlighting improves novices' comprehension. The authors argue highlighting "squanders a feedback channel" that the IDE could use better. | moderate (for a null result; the large N gives it weight) |
| Beelders & du Plessis 2016, *Syntax highlighting as an influencing factor when reading and comprehending source code*, J. Eye Movement Research 9(1). https://doi.org/10.16910/jemr.9.1.1 (verified) | 34 C# students, 17 per group | Between-subjects, 2 snippets, eye tracking | Fixations, fixation durations and regressions were all slightly higher for black-and-white code, but **none significantly** (e.g. U=99, p=0.12). Students *preferred* colour and rated it easier to read. | weak |
| Beelders & du Plessis 2016, *The influence of syntax highlighting on scanning and reading behaviour for source code*, SAICSIT. https://dl.acm.org/doi/10.1145/2987491.2987536 (secondary) | students | eye tracking | Distinct reading phases appeared with and without highlighting. No significant effect on fixation count or duration. | weak |
| Andrzejewska 2016, *The influence of syntax highlighting on reading program source code – eye-tracking research*, ETI 3/17. https://doi.org/10.15584/eti.2016.3.31 (verified abstract) | 13 CS students | Search for syntax errors in colour vs B/W | No significant effect on task performance or eye metrics | weak |
| Hakala, Nykyri & Sajaniemi 2006, *An experiment on the effects of program code highlighting on visual search for local patterns*, PPIG 18. https://www.ppig.org/papers/2006-ppig-18th-hakala/ (verified) | 21 intermediate students | Within-subjects. Plain vs "block" scheme (colours larger syntactic structures, less clutter) vs "token" scheme (vim Java defaults) | Scheme differences were small and n.s. **Plain text matched the coloured schemes overall.** Target type mattered, and each scheme was best for *some* target type (interaction p≈.05, "almost significant"). | weak |
| Gilmore & Green 1988 (secondary, via Sarkar 2015) | programmers | Highlighting control structures vs "plan" structures | Control-structure cues sped up finding *surface* bugs. Plan-structure cues sped up finding *deep* bugs. **Cues help only when they match the task.** | moderate (classic, old) |
| Feigenspan, Kästner, Apel et al. 2013, *Do background colors improve program comprehension in the #ifdef hell?*, EMSE. https://www.cs.cmu.edu/~ckaestne/pdf/ese12.pdf (verified) | 3 experiments, >70 subjects | Background colour per preprocessor feature | Colour sped up *locating* feature code, by up to 55% in one phase (large Cohen's d). **No benefit, or a slowdown, for maintenance and bug fixing.** Highly saturated backgrounds slowed bug fixing, which the authors attribute to visual fatigue, and **subjects did not notice the harm** and still preferred colour. No effect in the task that needed 12 colours at once; the authors suspect a capacity limit. | moderate |
| Park, Weill-Tessier, Brown, Jensen et al. 2023, *An eye tracking study assessing the impact of background styling in code editors on novice programmers' code understanding*, ICER. https://icer2023.acm.org/details/icer-2023-papers/32/ (abstract) | novices, crossover, 12 tasks | Plain Java vs BlueJ scope backgrounds vs Stride frames | No difference in correctness or speed. Gaze moved around less in Stride. | weak–moderate |

**What this body of work supports overall**
- E1 [moderate] The measured effect of conventional token-class highlighting on comprehension is **small to null**. The one significant speed effect (Sarkar) has N=10 and p≈0.05. The largest study (N=390) is null.
- E2 [moderate] Users reliably **prefer** colour, and that preference does **not** predict a performance gain (Beelders; Feigenspan). Preference is not evidence of benefit.
- E3 [moderate] Colour helps when it encodes **information that the task needs and that is not already visible** (Gilmore & Green; Feigenspan, where the locate tasks benefited and other tasks did not; Hakala's scheme × target interaction).
- E4 [weak] The benefit falls as expertise grows (Sarkar). Experts already read selectively (§4).
- E5 [moderate] Highly saturated colour over large areas can hurt sustained work, and users do not notice the harm (Feigenspan).
- Gap: I found **no controlled study** of semantic highlighting (per-identifier "rainbow" colouring) or of "highlight less" schemes for comprehension. Claims about them are untested.

## 2. Practitioner arguments (opinion unless noted)

- **Tonsky 2025**, *I am sorry, but everyone is getting syntax highlighting wrong*, https://tonsky.me/blog/syntax-highlighting/ [opinion; no formal evidence]. Claims:
  - "If everything is highlighted, nothing is highlighted."
  - Use **≤4 colours**, so that each one can be *looked up* from memory. His demonstration that readers cannot recall what their own theme's colours mean is anecdotal.
  - Highlight what is rare and useful as a landmark: **top-level definitions, constants/literals, strings, comments**.
  - Do **not** colour keywords. They are frequent, and readers look for the condition, not the `if`.
  - Make **comments prominent**, not grey. Grey out only disabled code.
  - Avoid bold and italic because they add another dimension.
  - Dark backgrounds allow more distinguishable vivid hues. Light themes may need background tints.
  - Uniform-lightness palettes make colours look alike, so use lightness differences deliberately.
- **Åkesson 2007**, *A case against syntax highlighting*, https://linusakesson.net/programming/syntaxhighlighting/ [opinion]. Claims:
  - Colour fragments reading flow and moves attention "from content to form".
  - It acts as training wheels for novices.
  - The syntax that colour reveals is already checked by the compiler.
  - Two exceptions: **multi-line comments**, so commented-out code is not mistaken for live code, and `=` vs `==`.
  - He recommends at most two classes: code and comments.
- **Evan Brooks 2014**, *Coding in color*, https://medium.com/@evnbr/coding-in-color-3a6db2743a1e (fetch blocked; summary from memory, secondary) [opinion]. Conventional highlighting colours things readers can already tell from their shape (keywords, punctuation). Colour is better spent on information that is *not* visible, such as **identifier identity**: each variable gets its own hue so that data flow can be traced (semantic highlighting).
- **Rougier 2020**, *On the design of text editors*, arXiv:2008.06030, https://arxiv.org/abs/2008.06030 (verified) [opinion, informed by attention literature]. He proposes colouring by **attentional role rather than syntax**, using six faces:
  - *critical*: high-contrast background, used rarely
  - *popout*: hue clearly different from all others
  - *strong*: same colour as default, **weight +1 step only**, for structure
  - *salient*: different hue, same intensity as default
  - *faded*: same hue, lower intensity, for comments and secondary text, replacing italic
  - *subtle*: barely visible background, for regions
- Shared principle across these essays [opinion, but consistent with §3]: **colour carries meaning only if it is scarce and only if it adds information the shape of the text does not already give.**

## 3. Vision science

### Preattentive features and pop-out
- [strong] Treisman & Gelade 1980, *A feature-integration theory of attention*, Cognitive Psychology 12:97–136 (secondary). A target that differs by a single feature, such as hue, is found in parallel: search time is flat as the number of items grows. A target defined by a *conjunction* of features, such as red-and-bold, requires serial search.
- [strong] Wolfe & Horowitz 2017, *Five factors that guide attention in visual search*, Nature Human Behaviour 1:0058, https://search.bwh.harvard.edu/new/pubs/FiveFactors_Wolfe-Horowitz_2017.pdf. Attention is guided by:
  1. bottom-up salience
  2. top-down feature guidance (knowing the target's colour)
  3. scene structure and meaning
  4. search history and priming
  5. value

  Colour is among the strongest guiding attributes. **Factors 3 and 4 mean that layout and learned habit compete with colour.**
- [strong] Duncan & Humphreys 1989 (secondary, cited in Haroz & Whitney). Search efficiency falls as targets become more similar to distractors and as the distractors become more varied among themselves.
- [moderate] Green & Anderson 1956 (secondary, via Sarkar 2015). Colour coding reduces search time **when the target's colour is known in advance**. Colouring all tokens gives little benefit when the reader does not know which colour to look for.

### Capacity: how many colour categories
- [moderate] Healey 1996, *Choosing effective colours for data visualization*, IEEE Vis / UBC TR-96-10, https://www.cs.ubc.ca/sites/default/files/tr/1996/TR-96-10_0.pdf (verified). 38 observers in the 3- and 5-colour studies.
  - With 3 or 5 colours, targets were found in 459–661 ms with ~2.5% error, independent of display size.
  - At 7 and 9 colours, some targets fell back to **serial search**, with RTs up to ~3.5 s.
  - With careful control of colour distance, linear separation and **named colour category**, "seven isoluminant colours is the maximum" for rapid identification. The final 7-colour result rests on **one observer, the author**.
  - The "5–7 colours" rule of thumb that circulates in industry is anecdotal, and Healey says so.
- [moderate] Haroz & Whitney 2012, *How capacity limits of attention influence information visualization effectiveness*, IEEE TVCG (InfoVis best paper), https://whitneylab.berkeley.edu/PDFs/Haroz_Whitney_2012_InfoVis.pdf (verified). Small N (5 per experiment) but many trials (880 per subject).
  - (a) **Known-target search** with colour stays nearly flat as the number of colours ("variety") grows, at a cost of a few ms per category.
  - (b) **Oddball search**, i.e. noticing something unexpected without knowing its colour, degrades steeply with variety when colours are spatially intermixed. Grouped layouts largely escape the cost.
  - (c) Judging *how many* categories are present collapses towards chance beyond about 3–4 categories when they are intermixed.
  - Guidelines: "less is more"; "reduce variety in the entire view rather than optimizing small regions"; a legend or known appearance helps; grey out what is not of current interest.
  - Code is a maximally *intermixed* layout, because token classes interleave on every line. This is the worst case for (b) and (c).
- [strong] Miller 1956 (7±2) and Cowan 2001 (~4 chunks) on working-memory capacity (secondary). Mapping colour to meaning is an arbitrary association that has to be held or learned. Feigenspan explicitly invokes this limit for its 12-colour failure.
- [moderate] Ware, *Information Visualization: Perception for Design* (secondary, from memory). For nominal labels, recommends about **6 reliably distinct colours, up to ~12**, chosen from basic colour-term categories: red, green, yellow, blue, black, white, then pink, cyan, grey, orange, brown, purple. Colours that share a name are confused.

### Colour as label vs highlight; salience
- [strong] Colour does two separate jobs:
  - **Labelling** (nominal identity): every item gets a hue and the reader decodes it. This costs memory and suffers from capacity limits.
  - **Highlighting** (salience): a few items differ from a neutral ground. This uses parallel pop-out and is cheap.

  Sources: Ware (secondary); Haroz & Whitney.
- [moderate] Highlighting validity. Fisher & Tan 1989, Human Factors 31(1), and related Fisher et al. work (secondary, paywalled). Highlighting speeds search when the highlighted items are likely targets and *costs* time when they are not. The more items are highlighted, the smaller the benefit.
- [strong] Salience is relative. An item pops out by contrast with its *neighbours*, so a heavily coloured field reduces the pop-out of any single colour. Sources: Duncan & Humphreys; Wolfe.
- [moderate] Saturated colours over large areas cause fatigue and slowdowns (Feigenspan 2013).

### Luminance, legibility, weight and slant
- [strong] Legge et al. 1990, *Psychophysics of reading XI: comparing color contrast and luminance contrast*, https://legge.dl8.umn.edu/sites/legge.psych.umn.edu/files/files/media/legge90_psychophysics_of_reading._xi._comparing_luminance_and_color_contrast.pdf, and Knoblauch, Arditi & Szlyk 1991, JOSA A 8:428 (secondary).
  - Reading speed depends on effective contrast.
  - The curves for colour contrast and luminance contrast have the same shape once scaled to threshold, and there is no additive benefit when both are present.
  - Implication: a hue change does not make text more legible. **Low-luminance-contrast colours (dim blues, greys) are slower to read.**
- [strong] Tinker 1963, *Legibility of Print*, ch. 4 and summary, https://www.gwern.net/doc/design/typography/1963-tinker-legibilityofprint.pdf (verified). This is prose on paper, so the transfer to monospace screens is assumed.
  - **Italic** is read about 2.7–5% slower (≈15.5 wpm). 96% of 224 readers preferred roman. Combined with other marginal conditions (small size, low light), the slowdown exceeds 10%.
  - **Bold** is read at the *same* speed as regular and is seen at greater distance. 70% of readers prefer regular for running text.
  - **"Medley" arrangements** that mix italic, caps, bold and sizes within text were read significantly more slowly. This is the typographic analogue of over-highlighting.
  - All-caps retards reading substantially.
- Gap: I found no controlled study of bold or italic in *monospace code on screens*. Treat the italic penalty as likely to transfer (the slant reduces x-height clarity, and many monospace italics are cursive with altered letterforms), but the transfer is unverified [weak].

## 4. What readers need to find in code

- [moderate] **Identifiers dominate code.** About 33% of tokens and ~70% of characters are identifiers (Eclipse corpus). Deissenboeck & Pizka 2006, *Concise and consistent naming*, Software Quality Journal, https://wwwbroy.in.tum.de/publ/papers/deissenboeck_pizka_identifier_naming.pdf (verified). Consequence: the "default" foreground is mostly identifiers, so whatever colour they get *is* the ground.
- [moderate] **Beacons.**
  - Brooks 1983, *Towards a theory of the comprehension of computer programs*, IJMMS (secondary). Comprehension is top-down: readers form hypotheses about what code does and verify them against **beacons**, stereotyped surface features that indicate a structure or operation (e.g. a swap inside nested loops signals a sort).
  - Wiedenbeck 1986 (secondary) found experts recall beacon lines better.
  - Crosby, Scholtz & Wiedenbeck 2002, *The roles beacons play in comprehension for novice and expert programmers*, PPIG 14, https://ppig.org/files/2002-PPIG-14th-crosby.pdf (verified): **novices barely discriminate** between important and unimportant lines, while more experienced programmers concentrate on beacon areas. The expertise effect was F(2,336)=3.37, p≤.05.
  - Beacons are *semantic*, not lexical. Keyword colouring does not mark them.
- [moderate] **Non-linear reading.** Busjahn et al. 2015, *Eye movements in code reading: relaxing the linear order*, ICPC, https://huang.isis.vanderbilt.edu/cs8395-f23/paper/linear-order-eye.pdf. Novices read code less linearly than prose, and experts less linearly than novices: they jump between definitions, call sites and control points. Readers need **landmarks to jump to**, not decoration along the reading line.
- [moderate] **What gets fixated.**
  - Rodeghero et al. 2014 (ICSE, 10 professionals; TSE 2015 https://www3.nd.edu/~cmc/papers/rodeghero_tse15.pdf): in isolated methods, **signatures** received the most attention, then **call terms**, then **control-flow terms**.
  - Abid et al. 2019, *Developer reading behavior while summarizing Java methods: size and context matters*, ICSE, https://arxiv.org/abs/1903.03358 (18 developers, real IDE, 63 methods): in context, developers read the **body more than the signature**, and revisit the body more as methods grow.
  - Takeaway: definitions are entry points, but bodies, specifically calls and control flow, are where time is spent.
- [moderate] **Information foraging.** Lawrance, Bogart, Burnett et al. 2013, *How programmers debug, revisited: an information foraging theory perspective*, IEEE TSE 39(2), https://web.engr.oregonstate.edu/~burnett/Reprints/TSE-IFT-2013-asprinted.pdf. Navigation while debugging is predicted by **information scent**, i.e. words and cues that match the goal, better than by hypotheses (10 professionals). Identifier names carry most of the scent, so they should stay maximally legible.
- [weak] Uwano et al. 2006 (code review eye tracking, secondary): reviewers do an initial **scan** of the whole code, and longer scans correlate with better defect detection. Global structure (definitions, block boundaries) matters during the scan.
- Comments vs code [opinion, with partial support]:
  - Åkesson and Tonsky both single out comments, and especially commented-out code, as worth distinguishing.
  - No study measures it directly. The hazard of misreading disabled code as live is plausible.
- Errors/diagnostics: by design these are the classic "critical/popout" case. Validity is high when they appear, and they are rare (Fisher & Tan logic). [moderate by transfer]

## Terms

- **Preattentive feature**: visual property (hue, luminance, orientation, size, motion) detected in parallel across the field in under ~200–250 ms. Treisman & Gelade 1980; Healey 1996.
- **Pop-out**: a single-feature target found in constant time regardless of the number of distractors. Treisman & Gelade 1980.
- **Conjunction search**: a target defined by a combination of features; serial and slow. Treisman & Gelade 1980.
- **Guided search / feature guidance**: top-down use of known target features (e.g. "it's yellow") to direct attention. Wolfe & Horowitz 2017.
- **Salience**: bottom-up conspicuity of an item relative to its surroundings. Wolfe & Horowitz 2017.
- **Target–distractor similarity / distractor heterogeneity**: search slows as targets resemble distractors and as distractors vary. Duncan & Humphreys 1989.
- **Oddball search**: detecting an unexpected deviant without knowing its appearance; capacity-limited. Haroz & Whitney 2012.
- **Variety (feature variety)**: number of distinct categories on screen; drives capacity costs. Haroz & Whitney 2012.
- **Subitizing**: rapid, accurate enumeration of a small number (≤~4) of items or categories. Haroz & Whitney 2012.
- **Colour category**: named-hue region (Berlin & Kay basic terms); colours within a named category are confused. Healey 1996.
- **Linear separation / colour distance**: Healey's criteria for whether a target colour can be separated from distractor colours. Healey 1996.
- **Labelling vs highlighting**: nominal coding of every item vs salience applied to a few items. Ware (secondary).
- **Highlight validity**: probability that a highlighted item is the one the user wants. Benefit scales with it. Fisher & Tan 1989.
- **Secondary notation**: layout, colour and other cues that are not part of the formal syntax but aid human readers. Green 1989 (via Sarkar 2015).
- **Beacon**: a stereotyped code feature that signals a function or structure and anchors top-down comprehension. Brooks 1983; Wiedenbeck 1986.
- **Plan / cognitive plan**: a stereotyped programming pattern in the reader's mental model. Soloway; Gilmore & Green 1988.
- **Information scent**: cues indicating the likely value of a navigation path. Lawrance et al. 2013 (from Pirolli & Card).
- **Context switch** (Sarkar): a fixation moving to a different area of interest, e.g. back to the task prompt. Sarkar 2015.
- **Medley arrangement**: mixed type forms within a text; it slows reading. Tinker 1963.
- **Faded / strong / salient / popout / critical / subtle**: attention-role faces proposed for editors. Rougier 2020.

## Implications for colouring patterns

Each implication is meant to be falsifiable in a within-subjects test on a realistic task.

- **I1. Neutral ground.** Most tokens, including local identifiers, keywords, operators and punctuation, use the default foreground. Prediction: reducing the number of colour-coded classes from ~8–10 to ≤4 does not reduce comprehension accuracy or speed (consistent with E1) and improves oddball detection, e.g. spotting a stray literal or an error (Haroz & Whitney). Basis: identifiers make up ~70% of characters; oddball detection collapses under intermixed variety.
- **I2. Hue budget.** At most ~4–5 simultaneously meaningful hue categories in a typical view, each from a different named colour category (Healey; Haroz & Whitney; Ware). Prediction: readers can name each hue's meaning without a legend, and recall falls off beyond this number.
- **I3. Colour scarce, task-relevant, high-validity categories only.** Good candidates are definitions (names at the binding site), literals/constants, strings, comments, and diagnostics. Each of these is either a landmark for non-linear jumps (Busjahn; Rodeghero) or a distinct reading mode. Prediction: "go to the definition of X" visual search is faster with definition-site colouring. Keyword colouring gives no measurable benefit (Gilmore & Green: cues help only when task-matched).
- **I4. Don't colour by shape.** Do not spend hue on classes that are already distinguishable by glyph shape or position, such as keywords, punctuation and operators. Prediction: removing keyword colour has no effect on speed or accuracy.
- **I5. Mark definitions with colour plus weight.** Same hue as the class, and bold only at the definition site (Rougier's "strong"). Tinker: bold costs no reading speed and increases visibility. Prediction: definition sites are found faster than with hue alone, at no cost to reading speed.
- **I6. Avoid italic as a primary carrier.** Italic carries a 3–5% reading cost, rising above 10% under marginal conditions (Tinker), and many monospace italics change letterforms. If italic is used at all, reserve it for text that is not read as code, such as comments or docstrings, never for identifiers.
- **I7. De-emphasise with luminance, emphasise with hue.**
  - "Faded" means the same hue at lower luminance contrast. Use it for low-value material: disabled code, punctuation if desired, inferred or virtual text.
  - Never apply it to something the reader must read closely, because reading speed tracks effective contrast (Legge; Knoblauch).
  - Prediction: commented-out code rendered faded is misread as live code less often than code rendered at normal contrast.
- **I8. Separate prose comments from disabled code.** Prose comments are readable, not faded. Commented-out code is faded (Åkesson; Tonsky). Testable via misreading rate.
- **I9. Critical/pop-out tier only for errors and diagnostics.** Reserve one maximally distinct treatment, such as a saturated background or underline, exclusively for errors and diagnostics, and keep it absent from normal syntax. Highlight validity stays high only if the treatment is rare (Fisher & Tan). Prediction: error detection latency increases when that hue is also used for an ordinary syntax class.
- **I10. No large saturated areas.** Background tints for regions (scope, diff, search, selection) should be low-saturation, "subtle" tints (Feigenspan: saturated backgrounds slowed bug fixing, and users did not notice).
- **I11. Semantic per-identifier colour as opt-in.** Treat it as a task mode, such as "trace this variable" or highlighting all occurrences under the cursor, not as an always-on label. Rationale: a small number of tracked identifiers is within capacity (Feigenspan's 1–2 features helped; 12 did not), and a fully rainbowed buffer maximises intermixed variety (Haroz & Whitney). Prediction: always-on rainbow identifiers do not beat cursor-driven occurrence highlighting on data-flow tasks and are worse at oddball detection.
- **I12. Consistency across languages and modes.** Each hue must keep one meaning across languages and modes so that top-down guidance can be learned (Green & Anderson: colour helps only when the target colour is known; Wolfe: search history). Prediction: inconsistent mappings slow known-target search.
- **I13. Do not use preference as the success metric.** Users prefer more colour regardless of performance (Beelders; Feigenspan). Validate patterns with task measures: locate-definition time, misread-disabled-code rate, oddball and error detection.
- **I14. Expect larger benefits for novices on search tasks, not on comprehension.** Effects are likely small and task-specific (E1–E4). Design for *finding* (landmarks), not for *understanding* (no evidence that colour supports it).
