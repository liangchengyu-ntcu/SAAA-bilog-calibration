# Input/output contract

## Student response workbook

Use the first worksheet. For every scorable item, require a column named `Q` plus the **original item number**, for example `Q1`, `Q2`, `Q18`.

Recognized control columns:

- `缺考`: absent flag;
- `無效`: invalid-record flag;
- `總流水號`: participant serial identifier.

When both `缺考` and `無效` exist, retain only rows where both values equal zero. If either control column is absent, do not filter on these flags and surface the R warning.

Allowed item-response values are `0`, `1`, `9`, blank, or NA. Blank/NA is normalized to `9`. Other values are hard input errors.

When `總流水號` ends in six digits, use that suffix as the BILOG ID. Otherwise use the original source-row numbering as six digits. IDs must be unique.

## Answer/dimension workbook

Choose the first worksheet whose name contains `答案`; otherwise use the first worksheet.

Prefer an answer column matching the subject code, treating forms such as `M5` and `M05` as equivalent. The current R workflow retains a compatibility fallback to column 2 (or the only column) and emits a warning when no exact subject column exists. Surface this warning rather than hiding it.

A row is scorable when its selected answer is not blank/NA and is not `不予計分`. The answer row position is the original item number. Do not renumber remaining items after exclusions.

For dimension metadata, prefer:

1. sheet `評量指標代`;
2. sheet `向度`;
3. otherwise the second worksheet.

If `題號` is absent, use sequential row numbers. Prefer subject-specific dimension columns. The grade fallback mapping is:

- 3 → `三年級`
- 4 → `四年級`
- 5 → `五年級`
- 6 → `六年級`
- 7 → `七年級`
- 8 → `八年級`

## Metadata inference

Infer subject/grade from a filename token matching letters followed by digits, such as `M5`, `M05`, or `S5`.

Infer the exam year from a three-digit filename prefix followed by `_` or `-`, such as `115_`.

Use `--subject` and `--year` to override inference.

## Native BILOG files

- `<SUBJECT_PAD>_data.dat`: six-digit ID, one space, then N response characters.
- `OMITKEY.dat`: seven leading spaces plus N nines.
- `<YEAR><SUBJECT_PAD>.BLM`: native BILOG job file.
- `<SUBJECT_PAD>_IP.PAR`: expected item parameter output.
- `<YEAR><SUBJECT_PAD>.PH1`: expected phase-1 statistics output.
- `<SUBJECT_PAD>_SCORE.SCO`: expected score output when produced by BILOG.
- `BLM1.log`, `BLM2.log`, `BLM3.log`: native execution logs when `run` mode is used.
- `BILOG_RUN_SUMMARY.txt`: status, paths, metadata, counts, and input MD5 hashes.

## Reports

Official workbook: `<YEAR>_<SUBJECT_PAD>_IRT參數.xlsx`.

It must contain exactly five columns:

1. normalized subject/item-number column;
2. `鑑別度(a)`;
3. `難度(b)`;
4. `猜測度(c)`;
5. `點二相關`.

Detailed workbook: `<SUBJECT>_BILOG_3PL_試題參數總表.xlsx`.

It includes original item number, standard answer, P, dimensions, a/b/c, PBIS, BIS, CITC, standard errors, and quality flags. A UTF-8 CSV copy is also produced.
