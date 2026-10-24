# 03 — Colour science for palette-agnostic code colouring

Purpose: give us numbers for deciding whether a palette (base16, base24, a terminal
16-colour set) can support a given colouring pattern. Each section has a table of
thresholds with a source and a confidence rating. The "Recommended metrics" section
turns these into exact checks for a Python validation harness.

Confidence key: **H** = number checked against the primary source or reproduced in
code here. **M** = number from a reliable secondary source or recalled from the
primary source and consistent with checked data. **L** = rule of thumb or our own
derivation. Treat L numbers as tunable parameters.

Viewing assumption for "text-sized": a 13–15 px monospace font at about 60 cm on a
~96–110 dpi display. 1 px is about 0.025°, x-height (6–8 px) is about 0.15–0.2°, the
full glyph cell is about 0.3–0.4°, and a stroke is 1–2 px (0.025–0.05°). HiDPI
screens give thinner strokes in degrees for the same nominal size. Because a glyph is
a set of thin strokes, the **line** models below fit text better than the
**point/patch** models.

---

## 1. Perceptual colour spaces

| Space | What it is | Strengths for us | Known weaknesses | Source | Conf. |
|---|---|---|---|---|---|
| CIELAB (1976) + ΔE*ab | L* 0–100, a*, b* opponent axes; Euclidean distance | Every small-mark threshold study (Stone 2014, Szafir 2018, Carter & Silverstein 2010) is in CIELAB units, so we can use their thresholds without conversion | Hue is not linear in the blue region (blue moves toward purple as chroma drops, an Abney-like error). Overstates chroma differences at high chroma. Classic JND ≈ 2.3 ΔE*ab (Sharma & Trussell 1997) applies only to large patches | Sharma, *Digital Color Imaging Handbook* 2003 | H |
| CIEDE2000 (ΔE00) | Corrections to CIELAB for lightness, chroma, hue and blue rotation | Industry standard for small differences; ΔE00 ≈ 1 is about one JND for large patches | Discontinuities; not a metric (fails triangle inequality); meant for small differences (< ~5), not a uniform space; not for large-difference palette spacing | Sharma, Wu & Dalal 2005, "The CIEDE2000 color-difference formula: implementation notes…", *Color Res. Appl.* 30(1). http://www2.ece.rochester.edu/~gsharma/ciede2000/ | H |
| CAM16-UCS | CIECAM16 appearance model (J', a', b') with uniform-space compression; takes viewing conditions (adapting luminance, surround, background) into account | Best-validated uniform space for both small and large differences; can model the background a colour is seen against | Heavier to compute; results depend on viewing-condition parameters; Euclidean ΔE' in CAM16-UCS is roughly comparable to ΔE00 for small differences | Li, Li, Wang, Zu, Luo, Cui, Melgosa, Brill, Pointer 2017, "Comprehensive color solutions: CAM16, CAT16, and CAM16-UCS", *Color Res. Appl.* 42(6). https://doi.org/10.1002/col.22131 | H (existence) / M (performance) |
| OKLab / OKLCH | L 0–1, a/b ≈ ±0.4; fitted to CAM16 lightness/chroma and IPT hue data | Cheap, closed-form, good hue linearity (blue stays blue when desaturated, better than CIELAB). Used by CSS Color 4 for gamut mapping, with JND = 0.02 ΔEOK. Good for constructing and adjusting colours (ramps, hue rotation) | Lightness is too dark in the low range compared with CIELAB L* (Ottosson's later "Lr" toe fixes this; coloraide's `oklrab`/`oklrch`). Not fitted to small-difference data; ΔEOK compresses chroma relative to lightness compared with CIELAB/ΔE00. High-chroma blues get different lightness estimates than in CIELAB. No viewing conditions | Ottosson 2020, "A perceptual color space for image processing", https://bottosson.github.io/posts/oklab/ ; Ottosson 2021, "Okhsv and Okhsl", https://bottosson.github.io/posts/colorpicker/ ; CSS Color 4 §13 gamut mapping, https://www.w3.org/TR/css-color-4/#gamut-mapping ; Lilley, "Better than Lab?", https://www.w3.org/Graphics/Color/Workshop/slides/lilley/lilley.html | H |

**Scale conversion (measured here).** For near-threshold sRGB pairs (ΔEOK 0.01–0.06,
20 000 random pairs), the median of ΔE00 / ΔEOK is **≈ 126** (IQR 103–169). For
lightness, ΔL_ok × 100 ≈ ΔL*. Across chroma, ΔE*ab / ΔEOK is about 300 because CIELAB
stretches chroma. A single ΔEOK threshold therefore cannot reproduce per-axis CIELAB
thresholds. **H** (computed with coloraide 8.13.1).

**Verdict.** Use **CIELAB (D65)** with the size-dependent, per-axis-normalised model
from §2 for the "can these two token colours be told apart" check, because that is
where the small-mark data was collected. Use **OKLCH** to describe the palette, for
hue and chroma classification, and to synthesise or adjust colours. Report **ΔE00** and
**ΔEOK** alongside as sanity checks. CAM16-UCS is optional (coloraide `ColorAll`,
`delta_e(method='cam16')`). Consider it only if we later model background adaptation
explicitly.

---

## 2. Colour difference for small marks and text

The model (Stone, Szafir & Setlur 2014; Szafir 2018) says that the CIELAB difference
needed for p % of viewers to notice a difference, per axis, grows as the mark gets
smaller:

`ND_x(p, s) = p / (c_x − k_x / s)` (Szafir 2018, Eq. 3), with `s` = size in degrees.
Normalised difference: `ΔE_{p,s} = sqrt((ΔL/ND_L)² + (Δa/ND_a)² + (Δb/ND_b)²)`
(Szafir 2018, Eq. 4). **ΔE_{p,s} ≥ 1 means p % of viewers will notice the difference.**

### 2a. Coefficients

| Model | Axis | Formula (p as fraction; 50 % shown) | Source | Conf. |
|---|---|---|---|---|
| Isolated patches, 0.33–2° (Stone 2014) | L* | ND_L(50,s) = 5.079 + 0.751/s | Stone, Szafir & Setlur 2014, "An engineering model for color difference as a function of size", 22nd IS&T Color & Imaging Conf., pp. 253–258. https://library.imaging.org/cic/articles/22/1/art00040 ; https://www.tableau.com/research/publications/engineering-model-color-difference-function-size | M (coefficients recalled; a* value at 0.5° = 8.42 confirmed by Szafir 2018 text) |
| | a* | ND_a(50,s) = 5.339 + 1.541/s | same | M |
| | b* | ND_b(50,s) = 5.349 + 2.871/s | same | M |
| Scatterplot points with distractors, 0.25–2° (Szafir 2018 Exp. 1) | L* | ND_L(p,s) = p / (0.0937 − 0.0085/s); 50 % logistic fit: 5.095 + 0.80/s | Szafir 2018, "Modeling Color Difference for Visualization Design", IEEE TVCG 24(1):392–401, doi:10.1109/TVCG.2017.2744359. Paper: https://par.nsf.gov/servlets/purl/10074616 ; data: https://cmci.colorado.edu/visualab/VisColors/ | H |
| | a* | p / (0.0775 − 0.0121/s); 50 %: 5.089 + 2.69/s | same | H |
| | b* | p / (0.0611 − 0.0096/s); 50 %: 6.786 + 3.20/s | same | H |
| **Lines, 0.05–0.35° thick (Szafir 2018 Exp. 3)** (closest analogue to glyph strokes) | L* | **ND_L(p,s) = p / (0.0742 − 0.0023/s)** | same, Eqs. 14–16 | H |
| | a* | **ND_a(p,s) = p / (0.0623 − 0.0015/s)** | same | H |
| | b* | **ND_b(p,s) = p / (0.0425 − 0.0009/s)** | same | H |
| Bars (thickness and length) | — | Gains from elongation level off as length/thickness grows; use thickness for a conservative estimate | same, Exp. 2 | H |

### 2b. Evaluated thresholds (CIELAB ΔE needed on a single axis)

| Mark / size | p | ΔL* | Δa* | Δb* | Conf. |
|---|---|---|---|---|---|
| Line 0.05° (≈ 1–2 px stroke) | 50 % | 17.7 | 15.5 | 20.4 | H (model extrapolated to the low edge of the tested range) |
| Line 0.05° | 80 % | 28.4 | 24.8 | 32.7 | H/L |
| **Line 0.10° (≈ 3 px; bold or large text)** | **50 %** | **9.8** | **10.6** | **14.9** | H |
| Line 0.10° | 80 % | 15.6 | 16.9 | 23.9 | H |
| Line 0.25° | 50 % | 7.7 | 8.9 | 12.9 | H |
| Point 0.25° | 50 % | 8.3 | 15.8 | 19.6 | H |
| Point 0.33° (≈ glyph cell) | 50 % | 7.5 | 13.2 | 16.5 | H |
| Isolated patch 0.5° (Stone) | 50 % | 6.6 | 8.4 | 11.1 | M |
| Isolated patch 2° (Stone) | 50 % | 5.5 | 6.1 | 6.8 | M |
| Classic large-patch JND | ~50 % | 2.3 ΔE*ab, or ≈ 1 ΔE00 | | | H |

Key facts from Szafir 2018 (all **H**):
- Web-viewed scatterplot JNDs are roughly **7× larger** than traditional colour-science
  JNDs.
- Lightness differences are detected most reliably. b* (blue–yellow) needs the largest
  difference at small sizes, which matches small-field tritanopia: the central fovea has
  almost no S-cones.
- At equal thickness, lines are much easier to tell apart than points: 6 px line
  Δa* JND = 9.4 against 16 for a 6 px point.
- The authors' pilot found the model **overestimates** thresholds below 0.25° (it
  predicts ND_b(50 %, 0.05°) = 63, but much smaller steps were visible). Treat the
  0.05° values as conservative upper bounds.
