# Troubleshooting

## Rscript not found

The Skill cannot execute calibration without an R runtime. Report the missing runtime and do not replace the workflow with Python.

## Missing R packages

The bundled script requires:

- `readxl`
- `writexl`

Report the exact missing package error. On a user-controlled R installation, the normal installation command is:

```r
install.packages(c("readxl", "writexl"))
```

Do not silently install packages unless the user or execution environment permits it.

## Workbook/schema errors

Common hard failures include:

- fewer than two scorable items;
- fewer than three valid students;
- missing `Q<item>` columns;
- response values outside `0`, `1`, `9`, blank, or NA;
- duplicate six-digit IDs;
- filename metadata that cannot be inferred without `--year` or `--subject`.

Use the error text from the R runner as the primary diagnosis.

## BILOG executables missing

If `run` was explicitly requested, all three native executables must exist in the configured BILOG directory. If they are unavailable, either correct `--bilog-dir` / `BILOGMG_HOME` or use `prepare` for an external run.

## BLM stage failure

The R runner executes BLM1, BLM2, and BLM3 sequentially. A non-zero status is a hard failure. Inspect the corresponding log:

- `BLM1.log`
- `BLM2.log`
- `BLM3.log`

Do not claim completion after a failed stage.

## PAR missing or malformed

PAR is required to produce a/b/c reports. If it is absent, the calibration is not complete. If parsing yields fewer item records than expected, verify that the PAR belongs to the generated BLM job and that the native run completed normally.

## PH1 missing or malformed

The workflow can still parse PAR, but PBIS/BIS values will be unavailable. The official point-biserial column will therefore be missing/NA. Surface this limitation.

## Parse provenance mismatch

`prepare` records MD5 hashes of the response and answer workbooks. During `parse`, if an existing `BILOG_RUN_SUMMARY.txt` contains hashes that differ from the supplied files, the R runner stops. Use the exact workbooks that generated the native BILOG job, or prepare a fresh job in a new output directory.

If no prior summary exists, parsing can continue with a warning because provenance cannot be cryptographically verified.
