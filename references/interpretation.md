# Interpretation rules

## Parameter fields

- `a`: BILOG 3PL discrimination parameter from PAR.
- `b`: BILOG 3PL difficulty parameter from PAR.
- `c`: BILOG 3PL guessing parameter from PAR.
- `PBIS`: PH1 `PEARSON` item-total statistic. Use this value for the official point-biserial field and the negative-correlation quality rule.
- `BIS`: PH1 `BISERIAL` statistic. Keep this as a separate diagnostic and do not relabel it as point-biserial.
- `CITC`: corrected item-total correlation computed in R from the scored response matrix with `9` treated as missing.
- `P`: mean scored response computed in R with `9` treated as missing.

## Review heuristics

The bundled workflow flags an item when any of these conditions hold:

- `a < 0.3`: low discrimination;
- `abs(b) > 5`: extreme estimated difficulty;
- `PBIS < 0`: negative point-biserial relationship.

Treat these as operational screening rules for manual review, not universal psychometric pass/fail cutoffs.

## Reporting flagged items

For each flagged item:

1. identify the original item number;
2. show the exact triggering parameter value;
3. name the triggered rule;
4. explain the practical concern in one or two sentences;
5. recommend item/content review where appropriate.

Consider P, CITC, standard errors, and BIS as supporting diagnostics when they are available, but do not override the configured flag logic unless the user explicitly asks for a different standard.

## Missing PH1

If PH1 is missing or malformed, PBIS/BIS may be NA. State that limitation. Do not infer point-biserial values from another metric.

## Unscored items

Blank answers and `不予計分` rows are excluded. All report references must retain original item numbers; for example, a calibrated sequence may be 1, 2, 4, 5 rather than 1, 2, 3, 4.