- 13 of 18 nine-step ColorBrewer sequential ramps were not robust for 4 px lines and
  10 px points.

Also relevant: Carter & Silverstein 2010, "Size matters: Improved color-difference
estimation for small visual targets", *J. Soc. Inf. Display* 18(1), doi:10.1889/JSID18.1.17.
This is a size-dependent extension of ΔE for targets down to a few arcminutes and
reaches the same conclusion. **M**

**What this means for code text (L, our synthesis).** For two token colours to be
told apart reliably on normal-weight text at code size, they need roughly
**ΔE_{80%, 0.1°} ≥ 1** with the line model. That is about **ΔL* ≥ 15**, or
**Δa* ≥ 17**, or **Δb* ≥ 24**, or a combination. At the 50 % "just noticeable"
level, ΔL* ≈ 10 or Δa* ≈ 11. In ΔEOK terms, a rough minimum is 0.08–0.10, and 0.12+
for reliable distinction. Many real palettes fall below this (see §8 stats).

---

## 3. Text contrast: WCAG 2.x and APCA

| Metric | Formula / threshold | Source | Conf. |
|---|---|---|---|
| WCAG 2.x relative luminance | Linearise sRGB (`c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`); Y = 0.2126R + 0.7152G + 0.0722B | WCAG 2.2, https://www.w3.org/TR/WCAG22/#dfn-relative-luminance | H |
| WCAG contrast ratio | (Y_light + 0.05) / (Y_dark + 0.05), range 1–21 | same | H |
| SC 1.4.3 AA | ≥ **4.5:1** normal text; ≥ **3:1** large text (≥ 18 pt, or ≥ 14 pt bold) | https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum | H |
| SC 1.4.6 AAA | ≥ **7:1** normal; ≥ 4.5:1 large | https://www.w3.org/WAI/WCAG22/Understanding/contrast-enhanced | H |
| SC 1.4.11 non-text | ≥ **3:1** for UI components and graphical objects | https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast | H |
| WCAG 2 weaknesses | Treats both polarities the same. Overstates contrast for dark colour pairs (dark mode). Ignores font weight and size beyond the "large" cutoff. Ignores spatial frequency | Myndex, "Why APCA", https://git.apcacontrast.com/documentation/WhyAPCA | M |
| APCA-W3 0.0.98G-4g | Y = 0.2126729·R^2.4 + 0.7151522·G^2.4 + 0.0721750·B^2.4 (simple 2.4 power, no linear segment). Soft clamp: if Y < 0.022, Y += (0.022 − Y)^1.414. If \|Y_bg − Y_txt\| < 0.0005, Lc = 0. Dark text on light bg: S = (Y_bg^0.56 − Y_txt^0.57)·1.14, Lc = S < 0.1 ? 0 : (S − 0.027)·100. Light text on dark bg: S = (Y_bg^0.65 − Y_txt^0.62)·1.14, Lc = S > −0.1 ? 0 : (S + 0.027)·100. Lc is about −108 to +106; negative means light-on-dark | https://github.com/Myndex/apca-w3 (constants checked) | H — our implementation reproduces the reference values: #888/#fff = 63.056, #fff/#888 = −68.541, #000/#aaa = 58.146, #aaa/#000 = −56.241 |
| APCA Lc 90 | Preferred for body text (≥ 14 px/400, ≥ 18 px/300); minimum for text ≥ 12 px/400 that is not body text | "APCA in a Nutshell", https://git.apcacontrast.com/documentation/APCA_in_a_Nutshell.html | H |
| **APCA Lc 75** | **Minimum for body/column text**: ≥ 18 px/400, 16 px/500, 14 px/700, 24 px/300; also non-body text ≥ 15 px/400 | same | H |
| **APCA Lc 60** | **Minimum for "content text" that is not body text** (e.g. short labels); size depends on weight, from 48 px/200 to 16 px/700 | same | H |
| **APCA Lc 45** | Minimum for larger, heavier text (36 px/400, 24 px/700) such as headlines; also detailed pictograms | same | H |
| APCA Lc 30 | Absolute minimum for any "spot-readable" text: placeholders, disabled text, copyright lines | same | H |
| APCA Lc 15 | Minimum for non-text that must be visible (dividers, thick focus rings ≥ 5 px) | same | H |
| Status | WCAG 3 is still a Working Draft. APCA is not a normative WCAG requirement and its licence ("W3C AGWG limited") is custom; check it before redistributing derived code | https://www.w3.org/TR/wcag-3.0/ ; https://github.com/Myndex/apca-w3/blob/master/LICENSE.md | M |

