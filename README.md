# bilog-calibration

> **Language / 語言**：[English](#english) | [繁體中文](#繁體中文)

---

## English

### Overview

`bilog-calibration` is an **AI Agent Skill** that automates BILOG-MG 3PL Item Response Theory (IRT) calibration workflows.  
It is compatible with Google Antigravity, OpenAI GPTs, Codex, and other Agent platforms.

The skill uses a single authoritative R-based engine (`scripts/easy_bilog_runner.R`) that:

- Validates student-response and answer/dimension Excel workbooks
- Prepares native BILOG-MG input files (`.dat`, `OMITKEY.dat`, `.BLM`)
- Executes BLM1 → BLM2 → BLM3 when BILOG-MG is installed
- Parses PAR and PH1 outputs from an external run
- Produces the official five-column IRT parameter workbook and a detailed CTT/IRT diagnostic report

### Requirements

| Dependency | Required | Notes |
| :--- | :---: | :--- |
| **R ≥ 4.2** | ✅ Yes | Must be available as `Rscript` on the system PATH |
| **readxl** R package | ✅ Yes | `install.packages("readxl")` |
| **writexl** R package | ✅ Yes | `install.packages("writexl")` |
| **BILOG-MG** (BLM1/BLM2/BLM3) | ⚠️ Windows only | Required for `run` / `auto` modes. `prepare` and `parse` modes work without it. |

### Quick Start

**Default (auto mode — runs BILOG if available, otherwise prepares files):**

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx
```

**Try with bundled sample data:**

```bash
Rscript scripts/easy_bilog_runner.R examples/sample_data.xlsx examples/sample_answers.xlsx --mode=prepare
```

**Explicit native BILOG run:**

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=run --bilog-dir="C:/Program Files/BILOGMG"
```

**Parse an externally produced PAR/PH1 (place them in OUTPUT_DIR first):**

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=parse --output-dir=OUTPUT_DIR
```

### Installation as an AI Agent Skill

**Google Antigravity — Global (available in all workspaces):**

```bash
# Windows
xcopy /E /I /Y "bilog-calibration" "%USERPROFILE%\.gemini\antigravity\skills\bilog-calibration"
```

**Google Antigravity — Project (current workspace only):**

```
.agents/skills/bilog-calibration/
```

### Output Files

| File | Description |
| :--- | :--- |
| `115_XXX_IRT參數.xlsx` | Official five-column workbook: item No., a, b, c, point-biserial |
| `XX_BILOG_3PL_試題參數總表.xlsx` | Full 16-column CTT/IRT diagnostic report |
| `BILOG_RUN_SUMMARY.txt` | Execution status and MD5 provenance hashes |

### Execution Modes

| Mode | BILOG required | Description |
| :--- | :---: | :--- |
| `auto` | Optional | Runs BILOG if available; otherwise prepares files only |
| `run` | ✅ Yes | Requires BLM1/BLM2/BLM3; fails explicitly if absent |
| `prepare` | ❌ No | Generates DAT/OMITKEY/BLM for external execution |
| `parse` | ❌ No | Parses a pre-existing PAR/PH1 in the output directory |

See [`references/execution-modes.md`](references/execution-modes.md) for the full decision table.

---

## 繁體中文

### 專案介紹

`bilog-calibration` 是一個 **AI Agent 技能（Skill）**，專門用於自動化 BILOG-MG 三參數 IRT（試題反應理論）試題校準工作流程。

本技能以純 R 語言腳本（`scripts/easy_bilog_runner.R`）作為**唯一計算核心**，可在 Google Antigravity、OpenAI GPTs 或其他 Agent 平台上運行，支援：

- 🔍 輸入 Excel 預檢驗（作答篩選檔 + 答案向度檔）
- 📝 生成符合公務規範的原生 BILOG-MG 輸入檔（`.dat`、`OMITKEY.dat`、`.BLM`）
- ⚙️ 自動呼叫 BLM1 → BLM2 → BLM3 執行 3PL EM 校準
- 📊 解析 PAR / PH1 輸出，自動生成公務標準五欄與 16 欄 CTT/IRT 診斷報表
- 🔒 MD5 溯源校驗，防止 PAR 檔案不匹配

### 環境需求

| 依賴項目 | 必要 | 說明 |
| :--- | :---: | :--- |
| **R ≥ 4.2** | ✅ 必須 | `Rscript` 必須在系統 PATH 中 |
| **readxl** 套件 | ✅ 必須 | `install.packages("readxl")` |
| **writexl** 套件 | ✅ 必須 | `install.packages("writexl")` |
| **BILOG-MG**（BLM1/BLM2/BLM3）| ⚠️ Windows only | `run`/`auto` 模式才需要，`prepare`/`parse` 不需要 |

### 快速上手

```bash
# 預設自動模式（有 BILOG 就執行，沒有就只準備原生檔案）
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx

# 使用範例資料測試
Rscript scripts/easy_bilog_runner.R examples/sample_data.xlsx examples/sample_answers.xlsx --mode=prepare

# 指定 BILOG 路徑完整執行
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --mode=run --bilog-dir="C:/Program Files/BILOGMG"
```

### 安裝為 AI Agent 技能

**全域安裝（Google Antigravity，所有工作區皆適用）：**

```bash
# Windows PowerShell
Copy-Item -Path "bilog-calibration" -Destination "$env:USERPROFILE\.gemini\antigravity\skills" -Recurse -Force
```

### 主要輸出報表

| 檔案 | 內容說明 |
| :--- | :--- |
| `115_XXX_IRT參數.xlsx` | 公務標準五欄：題號、a、b、c、點二系列相關 |
| `XX_BILOG_3PL_試題參數總表.xlsx` | 16 欄 CTT/IRT 完整診斷報表（含通過率、BIS、CITC、SE、品質標記） |
| `BILOG_RUN_SUMMARY.txt` | 執行狀態、校準題數、學生人數與 MD5 溯源哈希 |

### 相關參考文件

- [`references/execution-modes.md`](references/execution-modes.md)：四種執行模式決策表
- [`references/input-output-contract.md`](references/input-output-contract.md)：輸入/輸出欄位規格
- [`references/interpretation.md`](references/interpretation.md)：試題品質判定標準與 PBIS/BIS 詮釋
- [`references/troubleshooting.md`](references/troubleshooting.md)：BLM 各階段報錯診斷手冊

### 授權

本專案採用 [MIT License](LICENSE)。
