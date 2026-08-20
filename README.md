# SAAA-bilog-calibration 縣市學生能力檢測 bilog 試題參數估計

> **Language / 語言**：[繁體中文](#繁體中文) | [English](#english)

---

## 繁體中文

### 專案介紹

`SAAA-bilog-calibration` 是一個專門針對 **縣市學生能力檢測（SAAA）** 與標準化測驗設計的 **AI Agent 技能（Skill）**，用於自動化執行 BILOG-MG 三參數 IRT（試題反應理論）試題參數估計與品質把關工作流程。

本技能以純 R 語言腳本（`scripts/easy_bilog_runner.R`）作為**唯一計算核心**，可在 Google Antigravity、OpenAI GPTs、Claude 或其他 Agent 平台上運行，支援：

- 🔍 **輸入 Excel 預檢驗**：自動驗證學生作答篩選檔與標準答案/向度定義檔。
- 📝 **公務原生檔生成**：產出標準 `.dat`（6 碼學生 ID）、`OMITKEY.dat`（前置 7 空格）與 `.BLM` 語法檔。
- ⚙️ **自動呼叫原廠引擎**：全自動串聯 BLM1 → BLM2 → BLM3 執行 3PL EM 參數校準。
- 📊 **雙規格報表輸出**：
  - `115_[科目]_IRT參數.xlsx`：公務標準 5 欄（題號、a、b、c、點二相關）
  - `[科目]_BILOG_3PL_試題參數總表.xlsx`：16 欄 CTT/IRT 完整診斷報表（含通過率、BIS、CITC、各項標準誤、品質標記）
- 🔒 **MD5 溯源防呆**：防止外部 PAR 檔案與資料集不匹配。

### 環境需求

| 依賴項目 | 必要 | 說明 |
| :--- | :---: | :--- |
| **R ≥ 4.2** | ✅ 必須 | `Rscript` 必須在系統 PATH 中 |
| **readxl** 套件 | ✅ 必須 | `install.packages("readxl")` |
| **writexl** 套件 | ✅ 必須 | `install.packages("writexl")` |
| **BILOG-MG**（BLM1/BLM2/BLM3）| ⚠️ Windows only | `run`/`auto` 模式需要，`prepare`/`parse` 模式不需要 |

### 快速上手

```bash
# 執行 3PL 三參數校準（預設推薦）
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=3PL

# 執行 2PL 二參數校準（c 固定為 0，官方報表僅輸出 a, b, 點二）
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=2PL

# 執行 1PL 單參數校準（a 為共同斜率，官方報表僅輸出 b, 點二）
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=1PL

# 使用範例資料測試
Rscript scripts/easy_bilog_runner.R examples/sample_data.xlsx examples/sample_answers.xlsx --subject=M5 --year=115 --model=3PL --mode=auto

# 指定 BILOG-MG 安裝目錄完整執行
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx --model=3PL --mode=run --bilog-dir="C:/Program Files/BILOGMG"
```

### 安裝為 AI Agent 技能

**全域安裝（Google Antigravity，所有工作區皆適用）：**

```bash
# Windows PowerShell
git clone https://github.com/liangchengyu-ntcu/SAAA-bilog-calibration.git
Copy-Item -Path "SAAA-bilog-calibration" -Destination "$env:USERPROFILE\.gemini\antigravity\skills" -Recurse -Force
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

---

## English

### Overview

`SAAA-bilog-calibration` is an **AI Agent Skill** tailored for regional student academic achievement assessments (SAAA) and standardized testing. It automates BILOG-MG 3PL Item Response Theory (IRT) item calibration workflows.

The skill uses a single authoritative R-based engine (`scripts/easy_bilog_runner.R`) that:

- Validates student-response and answer/dimension Excel workbooks
- Prepares native BILOG-MG input files (`.dat`, `OMITKEY.dat`, `.BLM`)
- Executes BLM1 → BLM2 → BLM3 when native BILOG-MG executables are installed
- Parses PAR and PH1 outputs from an external run
- Produces the official five-column IRT parameter workbook and a detailed 16-column CTT/IRT diagnostic report

### Quick Start

```bash
Rscript scripts/easy_bilog_runner.R DATA.xlsx ANSWERS.xlsx
```

### License

This project is licensed under the [MIT License](LICENSE).