**Code-text interpretation (L).** Code is not "fluent body text": we scan it more than
we read it as prose. Its size is usually 12–16 px at weight 400. That puts the strict
APCA target at Lc 75–90 for default foreground, and around Lc 60 for content text.
Real palettes are well below this (§8): the median dark-scheme accent is |Lc| ≈ 52,
and the median `base03` comment colour is |Lc| ≈ 21. **Use APCA thresholds in tiers,
not as a single pass/fail.**

**Python.** No APCA package on PyPI (`apca-w3`, `apca`, `apcaw3` all absent, checked
2026-10-23). coloraide 8.13.1 does **not** ship APCA (`contrast` methods: `wcag21`,
`lstar` only in `ColorAll`). The coloraide docs show APCA as an example custom plugin.
We wrote a 15-line implementation from the constants (verified above, kept in the
harness). `wcag-contrast-ratio` is on PyPI, but `Color.contrast(bg, method='wcag21')`
does the same job.

---

## 4. Colour vision deficiency (CVD)

| Item | Value | Source | Conf. |
|---|---|---|---|
| Red–green CVD prevalence, N. European ancestry | ≈ **8 % of males, 0.4–0.5 % of females** | Birch 2012, "Worldwide prevalence of red-green color deficiency", JOSA A 29(3):313–320, doi:10.1364/JOSAA.29.000313 | H |
| Breakdown (males) | deuteranomaly ≈ 5 %, protanomaly ≈ 1 %, protanopia ≈ 1 %, deuteranopia ≈ 1 % | Birch 2012; Sharpe et al. 1999 in *Color Vision: From Genes to Perception* | M |
| Tritan (blue–yellow) | ≈ 1 in 10 000 or rarer (congenital); acquired forms are more common with age, cataract and diabetes | Sharpe et al. 1999; Wright 1952 | M |
| Prevalence elsewhere | Lower in some populations (≈ 4–6.5 % of East Asian males, ≈ 2–4 % of some African populations) | Birch 2012 | M |
| Dichromat simulation (full severity) | Brettel, Viénot & Mollon 1997, "Computerized simulation of color appearance for dichromats", JOSA A 14(10):2647–2655. Two half-planes; the reference method, and the right one for **tritan** | doi:10.1364/JOSAA.14.002647 | H |
| Fast dichromat simulation | Viénot, Brettel & Mollon 1999, "Digital video colourmaps for checking the legibility of displays by dichromats", Color Res. Appl. 24(4). Single 3×3 matrix; fine for protan/deutan, **poor for tritan** | doi:10.1002/(SICI)1520-6378(199908)24:4<243::AID-COL5>3.0.CO;2-3 | H |
| Anomalous trichromacy with severity | Machado, Oliveira & Fernandes 2009, "A physiologically-based model for simulation of color vision deficiency", IEEE TVCG 15(6):1291–1298. Severity 0–1; **use for protan/deutan with severity**; the authors say tritan results are less reliable | https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html | H |
| Simulator comparison | DaltonLens review: Brettel 1997 or Viénot 1999 for protan/deutan; Brettel 1997 for tritan; avoid "Coblis v1" | https://daltonlens.org/opensource-cvd-simulation/ | M |
| Pairs that collapse | **Protan/deutan**: red↔green, red↔brown/orange, green↔yellow/orange, blue↔purple/violet (the red component disappears), cyan↔grey/white, pink↔grey. Protans also see reds as **darker**, so red text on dark backgrounds loses contrast. **Tritan**: blue↔green, purple↔red/pink, yellow↔white/pink, orange↔red | Confusion lines; Brettel 1997. Demonstrated here: Tomorrow Night blue↔purple ΔEOK 0.073 → **0.017** under deutan (Viénot) | H (demo) / M (list) |

