---
name: SAAA-bilog-calibration
description: 縣市學生能力檢測 (SAAA) BILOG-MG 3PL 試題參數估計與品質診斷專用 Skill。自動化執行學生作答與答案/向度 Excel 預檢、生成標準 DAT/OMITKEY/BLM 原生檔、呼叫 BLM1/BLM2/BLM3 執行校準、解析 PAR/PH1 輸出、產出公務標準五欄 IRT 參數表與 16 欄 CTT/IRT 詳細報表。
---

# SAAA-bilog-calibration 縣市學生能力檢測 bilog 試題參數估計

Use `scripts/easy_bilog_runner.R` as the only calibration engine. Treat its behavior and outputs as authoritative for this Skill.

## Non-negotiable execution rules

- Run the bundled R script for validation, preparation, calibration, parsing, and report generation.
- Do **not** reproduce or substitute the calibration logic in Python, JavaScript, spreadsheets, or an LLM calculation.
- Do **not** simulate BILOG-MG parameters when BILOG executables or PAR/PH1 outputs are unavailable.
- If `Rscript` is unavailable, stop and report that the R runtime is required.
- If required R packages are missing, report the package names from the script error; do not silently switch engines.
- If BILOG-MG is unavailable, use `prepare` mode and return the native files for external execution.
- Use the same response and answer workbooks plus the same output directory when later parsing external BILOG results.

## Workflow

1. Identify the two required Excel inputs:
   - student response/filter workbook;
   - answer/dimension workbook.
2. Determine whether the user supplied explicit exam year, subject code, output directory, or BILOG directory. Otherwise allow the R script to infer year/subject from the response filename.
3. Verify that `Rscript` is available before execution.
4. Select the execution mode using the decision table in `references/execution-modes.md`.
5. Run `scripts/easy_bilog_runner.R` with the original files.
6. Inspect the process exit status and `BILOG_RUN_SUMMARY.txt`.
7. If BILOG stages fail, inspect `BLM1.log`, `BLM2.log`, or `BLM3.log`; follow `references/troubleshooting.md`.
8. When status is `completed`, return the official five-column workbook and the detailed workbook, then interpret flagged items using `references/interpretation.md`.
9. When status is `prepared_only`, return the DAT, OMITKEY, and BLM files and explain that native BILOG-MG must be run externally before `parse` mode.

## Commands

Default behavior:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx
```

Explicit native run:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=run --bilog-dir="C:/Program Files/BILOGMG"
```

Prepare files without executing BILOG:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=prepare --output-dir=RESULTS
```

Parse PAR/PH1 produced externally:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=parse --output-dir=RESULTS
```

Override inferred metadata when necessary:

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --year=115 --subject=M5
```

Prefer quoting paths that contain spaces. The BILOG directory can also be supplied through the `BILOGMG_HOME` environment variable.

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
- Keep the official IRT workbook at exactly five columns: item number, a, b, c, BIS (from PH1 BISERIAL to match historical official practice).
- The 16-column detailed workbook provides both PBIS (PEARSON) and BIS (BISERIAL) diagnostics.

## Result interpretation

Read `references/interpretation.md` before explaining item quality. Treat the bundled quality rules as review heuristics rather than universal pass/fail standards.

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
