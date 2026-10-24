# Timed search task: one subject, 36 trials (2026-10-23)

Source: `out/task_results.json` (raw) and `out/task_results.csv` (derived). Design:

- 3 languages (python, typescript, rust) × 3 tasks (definitions, exits, literals) × 4 conditions.
- Latin square over 4 snippets per language.
- 4 creator-assigned palettes (Gruvbox, Monokai, Kanagawa, Zenburn).

| Condition | Median ms/target | Recall | False alarms | F1 | IES (ms/target ÷ F1) | Mean IES rank (1 = best) |
|---|---|---|---|---|---|---|
| plain | 3130 | 0.65 | 11 | 0.62 | 6844 | 3.22 |
| landmark | 2422 | 0.64 | 11 | 0.66 | 3240 | 2.11 |
| label | 4437 | 0.74 | 6 | 0.71 | 4452 | 2.56 |
| **reader** | 3192 | **0.85** | **5** | **0.84** | 4097 | 2.11 |

- **Reader is the most accurate:** highest recall and fewest false alarms.
- **Landmark is the fastest but misses the most:** definition recall was 0.36.
- **On speed and accuracy combined (IES), reader and landmark tie,** and both beat plain.
  Reader beats plain in 7 of 9 blocks.
- **No learning effect:** Spearman ρ(trial order, time) = 0.01.
- **Not statistically significant:** one subject and 9 blocks; Friedman p = 0.22 on IES and
  0.053 on raw speed. Treat this as a sanity check: nothing contradicts the parse-load
  metric, and accuracy favours reader.