**Python libraries (checked by running them).**
- **coloraide 8.13.1**: `Color(c).filter('protan'|'deutan'|'tritan', amount=1.0, method='brettel'|'vienot'|'machado')`.
  Defaults are **vienot** for protan/deutan and **brettel** for tritan. **The output is in
  `srgb-linear`**: always add `.convert('srgb').fit('srgb')` before comparing or printing.
- **daltonlens** (PyPI `daltonlens`, numpy): `simulate.Simulator_Brettel1997`,
  `Simulator_Vienot1999`, `Simulator_Machado2009`, `Simulator_AutoSelect`; enum
  `simulate.Deficiency.PROTAN/DEUTAN/TRITAN`. Works on image arrays (H×W×3 uint8).
- **colorspacious 1.1.2**: `cspace_convert(rgb, {"name": "sRGB1+CVD", "cvd_type": "deuteranomaly", "severity": 100}, "sRGB1")`
  (Machado). Also `deltaE(a, b, input_space='sRGB1')` in CAM02-UCS. Unmaintained;
  `SyntaxWarning` on Python 3.14.

---

## 5. Categorical palettes: count, naming, and hue at low chroma

| Item | Value | Source | Conf. |
|---|---|---|---|
| Basic colour terms (English) | **11**: white, black, red, green, yellow, blue, brown, orange, pink, purple, grey. Of these, 8 are **chromatic** and usable as hue categories on a fixed background | Berlin & Kay 1969, *Basic Color Terms: Their Universality and Evolution* | H |
| Colours that are quickly distinguishable and nameable | About **5–10**. Healey: 7 colours worked for rapid search, when they were separated by name, linear separation and distance. Ware: about 6–12 categorical colours in practice | Healey 1996, "Choosing effective colours for data visualization", IEEE Vis '96; Ware, *Information Visualization* (4th ed. 2020) ch. 4 | M |
| Colour-naming model | Built from the XKCD colour survey (≈ 3.4 M names, 153 terms used). **Name distance** = Hellinger distance between two colours' name distributions; **saliency** = negative entropy of a colour's name distribution. Colours can be far apart in ΔE and still share a name (e.g. two "blue"s), which hurts categorical encoding | Heer & Stone 2012, "Color naming models for color selection, image editing and palette design", CHI '12, doi:10.1145/2207676.2208547 ; code (JS, "c3"): https://github.com/StanfordHCI/c3 | H (method) / M (counts) |
| Colorgorical | Scores palettes on **perceptual distance (ΔE00)**, **name difference** (Heer & Stone), **name uniqueness**, and **pair preference** (Schloss & Palmer). Discriminability rose with perceptual distance and name difference; aesthetic preference was a separate factor | Gramazio, Laidlaw & Schloss 2017, "Colorgorical: Creating discriminable and preferable color palettes for information visualization", IEEE TVCG 23(1), doi:10.1109/TVCG.2016.2598918 ; http://vrl.cs.brown.edu/color | H |
| Maximally distinct palettes | Greedy max–min ΔE in CIELAB; distinctness drops quickly after about 10 colours | Glasbey, van der Heijden, Toh & Gray 2007, "Colour displays for categorical images", Color Res. Appl. 32(4) | H |
| **Why hue is unreliable at low chroma** | Hue is only defined when chroma clearly exceeds the chromatic threshold. At text size, Δa* and Δb* JNDs are about 10–15 (line, 50 %) to 17–24 (80 %). A text colour with C* ≲ 15 (≈ OKLCH C ≲ 0.04) **cannot reliably be told apart from grey**, so its hue carries no information | Derived from §2; similar "hue undefined below C≈0.02–0.04" cut-offs are used in CSS Color 4 powerless-hue handling, https://www.w3.org/TR/css-color-4/#powerless | L |
| Hue sectors | For token categories, use **OKLCH hue bins anchored on basic colour terms**. Approximate centres for typical sRGB accents: red 25°, orange 55°, yellow 95°, green 140°, cyan 195°, blue 250°, purple 305°, pink/magenta 345°. Width differs per sector (cyan and yellow are narrow; blue is wide). Recommended "different category" rule: **hue-name differs, or Δh ≥ 30° with both C ≥ 0.06** | L, our engineering choice; calibrate with the Heer & Stone model if needed | L |

