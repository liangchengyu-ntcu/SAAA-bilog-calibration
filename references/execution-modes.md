# Execution modes

## Decision table

| Mode | Use when | BILOG EXE required | Behavior |
|---|---|---:|---|
| `auto` | Default | Conditional | Run if BLM1/2/3 exist; otherwise prepare only |
| `prepare` | BILOG cannot run in the current environment | No | Validate inputs and create DAT, OMITKEY, BLM, and summary |
| `run` | Windows host has BILOG-MG | Yes | Prepare, run BLM1/2/3, parse outputs, write reports |
| `parse` | BILOG was run externally | No | Revalidate inputs, verify prior input provenance when available, parse PAR/PH1, write reports |

## Auto-mode safety rule

`auto` never consumes an existing PAR file automatically. Existing PAR files may be stale or belong to a different preparation. If BILOG executables are unavailable, `auto` ends as `prepared_only`.

Use `parse` explicitly after an external native BILOG run.

## Prepare → external BILOG → parse

1. Run `--mode=prepare --output-dir=RESULTS`.
2. Keep `DATA.xlsx`, `ANSWERS.xlsx`, and `RESULTS/BILOG_RUN_SUMMARY.txt` together.
3. Run the generated `.BLM` job with native BILOG-MG on Windows so that the expected `.PAR` and `.PH1` files are written into `RESULTS`.
4. Run `--mode=parse --output-dir=RESULTS` with the same two Excel inputs.
5. The R runner compares their MD5 hashes against the prior summary when those hashes are present.

## Native run prerequisites

A `run` requires all of:

- Windows-compatible native BILOG-MG installation;
- `BLM1.EXE`;
- `BLM2.EXE`;
- `BLM3.EXE`.

Supply the directory using `--bilog-dir=...` or `BILOGMG_HOME`. The default is `C:/Program Files/BILOGMG`.
