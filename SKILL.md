---
name: SAAA-bilog-calibration
description: 縣市學生能力檢測 (SAAA) BILOG-MG IRT 試題參數估計 Skill，支援 1PL、2PL、3PL 三種模型。自動化執行學生作答與答案/向度 Excel 預檢、生成 DAT/OMITKEY/BLM 原生檔、呼叫 BLM1/BLM2/BLM3 執行校準、解析 PAR/PH1 輸出、依模型產出不同欄位規格的公務標準 IRT 參數表與 CTT/IRT 詳細報表。
---

# SAAA-bilog-calibration 縣市學生能力檢測 BILOG IRT 試題參數估計（1PL / 2PL / 3PL）

Use `scripts/easy_bilog_runner.R` as the only calibration engine. Treat its behavior and outputs as authoritative for this Skill.

## Non-negotiable execution rules

- Run the bundled R script for validation, preparation, calibration, parsing, and report generation.
- Do **not** reproduce or substitute the calibration logic in Python, JavaScript, spreadsheets, or an LLM calculation.
- Do **not** simulate BILOG-MG parameters when BILOG executables or PAR/PH1 outputs are unavailable.
- If `Rscript` is unavailable, stop and report that the R runtime is required.
- If required R packages are missing, report the package names from the script error; do not silently switch engines.
- If BILOG-MG is unavailable, use `prepare` mode and return the native files for external execution.
- Use the same response and answer workbooks plus the same output directory when later parsing external BILOG results.

## Model selection — Agent must ask before calibrating

**Model selection is an analytical decision. The Agent must never silently default to any model.**

Follow this decision logic strictly:

| User says | Agent action |
| :--- | :--- |
| Explicitly says `1PL`, `2PL`, or `3PL` | Execute immediately with the specified model |
| Says "compare models" or "which model fits" | Run all three (1PL → 2PL → 3PL), then compare and report |
| Says "run BILOG" or any calibration request **without specifying a model** | **Stop. Ask: "這次要跑 1PL、2PL 還是 3PL？" Before the user answers, do NOT start calibration and do NOT assume 3PL.** |

The R script also enforces this at the code level: calling `run_bilog_auto()` without `--model` raises an error (`尚未指定 IRT 模型`). This is the second layer of protection in case the Agent forgets to ask.

| Model | NPARM | Estimated parameters | Fixed parameters | Official table columns |
| :--- | :---: | :--- | :--- | :--- |
| **3PL** | 3 | a (per-item), b (per-item), c (per-item) | — | 題號, a, b, c, 點二相關 |
| **2PL** | 2 | a (per-item), b (per-item) | c = 0 (not shown in official table) | 題號, a, b, 點二相關 |
| **1PL** | 1 | b (per-item) | a = common slope, c = 0 (not per-item) | 題號, b, 點二相關 |

**Output schema contract**: Fixed/constrained parameters must never appear as estimated values in the official table. The 16-column detailed report clearly labels each fixed parameter.

## Workflow

1. Identify the two required Excel inputs:
   - student response/filter workbook;
   - answer/dimension workbook.
2. Determine whether the user supplied explicit exam year, subject code, model, output directory, or BILOG directory. Otherwise allow the R script to infer year/subject from the response filename; default model is `3PL`.
3. Verify that `Rscript` is available before execution.
4. Select the execution mode using the decision table in `references/execution-modes.md`.
5. Run `scripts/easy_bilog_runner.R` with the original files and chosen model.
6. Inspect the process exit status and `BILOG_RUN_SUMMARY.txt`.
7. If BILOG stages fail, inspect `BLM1.log`, `BLM2.log`, or `BLM3.log`; follow `references/troubleshooting.md`.
8. When status is `completed`, return the official parameter workbook (schema varies by model) and the detailed workbook, then interpret flagged items using `references/interpretation.md`.
9. When status is `prepared_only`, return the DAT, OMITKEY, and BLM files and explain that native BILOG-MG must be run externally before `parse` mode.

## Commands

Default (3PL, auto mode):

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx
```

2PL model:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=2PL
```

1PL model:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=1PL
```

Prepare-only (no BILOG required):

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=2PL --mode=prepare
```

Explicit native run with path:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=3PL --mode=run --bilog-dir="C:/Program Files/BILOGMG"
```

Parse externally-produced PAR/PH1:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=3PL --mode=parse --output-dir=RESULTS
```

Override inferred metadata:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --year=115 --subject=M5 --model=2PL
```

Prefer quoting paths that contain spaces. The BILOG directory can also be supplied through the `BILOGMG_HOME` environment variable.

## Model comparison workflow

When the user asks to compare models or find the best-fitting model:

1. Run 1PL: `--model=1PL`
2. Run 2PL: `--model=2PL`
3. Run 3PL: `--model=3PL`
4. Collect results from each model's `BILOG_RUN_SUMMARY.txt` and detailed workbook.
5. Compare using information available in BILOG PAR/PH1 output:
   - parameter stability (SE magnitudes for a, b, c);
   - number of flagged items per model;
   - 3PL: are c values stable (c > 0.35 = unstable guessing estimate)?
   - 2PL vs 1PL: do per-item a values vary meaningfully?
   - sample size: 3PL requires N > 1000 for stable c; 2PL requires N > 500; 1PL can work with smaller samples.
6. Report recommended model with explicit evidence from BILOG outputs. Do not recommend based on appearance only.

## Mode policy

Use `auto` as the default. It runs BILOG only when all three BLM executables are available; otherwise it prepares native files. It intentionally does **not** auto-parse an existing PAR file because that file may be stale.

Use `parse` only when the PAR/PH1 outputs are known to belong to the prepared job. The R script records MD5 hashes of both Excel inputs in `BILOG_RUN_SUMMARY.txt` and rejects a parse operation when a prior summary proves that the inputs differ.

See `references/execution-modes.md` for the full decision table.

## Input and output contract

Read `references/input-output-contract.md` whenever workbook structure, item numbering, missing values, filenames, or report columns matter.

Important invariants:

- Treat `9` as missing response data for BILOG/CTT purposes.
- Exclude blank answers and `不予計分` items from calibration.
- Preserve original item numbers in all reports after exclusions.
- Require response columns named `Q<original item number>` for every scorable item.
- The official IRT workbook uses BISERIAL (from PH1) as the point-biserial correlation to match historical official practice.
- Fixed/constrained parameters are **never** included in the official parameter table as if they were estimated.
- The detailed workbook provides both PBIS (PEARSON) and BIS (BISERIAL) diagnostics.
- Output directory and filenames include the model tag (e.g., `115_M05_2PL_IRT參數.xlsx`).

## Result interpretation

Read `references/interpretation.md` before explaining item quality. Treat the bundled quality rules as review heuristics rather than universal pass/fail standards.

Quality flags vary by model:
- **3PL**: a < 0.3, |b| > 5, c > 0.5, BIS < 0
- **2PL**: a < 0.3, |b| > 5, BIS < 0
- **1PL**: |b| > 5, BIS < 0

For each flagged item, report:

- original item number;
- triggering metric and value;
- applicable rule;
- a concise interpretation;
- whether manual item/content review is recommended.

Do not invent interpretations for missing PAR/PH1 statistics.

## Failure handling

Read `references/troubleshooting.md` when execution fails.

Always distinguish among:

- R runtime/package failure;
- workbook/schema/input failure;
- missing BILOG executables;
- BLM stage non-zero exit status;
- missing/malformed PAR;
- missing/malformed PH1;
- prepare/parse provenance mismatch.

Do not report calibration as successful unless the R runner returns completed status and the expected report files exist.