---

## 6. Weight and style as channels

| Effect | Evidence / number | Source | Conf. |
|---|---|---|---|
| Chromatic sensitivity is low-pass in spatial frequency; luminance sensitivity is band-pass, peaking around 3–5 c/deg. At text spatial frequencies (≈ 5–15 c/deg for strokes) **chromatic contrast is much less effective than luminance contrast** | Mullen 1985, "The contrast sensitivity of human colour vision to red–green and blue–yellow chromatic gratings", J. Physiol. 359:381–400 | H |
| Text that differs from its background only in colour (equiluminant) can be read when it is large, but **reading speed drops sharply for small characters** unless there is luminance contrast | Legge, Parish, Luebker & Wurm 1990, "Psychophysics of reading XI. Comparing color contrast and luminance contrast", JOSA A 7(10):2002–2010; Knoblauch, Arditi & Szlyk 1991, JOSA A 8(2) | H |
| Small-field tritanopia: blue–yellow discrimination drops for targets ≲ 20′ | Willmer & Wright 1945, Nature 156:119 | H |
| Thinner strokes need more contrast. APCA's lookup table raises the required Lc as weight drops (e.g. for the same Lc, 14 px needs weight 700 where 18 px needs 400). In practice, **one weight step (400→700) is worth about +15 Lc** at body sizes | APCA font lookup table, https://git.apcacontrast.com/documentation/APCA_in_a_Nutshell.html and https://www.myndex.com/APCA/ | M (pattern) / L (+15 estimate) |
| Antialiasing: grayscale AA blends partly covered stroke pixels with the background, so thin glyphs show **lower effective contrast and lower chroma** than the nominal colour. Bold text has more fully covered pixels, so its nominal colour is closer to what is perceived. Effect is strongest for 1 px strokes at low DPI | General rendering fact; Myndex discussion of "effective contrast"; Szafir 2018 line data (thinner = higher ND) | M |
| Irradiation: light text on a dark background looks bolder/heavier, and dark text on light looks thinner. APCA models this with different exponents per polarity, so light-on-dark needs **higher absolute** \|Lc\| for the same luminance pair | APCA constants (revTXT 0.62/revBG 0.65 vs normTXT 0.57/normBG 0.56) | H (model) |
| Italic | No reliable colour-perception data. Italic slightly thins strokes (some fonts use a lighter italic), so it reads as slightly lower contrast. Treat it as a **shape channel** only | L | L |

**Use in patterns (L).** Weight and italic are **redundant secondary channels**, not
replacements for colour separation. Bold adds roughly one "notch" of salience and
partly makes up for low-contrast hues (yellow on light, blue on dark). It cannot
recover hue information that is below chroma threshold.

---

## 7. Appearance effects: Helmholtz–Kohlrausch, contrast, polarity

| Effect | Description and size | Source | Conf. |
|---|---|---|---|
| Helmholtz–Kohlrausch (H-K) | At equal luminance, saturated colours look **brighter** than grey. Strongest for blue, magenta and red, weakest for yellow. The size can reach the equivalent of **≈ 5–15 L*** units for highly saturated sRGB blues and reds. APCA, WCAG and OKLab L all **ignore** it, so a saturated blue or red can look more prominent than its Lc suggests | Fairchild & Pirrotta 1991, "Predicting the lightness of chromatic object colors using CIELAB", Color Res. Appl. 16(6); Nayatani 1997 VCC model; Hellwig & Fairchild 2022 (CAM16 H-K extension), Color Res. Appl. 47(5) | M |
| Hunt effect | Colourfulness increases with luminance; on dark themes with a dim display, chroma looks lower | Hunt 1952; Fairchild, *Color Appearance Models* 3rd ed. 2013 | H |
| Simultaneous contrast / induction | The surround shifts perceived colour away from itself: lightness, plus a hue shift toward the surround's complement. On a coloured background (e.g. Solarized base03 #002b36), cyan/blue text looks **less** chromatic and orange/red looks **more** chromatic. Small targets are affected more | Fairchild 2013 ch. 6; Szafir 2018 "isolation assumption" | M |
| Dark vs light background | Dark backgrounds: text chroma looks higher (and H-K is stronger in relative terms), halation and blooming of light text, irradiation. Light backgrounds: yellow, cyan and light-green text often fail contrast (high Y), and chroma looks lower. APCA's asymmetric exponents reflect polarity | APCA; Piepenbrock et al. 2013 "Positive display polarity is advantageous…", Ergonomics 56(7) (positive polarity better for small text acuity) | M |
| Abney effect | Mixing with white shifts perceived hue, mainly blue → purple. CIELAB shows this error; OKLab partly corrects it | Ottosson 2020; Fairchild 2013 | H |
| Bezold–Brücke | Hue shifts with luminance level (except at invariant hues ≈ 475, 505, 575 nm) | Fairchild 2013 | H |

**Use (L).** For pattern salience ranking, compute "effective lightness" as OKLab L
(or CIELAB L*) plus an optional H-K correction, using coloraide's
`helmlab`/Hellwig-type models or a simple `L + k·C` with `k ≈ 0.1–0.25` that depends on
hue. Use it **only for ordering prominence**, never for legibility pass/fail.

---

## 8. Palette corpora

| Corpus | URL | Format | Count (2026-10-23) | Licence | Notes |
|---|---|---|---|---|---|
| tinted-theming/schemes (base16 / base24) | https://github.com/tinted-theming/schemes | YAML: `system`, `name`, `author`, `variant` (dark/light), `palette: {base00..base0F}` (base24 adds `base10..base17`) | **base16: 361 files** (254 dark + 106 light parse with `variant`), **base24: 210**, tinted8: 11 | MIT (repo); per-scheme authors credited | Spec: https://github.com/tinted-theming/home/blob/main/styling.md. base00 = bg, base03 = comments, base05 = fg, base08–0F = accents with semantic roles. Default branch `spec-0.11` |
| iTerm2-Color-Schemes | https://github.com/mbadolato/iTerm2-Color-Schemes | `schemes/*.itermcolors` (plist), `windowsterminal/*.json` (`black…brightWhite`, `background`, `foreground`, `cursorColor`, `selectionBackground`), plus ghostty, kitty, alacritty, Xresources, `yaml/` | **≈ 854 schemes** (`schemes/`, `windowsterminal/`, `kitty/` each 854; `yaml/` 393) | Repo MIT; `licenses.yml` gives a per-scheme SPDX: 580 unknown, 202 MIT, 18 **nonfree**, 16 GPL-2.0+, 9 Apache-2.0… | Best source of **terminal 16-colour** palettes. **Exclude `nonfree`** and treat `unknown` as test-only (do not redistribute) |
| Gogh | https://github.com/Gogh-Co/Gogh | `themes/*.yml`: `name`, `author`, `variant`, `color_01..color_16` (ANSI 0–15), `background`, `foreground`, `cursor`. Aggregates: `data/themes.json`, `themes.csv`, `wcag.json` | **≈ 1251 themes** | MIT / Apache-2.0 dual (`LICENSE-MIT`, `LICENSE-APACHE`) | `data/themes.json` loads in one request; `wcag.json` already has contrast data |
| Windows Terminal schemes | Same as iTerm2 `windowsterminal/`; built-ins documented at https://learn.microsoft.com/windows/terminal/customize-settings/color-schemes | JSON (as above) | — | — | No separate corpus needed |

**Baseline stats from the base16 corpus (computed here, H).** Accents are base08–base0E
against base00.

| Variant | n | median accent \|Lc\| (p10/p30/p50/p70/p90) | base03 "comment" \|Lc\| (p10/…/p90) | mean # of 7 accents below Lc 45 | min accent-pair ΔEOK (p10/…/p90) |
|---|---|---|---|---|---|
| dark | 254 | 34 / 46 / **52** / 56 / 66 | 0 / 14 / **21** / 27 / 39 | 2.5 | 0.000 / 0.045 / **0.065** / 0.080 / 0.116 |
| light | 106 | 43 / 54 / **61** / 67 / 76 | 30 / 36 / **48** / 57 / 71 | 1.2 | 0.000 / 0.050 / **0.067** / 0.085 / 0.116 |

Implications:
1. A strict "every accent ≥ Lc 60" rule rejects most dark palettes.
2. base03 is mostly a **dim/structure** colour, not a readable comment colour, on dark
   schemes.
3. The closest pair of accents in a typical palette (ΔEOK ≈ 0.065) is **below** the
   text-size distinguishability estimate of §2. Every palette has some pairs that look
   alike at code size, so the mapping algorithm must choose which pairs to separate.

Example (Tomorrow Night, dark): fg Lc −70.9, comment −44.4, red **−35.5**, orange
−51.4, yellow −73.7, green −61.5, cyan −59.9, blue −47.9, purple −47.9, brown −28.8.
Closest pairs: comment/blue ΔEOK 0.059; blue/purple 0.073 (deutan **0.017**).

---

## Recommended metrics (validation harness)

Dependencies: `uv run --with coloraide --with pyyaml`. Optionally `daltonlens` to
cross-check CVD. All colours are sRGB hex. `bg` is the palette background.

```python
from coloraide import Color
# CIELAB D65 for the Szafir model; coloraide 'lab' is D50, so use 'lab-d65'.
lab = lambda c: Color(c).convert('lab-d65').coords()
oklch = lambda c: Color(c).convert('oklch').coords()          # [L 0-1, C ~0-0.37, h deg]
de_ok = lambda a, b: Color(a).delta_e(b, method='ok')
de_00 = lambda a, b: Color(a).delta_e(b, method='2000')
wcag  = lambda fg, bg: Color(fg).contrast(bg, method='wcag21')
cvd   = lambda c, k: Color(c).filter(k, method=('brettel' if k == 'tritan' else 'machado')
                                     ).convert('srgb').fit('srgb').to_string(hex=True)

def nd_line(p, s):   # Szafir 2018 Eqs 14-16; p in 0..1, s = stroke thickness (deg)
    return [p / (c - k / s) for c, k in ((0.0742, .0023), (0.0623, .0015), (0.0425, .0009))]

def de_text(a, b, p=0.8, s=0.1):   # Szafir 2018 Eq 4; >= 1 means p of viewers see a difference
    (l1, a1, b1), (l2, a2, b2) = lab(a), lab(b)
    nL, na, nb = nd_line(p, s)
    return (((l1 - l2) / nL)**2 + ((a1 - a2) / na)**2 + ((b1 - b2) / nb)**2) ** .5

def apca_lc(text, bg):   # APCA-W3 0.0.98G-4g; verified against reference values
    def Y(h):
        h = h.lstrip('#'); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
        y = .2126729 * r**2.4 + .7151522 * g**2.4 + .0721750 * b**2.4
        return y if y > .022 else y + (.022 - y)**1.414
    t, b = Y(text), Y(bg)
    if abs(b - t) < .0005: return 0.0
    if b > t:
        s = (b**.56 - t**.57) * 1.14; return 0.0 if s < .1 else (s - .027) * 100
    s = (b**.65 - t**.62) * 1.14; return 0.0 if s > -.1 else (s + .027) * 100
```

### Checks and thresholds

`|Lc|` = `abs(apca_lc(fg, bg))`. All thresholds are **parameters**. The defaults below
come from the sections above. Pass levels: *strict* / *default* / *floor*.

| Check | Default rule | Rationale |
|---|---|---|
| **L1 Default foreground legible** | \|Lc\| ≥ 75 strict / **≥ 60** default / ≥ 45 floor; also WCAG ≥ 4.5 | APCA body/content; WCAG AA |
| **L2 Token (accent) legible** | \|Lc\| ≥ 60 strict / **≥ 45** default / ≥ 35 floor. If the role is drawn bold, lower each tier by 10–15 | Corpus median is about 52 on dark; APCA Lc 45 = large/heavy text |
| **L3 De-emphasised text (comments, docs)** | \|Lc\| ≥ 45 strict / **≥ 30** default (APCA "spot-readable") / ≥ 20 floor; and **at least 10 Lc below** fg | Comments must stay readable but sit visibly lower in the hierarchy |
| **L4 Non-text marks (rulers, whitespace, line numbers dim)** | \|Lc\| ≥ 15 | APCA Lc 15 |
| **D1 Two token colours distinguishable (normal weight)** | `de_text(a, b, p=0.8, s=0.1) ≥ 1.0` (reliable); `de_text(a, b, p=0.5, s=0.1) ≥ 1.0` (just noticeable, the floor). Cross-check: `de_ok ≥ 0.10` reliable / `≥ 0.06` floor; `de_00 ≥ 15` reliable / `≥ 10` floor | Szafir 2018 line model at code-stroke scale; ΔE00 ≈ 126 × ΔEOK near threshold |
| **D2 Categorically different** (pattern says "different kinds") | D1 passes **and** (hue-name differs **or** \|ΔL_ok\| ≥ 0.12). Hue-name is valid only when both colours have OKLCH C ≥ 0.04; otherwise treat the colour as "grey" | Heer & Stone / Colorgorical: name difference predicts discriminability |
| **D3 Same family / related** (pattern says "variant of") | same hue-name, \|Δh\| ≤ 25°, and D1 at p = 0.5 passes (visible but related) | — |
| **D4 Hue carries meaning** | OKLCH C ≥ **0.04** (at least about 1 text-size a/b JND from grey); C ≥ 0.06 for reliable hue naming | §5 derivation |
| **C1 CVD robustness** | Repeat D1 and D2 on `cvd(·, 'deutan')` and `cvd(·, 'protan')` (full severity, Machado or Viénot), and on `cvd(·, 'tritan')` with Brettel. Require D1 at p = 0.5 for pairs that the pattern marks as **must-differ**. Report collapsed pairs, but don't fail the palette on them | 8 % of males are red–green CVD; tritan is rare |
| **S1 Salience order** | Rank roles by \|Lc\| (and optionally H-K-adjusted OKLab L + chroma). The pattern's emphasis order must hold with margins of **≥ 7.5 Lc** between adjacent tiers | Roughly half of the APCA tier spacing (15) |
| **B1 Background tints** (selection, current line, diff bg) | ΔEOK(bg, tint) ≥ 0.02 (visible as an area, CSS JND), and every role in L1–L3 still passes on the tint | Large-area JND; text must stay legible on highlights |

**Scoring.** For each pattern, compute pass/fail per check at each tier. A palette
"supports" a pattern at the highest tier where every required check passes. When it
only reaches *floor*, the mapper should add weight or style redundancy (§6) to the
failing pairs, or merge roles the palette cannot separate.

---

## Terms

- **ΔE (Delta E)**: distance between two colours in a colour space. ΔE*ab (1976) is
  Euclidean CIELAB; ΔE00 is CIEDE2000; ΔEOK is Euclidean OKLab (range about 0–1);
  ΔE_{p,s} is Szafir's size-normalised CIELAB distance.
- **JND (just-noticeable difference)**: the difference noticed in a criterion fraction
  of trials (usually 50 %). **ND(p, s)**: the difference noticed by p % of viewers for a
  mark of size s.
- **Visual angle (°)**: size on the retina. 1° ≈ 10.5 mm at 60 cm, ≈ 40 px on a
  ~100 dpi display. 1′ (arcminute) = 1/60°.
- **Lightness (L*, L_ok)**: perceived brightness relative to white. **Luminance (Y)**:
  physical, linear-light value used by WCAG and APCA.
- **Chroma (C)**: colourfulness relative to a grey of the same lightness (OKLCH C,
  CIELAB C*). **Saturation** is chroma relative to lightness. **Hue (h)**: angle in a/b.
- **Contrast ratio (WCAG)**: (Y1 + 0.05)/(Y2 + 0.05), range 1–21.
- **Lc (lightness contrast, APCA)**: perceptual contrast value, about −108 to +106.
  Sign gives polarity (negative = light text on dark). Thresholds 90/75/60/45/30/15.
- **Polarity**: dark-on-light (positive/normal) vs light-on-dark (negative/reverse).
- **CVD (colour vision deficiency)**. Protan = L-cone, deutan = M-cone, tritan = S-cone.
  "-opia" means the cone type is missing (dichromat); "-omaly" means it is shifted
  (anomalous trichromat, has a severity).
- **Confusion line**: set of colours a dichromat cannot tell apart.
- **Basic colour term**: one of Berlin & Kay's 11 monolexemic, general-purpose colour
  names. **Name distance**: Heer & Stone's Hellinger distance between name
  distributions.
- **H-K effect**: saturated colours look brighter than their luminance predicts.
  **Hunt effect**: colourfulness increases with luminance. **Abney effect**: hue shifts
  when white is added. **Simultaneous contrast**: the surround shifts perceived colour
  away from itself.
- **Spatial frequency (c/deg)**: cycles per degree. Fine text strokes are high-frequency,
  where chromatic sensitivity is low.
- **Gamut mapping / `fit`**: bringing an out-of-gamut colour into sRGB. Needed after CVD
  simulation and OKLCH edits.

## Verified library facts (2026-10-23)

- coloraide **8.13.1**:
  - `Color.delta_e` methods: `76, 94, cmc, 2000, hyab, ok, itp`. `ColorAll` (from
    `coloraide.everything`) adds `cam16, cam02, hct, jz, 99o, helmlab`.
  - `contrast`: `wcag21` (plus `lstar` in `ColorAll`). **No APCA.**
  - Filters: `protan`, `deutan`, `tritan` with `method` = `brettel`, `vienot` or
    `machado`. Defaults are vienot (protan/deutan) and brettel (tritan). Output is
    srgb-linear.
  - Spaces include `oklab, oklch, oklrab, oklrch, okhsl, okhsv, lab, lab-d65, cam16-ucs, hct`.
- daltonlens: `Simulator_Brettel1997`, `Simulator_Vienot1999`, `Simulator_Machado2009`,
  `Simulator_AutoSelect`, `Deficiency`.
- colorspacious 1.1.2: `cspace_convert`, `deltaE` (CAM02-UCS), CVD via `sRGB1+CVD`.
- APCA: no PyPI package. Our implementation matches the apca-w3 reference values exactly.
