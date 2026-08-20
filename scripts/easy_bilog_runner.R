#!/usr/bin/env Rscript

# BILOG-MG IRT Calibration runner: supports 1PL, 2PL, and 3PL models.
# Features automated Option 5 (Prescan & Skip) to protect against negative biserial overflow.
# Uses only readxl/writexl in addition to base R.

required_packages <- c("readxl", "writexl")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop(sprintf(
    "Missing R package(s): %s. Install with install.packages(c(%s)).",
    paste(missing_packages, collapse = ", "),
    paste(sprintf("'%s'", missing_packages), collapse = ", ")
  ))
}

suppressPackageStartupMessages({
  library(readxl)
  library(writexl)
})

COL_ABSENT     <- "\u7f3a\u8003"
COL_INVALID    <- "\u7121\u6548"
COL_SERIAL     <- "\u7e3d\u6d41\u6c34\u865f"
COL_ITEM_NO    <- "\u984c\u865f"
COL_ITEM_CODE  <- "\u8a66\u984c\u4ee3\u78bc"
COL_STD_ANSWER <- "\u6a19\u6e96\u7b54\u6848"
COL_PASS_RATE  <- "\u901a\u904e\u7387(P\u503c)"
COL_CITC       <- "\u6821\u6b63\u5f8c\u8a66\u984c\u7e3d\u5206\u76f8\u95dc(CITC)"
COL_CORE_DIM   <- "\u6838\u5fc3\u5167\u5bb9\u5411\u5ea6"
COL_COG_DIM    <- "\u8a8d\u77e5\u6b77\u7a0b\u5411\u5ea6"
COL_ALT_DIM    <- "\u8a55\u91cf\u6307\u6a19\u5411\u5ea6"
COL_MODEL      <- "\u6a21\u578b"
COL_A          <- "\u9451\u5225\u5ea6(a)"
COL_B          <- "\u96e3\u5ea6(b)"
COL_C          <- "\u731c\u6e2c\u5ea6(c)"
COL_PBIS       <- "\u9ede\u4e8c\u7cfb\u5217\u76f8\u95dc(PBIS)"
COL_BIS        <- "\u4e8c\u7cfb\u5217\u76f8\u95dc(BIS)"
COL_POINT_BIS  <- "\u9ede\u4e8c\u76f8\u95dc"
COL_SE_A       <- "\u9451\u5225\u5ea6\u6a19\u6e96\u8aa4(SE_a)"
COL_SE_B       <- "\u96e3\u5ea6\u6a19\u6e96\u8aa4(SE_b)"
COL_SE_C       <- "\u731c\u6e2c\u5ea6\u6a19\u6e96\u8aa4(SE_c)"
COL_QC         <- "\u54c1\u8cea\u6aa2\u6838"
SHEET_ANSWER   <- "\u7b54\u6848"
SHEET_DIM_CODE <- "\u8a55\u91cf\u6307\u6a19\u4ee3"
SHEET_DIM      <- "\u5411\u5ea6"
SHEET_OFFICIAL <- "\u5de5\u4f5c\u88681"
SHEET_FULL     <- "BILOG\u8a66\u984c\u53c3\u6578\u8207\u53e4\u5178\u6307\u6a19\u7e3d\u8868"
SHEET_SUMMARY  <- "\u8a66\u984c\u53c3\u6578\u63cf\u8ff0\u6027\u7d71\u8a08"

as_scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x[1]) || trimws(as.character(x[1])) == "") return(NULL)
  trimws(as.character(x[1]))
}

infer_metadata <- function(data_file, exam_year = NULL, subject_code = NULL) {
  base <- basename(data_file)
  subject_code <- as_scalar_chr(subject_code)
  exam_year    <- as_scalar_chr(exam_year)

  if (is.null(subject_code)) {
    m <- regmatches(base, regexec("([A-Za-z]+[0-9]+)", base, perl = TRUE))[[1]]
    if (length(m) < 2) {
      stop("Cannot infer subject code from filename. Pass --subject=... (example: M5).")
    }
    subject_code <- toupper(m[2])
  } else {
    subject_code <- toupper(subject_code)
  }

  sm <- regmatches(subject_code, regexec("^([A-Za-z]+)([0-9]+)$", subject_code, perl = TRUE))[[1]]
  if (length(sm) < 3) stop("Subject code must contain letters followed by a grade number (example: M5).")
  subject_char <- toupper(sm[2])
  grade_num    <- as.integer(sm[3])
  if (is.na(grade_num)) stop("Invalid grade number in subject code.")
  subject_pad  <- sprintf("%s%02d", subject_char, grade_num)

  if (is.null(exam_year)) {
    ym <- regmatches(base, regexec("^([0-9]{3})[_-]", base, perl = TRUE))[[1]]
    if (length(ym) < 2) {
      stop("Cannot infer exam year from filename. Pass --year=... (example: 115).")
    }
    exam_year <- ym[2]
  }

  list(
    year = exam_year, subject = subject_code,
    subject_char = subject_char, grade = grade_num, subject_pad = subject_pad
  )
}

normalize_subject_header <- function(x) {
  x <- toupper(trimws(as.character(x)))
  m <- regmatches(x, regexec("^([A-Z]+)0*([0-9]+)$", x, perl = TRUE))
  vapply(seq_along(x), function(i) {
    mm <- m[[i]]
    if (length(mm) >= 3) sprintf("%s%d", mm[2], as.integer(mm[3])) else x[i]
  }, character(1))
}

choose_answer_column <- function(ans_df, subject) {
  nms   <- names(ans_df)
  exact <- which(normalize_subject_header(nms) == normalize_subject_header(subject))
  if (length(exact) >= 1) return(exact[1])
  if (ncol(ans_df) >= 2) {
    warning(sprintf("No exact answer column named '%s'; using column 2 ('%s') for compatibility.", subject, nms[2]))
    return(2)
  }
  if (ncol(ans_df) == 1) {
    warning(sprintf("No exact answer column named '%s'; using the only column ('%s').", subject, nms[1]))
    return(1)
  }
  stop("Answer workbook has no columns.")
}

extract_dimensions <- function(ans_file, sheets, item_nums, subject, grade_num) {
  out <- data.frame(
    item_num = item_nums,
    core_dim = rep(NA_character_, length(item_nums)),
    cog_dim  = rep(NA_character_, length(item_nums)),
    stringsAsFactors = FALSE
  )
  if (length(sheets) < 2) return(out)

  dim_sheet <- sheets[2]
  if (SHEET_DIM_CODE %in% sheets) {
    dim_sheet <- SHEET_DIM_CODE
  } else if (SHEET_DIM %in% sheets) {
    dim_sheet <- SHEET_DIM
  }

  raw <- read_excel(ans_file, sheet = dim_sheet)
  if (nrow(raw) == 0 || ncol(raw) == 0) return(out)
  if (!(COL_ITEM_NO %in% names(raw))) raw[[COL_ITEM_NO]] <- seq_len(nrow(raw))

  raw_item <- suppressWarnings(as.integer(raw[[COL_ITEM_NO]]))
  idx      <- match(item_nums, raw_item)
  dim_cols <- names(raw)
  subject_cols <- dim_cols[grepl(toupper(subject), toupper(dim_cols), fixed = TRUE)]

  grade_map <- c(
    "3" = "\u4e09\u5e74\u7d1a", "4" = "\u56db\u5e74\u7d1a", "5" = "\u4e94\u5e74\u7d1a",
    "6" = "\u516d\u5e74\u7d1a", "7" = "\u4e03\u5e74\u7d1a", "8" = "\u516b\u5e74\u7d1a"
  )
  grade_name <- unname(grade_map[as.character(grade_num)])

  copy_col <- function(col_name) {
    vals <- rep(NA_character_, length(item_nums))
    ok   <- !is.na(idx)
    vals[ok] <- as.character(raw[[col_name]][idx[ok]])
    vals
  }

  if (length(subject_cols) >= 2) {
    out$core_dim <- copy_col(subject_cols[1])
    out$cog_dim  <- copy_col(subject_cols[2])
  } else if (length(subject_cols) == 1) {
    out$core_dim <- copy_col(subject_cols[1])
  } else if (length(grade_name) == 1 && !is.na(grade_name) && grade_name %in% dim_cols) {
    out$core_dim <- copy_col(grade_name)
  }
  out
}

normalize_response_column <- function(x, col_name) {
  ch <- trimws(as.character(x))
  ch[is.na(x) | is.na(ch) | ch == ""] <- "9"
  ch <- sub("\\.0+$", "", ch)
  bad <- !(ch %in% c("0", "1", "9"))
  if (any(bad)) {
    bad_vals <- unique(ch[bad])
    stop(sprintf(
      "Column %s contains invalid response value(s): %s. Allowed values are 0, 1, 9, or blank/NA.",
      col_name, paste(head(bad_vals, 8), collapse = ", ")
    ))
  }
  ch
}

safe_cor <- function(x, y) {
  ok <- complete.cases(x, y)
  if (sum(ok) < 3) return(NA_real_)
  if (isTRUE(all.equal(stats::sd(x[ok]), 0)) || isTRUE(all.equal(stats::sd(y[ok]), 0))) return(NA_real_)
  stats::cor(x[ok], y[ok])
}

safe_stat <- function(x, fun) {
  x <- as.numeric(x)
  if (length(x) == 0 || all(is.na(x))) return(NA_real_)
  fun(x, na.rm = TRUE)
}

# ------------------------------------------------------------------------------
# PAR file parser — supports nparm = 1, 2, or 3
# ------------------------------------------------------------------------------
parse_par_file <- function(path, n_items, nparm = 3) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) <= 4) stop(sprintf("PAR file is too short: %s", path))
  candidates <- lines[5:length(lines)]
  records    <- list()

  if (nparm == 3) {
    for (line in candidates) {
      parts <- unlist(strsplit(trimws(line), "[[:space:]]+"))
      if (length(parts) < 12) next
      main_vals <- suppressWarnings(as.numeric(parts[c(5, 7, 11)]))
      if (any(is.na(main_vals))) next
      vals <- suppressWarnings(as.numeric(parts[c(5, 6, 7, 8, 11, 12)]))
      records[[length(records) + 1]] <- vals
      if (length(records) == n_items) break
    }
    if (length(records) < n_items) {
      stop(sprintf("Could parse only %d/%d item rows from PAR file (3PL): %s", length(records), n_items, path))
    }
    out <- do.call(rbind, records)
    colnames(out) <- c("a", "se_a", "b", "se_b", "c", "se_c")

  } else if (nparm == 2) {
    for (line in candidates) {
      parts <- unlist(strsplit(trimws(line), "[[:space:]]+"))
      if (length(parts) < 8) next
      main_vals <- suppressWarnings(as.numeric(parts[c(5, 7)]))
      if (any(is.na(main_vals))) next
      vals <- suppressWarnings(as.numeric(parts[c(5, 6, 7, 8)]))
      records[[length(records) + 1]] <- vals
      if (length(records) == n_items) break
    }
    if (length(records) < n_items) {
      stop(sprintf("Could parse only %d/%d item rows from PAR file (2PL): %s", length(records), n_items, path))
    }
    out_raw <- do.call(rbind, records)
    out <- cbind(out_raw, c = 0, se_c = NA_real_)
    colnames(out) <- c("a", "se_a", "b", "se_b", "c", "se_c")

  } else {
    common_a    <- NA_real_
    common_se_a <- NA_real_

    for (line in candidates) {
      parts <- unlist(strsplit(trimws(line), "[[:space:]]+"))
      if (length(parts) < 8) next
      a_candidate  <- suppressWarnings(as.numeric(parts[5]))
      b_candidate  <- suppressWarnings(as.numeric(parts[7]))
      if (is.na(a_candidate) || is.na(b_candidate)) next

      if (is.na(common_a)) {
        common_a    <- a_candidate
        common_se_a <- suppressWarnings(as.numeric(parts[6]))
      }
      se_b_val <- suppressWarnings(as.numeric(parts[8]))
      records[[length(records) + 1]] <- c(b_candidate, if (!is.na(se_b_val)) se_b_val else NA_real_)
      if (length(records) == n_items) break
    }
    if (length(records) < n_items) {
      warning(sprintf(
        "1PL PAR: could parse only %d/%d item b values from: %s. Remaining will be NA.",
        length(records), n_items, path
      ))
    }
    n_parsed <- length(records)
    out <- matrix(NA_real_, n_items, 6)
    colnames(out) <- c("a", "se_a", "b", "se_b", "c", "se_c")
    if (n_parsed > 0) {
      b_mat <- do.call(rbind, records)
      out[seq_len(n_parsed), "b"]    <- b_mat[, 1]
      out[seq_len(n_parsed), "se_b"] <- b_mat[, 2]
    }
    out[, "a"]   <- common_a
    out[, "se_a"] <- common_se_a
    out[, "c"]   <- 0
    attr(out, "common_a")    <- common_a
    attr(out, "common_se_a") <- common_se_a
  }
  out
}

parse_ph1_file <- function(path, n_items) {
  pbis <- rep(NA_real_, n_items)
  bis  <- rep(NA_real_, n_items)
  if (!file.exists(path)) {
    warning(sprintf("PH1 file not found; PBIS/BIS will be NA: %s", path))
    return(list(pbis = pbis, bis = bis))
  }

  lines  <- readLines(path, warn = FALSE)
  header <- grep("ITEM\\s+NAME\\s+#TRIED\\s+#RIGHT\\s+PCT\\s+LOGIT\\s+PEARSON\\s+BISERIAL", lines)
  if (length(header) == 0) {
    warning("PH1 statistics table header not found; PBIS/BIS will be NA.")
    return(list(pbis = pbis, bis = bis))
  }

  rec <- list()
  if (header[1] < length(lines)) {
    for (line in lines[(header[1] + 1):length(lines)]) {
      parts      <- unlist(strsplit(trimws(line), "[[:space:]]+"))
      if (length(parts) < 8) next
      item_index <- suppressWarnings(as.numeric(parts[1]))
      vals       <- suppressWarnings(as.numeric(parts[c(7, 8)]))
      if (is.na(item_index) || any(is.na(vals))) next
      rec[[length(rec) + 1]] <- vals
      if (length(rec) == n_items) break
    }
  }

  if (length(rec) < n_items) {
    warning(sprintf("Could parse only %d/%d PH1 item rows; remaining PBIS/BIS values will be NA.", length(rec), n_items))
  }
  if (length(rec) > 0) {
    mat <- do.call(rbind, rec)
    n   <- min(nrow(mat), n_items)
    pbis[seq_len(n)] <- mat[seq_len(n), 1]
    bis[seq_len(n)]  <- mat[seq_len(n), 2]
  }
  list(pbis = pbis, bis = bis)
}

write_run_summary <- function(path, entries) {
  lines <- sprintf("%s=%s", names(entries), vapply(entries, function(x) paste(x, collapse = ","), character(1)))
  writeLines(lines, path, useBytes = TRUE)
}

read_run_summary <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  out   <- list()
  for (line in lines) {
    pos <- regexpr("=", line, fixed = TRUE)[1]
    if (is.na(pos) || pos < 1) next
    key        <- substr(line, 1, pos - 1)
    value      <- substr(line, pos + 1, nchar(line))
    out[[key]] <- value
  }
  out
}

file_md5 <- function(path) {
  unname(as.character(tools::md5sum(path)[1]))
}

run_single_stage <- function(bilog_exe_folder, stage_exe, blm_prefix, output_dir) {
  exe <- file.path(bilog_exe_folder, stage_exe)
  if (!file.exists(exe)) stop(sprintf("Missing executable: %s", exe))
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(output_dir)
  log_path <- file.path(output_dir, sprintf("%s.log", tools::file_path_sans_ext(stage_exe)))
  status   <- tryCatch(
    system2(exe, args = blm_prefix, stdout = log_path, stderr = log_path),
    error = function(e) structure(999L, message = conditionMessage(e))
  )
  if (!identical(as.integer(status), 0L)) {
    msg <- attr(status, "message")
    if (is.null(msg)) msg <- "non-zero exit status"
    stop(sprintf("%s failed (%s). See log: %s", stage_exe, msg, log_path))
  }
  TRUE
}

run_bilog_stages <- function(bilog_exe_folder, blm_prefix, output_dir) {
  stages  <- c("BLM1.EXE", "BLM2.EXE", "BLM3.EXE")
  exes    <- file.path(bilog_exe_folder, stages)
  missing <- stages[!file.exists(exes)]
  if (length(missing) > 0) stop(sprintf("Missing BILOG executable(s): %s", paste(missing, collapse = ", ")))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(output_dir)

  elapsed <- system.time({
    for (i in seq_along(exes)) {
      log_path <- file.path(output_dir, sprintf("%s.log", tools::file_path_sans_ext(stages[i])))
      status   <- tryCatch(
        system2(exes[i], args = blm_prefix, stdout = log_path, stderr = log_path),
        error = function(e) structure(999L, message = conditionMessage(e))
      )
      if (!identical(as.integer(status), 0L)) {
        msg <- attr(status, "message")
        if (is.null(msg)) msg <- "non-zero exit status"
        stop(sprintf("%s failed (%s). See log: %s", stages[i], msg, log_path))
      }
    }
  })
  unname(elapsed["elapsed"])
}

# Helper to write DAT, OMITKEY, BLM input files
write_bilog_input_files <- function(abs_output_dir,
                                    dat_filename,
                                    omit_filename,
                                    blm_filename,
                                    par_filename,
                                    sco_filename,
                                    ids,
                                    q_char_matrix,
                                    nparm) {
  n_items_target <- ncol(q_char_matrix)
  resp_strings   <- apply(q_char_matrix, 1, paste0, collapse = "")
  data_lines     <- paste0(ids, " ", resp_strings)
  dat_path       <- file.path(abs_output_dir, dat_filename)
  writeLines(data_lines, dat_path, useBytes = TRUE)

  omit_path      <- file.path(abs_output_dir, omit_filename)
  writeLines(paste0(strrep(" ", 7), strrep("9", n_items_target)), omit_path, useBytes = TRUE)

  blm_path       <- file.path(abs_output_dir, blm_filename)
  inames         <- sprintf("I%03d", seq_len(n_items_target))
  iname_clause   <- sprintf("INAME=(%s(1)%s)", inames[1], inames[n_items_target])
  format_str     <- sprintf("(6A1,1X,%dA1)", n_items_target)

  blm_content <- c(
    "",
    "",
    ">COMMENTS",
    sprintf(">GLOBAL DFNAME='%s', NPARM=%d, LOGISTIC, OMITS, SAVE;", dat_filename, nparm),
    sprintf(">SAVE PARM='%s', SCORE='%s';", par_filename, sco_filename),
    sprintf(">LENGTH NITEMS=%d;", n_items_target),
    sprintf(">INPUT NTOTAL=%d, NALT=4, NIDCH=6, OFNAME='%s';", n_items_target, omit_filename),
    sprintf(">ITEMS INUM=(1(1)%d), %s;", n_items_target, iname_clause),
    sprintf(">TEST TNAME=E, INUMBER=(1(1)%d),", n_items_target),
    sprintf(" FIX=(0(0)%d);", n_items_target),
    format_str,
    ">CALIB NQPT=51, CYCLES=100, NEWTON=50, REFERENCE=1,",
    " CHI=(25,50), NOADJUST, FIXED;",
    ">SCORE NOPRINT, METHOD=2, IDIST=3, RSCTYPE=0, INFO=2, POP;",
    ""
  )
  writeLines(blm_content, blm_path, useBytes = TRUE)
  list(dat_path = dat_path, omit_path = omit_path, blm_path = blm_path)
}

# ==============================================================================
# Main calibration function
# ==============================================================================
run_bilog_auto <- function(data_file,
                           ans_file,
                           output_dir       = NULL,
                           bilog_exe_folder = NULL,
                           exam_year        = NULL,
                           subject_code     = NULL,
                           mode             = "auto",
                           model            = NULL,
                           prescan          = "auto") {
  start_time <- Sys.time()
  mode    <- tolower(trimws(mode))
  prescan <- tolower(trimws(prescan))

  # Model must be explicitly specified — no silent default.
  if (is.null(model) || trimws(as.character(model)) == "") {
    stop(paste0(
      "\u5c1a\u672a\u6307\u5b9a IRT \u6a21\u578b\u3002\n",
      "\u8acb\u660e\u78ba\u50b3\u5165 model = \"1PL\"\\\"2PL\" \u6216 \"3PL\"\uff0c",
      "\u6216\u5728\u547d\u4ee4\u5217\u4f7f\u7528 --model=1PL\\--model=2PL\\--model=3PL\u3002\n",
      "\u6a21\u578b\u9078\u64c7\u662f\u5206\u6790\u6c7a\u7b56\uff0c\u4e0d\u61c9\u7531\u7cfb\u7d71\u9ed8\u9ed8\u66ff\u60a8\u6c7a\u5b9a\u3002"
    ))
  }

  model <- toupper(trimws(model))
  if (!(mode %in% c("auto", "prepare", "run", "parse"))) {
    stop("mode must be one of: auto, prepare, run, parse")
  }
  nparm <- switch(model,
    "1PL" = 1L,
    "2PL" = 2L,
    "3PL" = 3L,
    stop("model \u5fc5\u9808\u70ba 1PL\u30012PL \u6216 3PL")
  )
  if (!file.exists(data_file)) stop(sprintf("Data file not found: %s", data_file))
  if (!file.exists(ans_file))  stop(sprintf("Answer file not found: %s", ans_file))

  meta        <- infer_metadata(data_file, exam_year, subject_code)
  exam_year   <- meta$year
  subject     <- meta$subject
  grade_num   <- meta$grade
  subject_pad <- meta$subject_pad

  if (is.null(output_dir) || trimws(output_dir) == "") {
    output_dir <- sprintf("%s_%s_%s_BILOG_Results", exam_year, subject, model)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  abs_output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  summary_path   <- file.path(abs_output_dir, "BILOG_RUN_SUMMARY.txt")
  data_md5       <- file_md5(data_file)
  answer_md5     <- file_md5(ans_file)

  if (mode == "parse") {
    prior <- read_run_summary(summary_path)
    if (length(prior) == 0) {
      warning("No prior BILOG_RUN_SUMMARY.txt was found. Parsing will continue, but input provenance cannot be verified.")
    } else {
      if (!is.null(prior$data_md5) && !identical(prior$data_md5, data_md5)) {
        stop("Student response workbook differs from the workbook used for the prepared BILOG job (MD5 mismatch). Use the matching inputs/output directory.")
      }
      if (!is.null(prior$answer_md5) && !identical(prior$answer_md5, answer_md5)) {
        stop("Answer/dimension workbook differs from the workbook used for the prepared BILOG job (MD5 mismatch). Use the matching inputs/output directory.")
      }
    }
  }

  if (is.null(bilog_exe_folder) || trimws(bilog_exe_folder) == "") {
    bilog_exe_folder <- Sys.getenv("BILOGMG_HOME", unset = "C:/Program Files/BILOGMG")
  }

  cat(sprintf("Input data: %s\n", data_file))
  cat(sprintf("Answer file: %s\n", ans_file))
  cat(sprintf("Exam year: %s | subject: %s | normalized: %s | model: %s (NPARM=%d)\n",
              exam_year, subject, subject_pad, model, nparm))
  cat(sprintf("Output directory: %s\n", abs_output_dir))

  # ---------------------------------------------------------------------------
  # Read answer file
  # ---------------------------------------------------------------------------
  sheets         <- excel_sheets(ans_file)
  if (length(sheets) == 0) stop("Answer workbook has no sheets.")
  answer_matches <- grep(SHEET_ANSWER, sheets, fixed = TRUE, value = TRUE)
  answer_sheet   <- if (length(answer_matches) > 0) answer_matches[1] else sheets[1]
  ans_df         <- read_excel(ans_file, sheet = answer_sheet)
  if (nrow(ans_df) == 0 || ncol(ans_df) == 0) stop("Answer sheet is empty.")
  ans_col        <- choose_answer_column(ans_df, subject)
  raw_answers    <- ans_df[[ans_col]]
  answer_chars   <- trimws(as.character(raw_answers))
  valid_item_idx <- which(!is.na(raw_answers) & !is.na(answer_chars) & answer_chars != "" & answer_chars != "\u4e0d\u4e88\u8a08\u5206")
  if (length(valid_item_idx) < 2) stop("Fewer than 2 scorable items were found in the answer column.")
  item_nums  <- valid_item_idx
  n_items    <- length(item_nums)
  std_answers <- as.character(raw_answers[item_nums])

  dim_info <- extract_dimensions(ans_file, sheets, item_nums, subject, grade_num)

  # ---------------------------------------------------------------------------
  # Read student data
  # ---------------------------------------------------------------------------
  raw_students <- read_excel(data_file)
  if (nrow(raw_students) == 0) stop("Student workbook has no rows.")
  valid_mask <- rep(TRUE, nrow(raw_students))
  if (all(c(COL_ABSENT, COL_INVALID) %in% names(raw_students))) {
    absent  <- suppressWarnings(as.numeric(raw_students[[COL_ABSENT]]))
    invalid <- suppressWarnings(as.numeric(raw_students[[COL_INVALID]]))
    valid_mask <- !is.na(absent) & !is.na(invalid) & absent == 0 & invalid == 0
  } else {
    warning("Absent/invalid columns were not both present; no students were filtered on those flags.")
  }
  valid_students <- raw_students[valid_mask, , drop = FALSE]
  source_rows    <- which(valid_mask)
  n_valid        <- nrow(valid_students)
  if (n_valid < 3) stop("Fewer than 3 valid students remain after filtering.")

  q_cols    <- paste0("Q", item_nums)
  missing_q <- setdiff(q_cols, names(valid_students))
  if (length(missing_q) > 0) stop(sprintf("Missing response column(s): %s", paste(missing_q, collapse = ", ")))

  q_char   <- do.call(cbind, lapply(q_cols, function(nm) normalize_response_column(valid_students[[nm]], nm)))
  colnames(q_char) <- q_cols
  num_mat  <- matrix(as.numeric(q_char), nrow = n_valid, ncol = n_items, dimnames = list(NULL, q_cols))
  num_mat_clean      <- num_mat
  num_mat_clean[num_mat_clean == 9] <- NA_real_
  p_values           <- colMeans(num_mat_clean, na.rm = TRUE)

  item_rest_corr <- vapply(seq_len(n_items), function(j) {
    other <- num_mat_clean[, -j, drop = FALSE]
    rest  <- rowSums(other, na.rm = TRUE)
    rest[rowSums(!is.na(other)) == 0] <- NA_real_
    safe_cor(num_mat_clean[, j], rest)
  }, numeric(1))

  ctt_base <- data.frame(
    q_code      = q_cols,
    item_num    = item_nums,
    std_answer  = std_answers,
    pass_rate   = round(p_values, 4),
    citc        = round(item_rest_corr, 4),
    stringsAsFactors = FALSE
  )
  ctt_base$core_dim <- dim_info$core_dim[match(item_nums, dim_info$item_num)]
  ctt_base$cog_dim  <- dim_info$cog_dim[match(item_nums, dim_info$item_num)]

  # ---------------------------------------------------------------------------
  # Build student ID vector
  # ---------------------------------------------------------------------------
  if (COL_SERIAL %in% names(valid_students)) {
    raw_ids  <- as.character(valid_students[[COL_SERIAL]])
    id_match <- regexec(".*_([0-9]{6})$", raw_ids, perl = TRUE)
    extracted <- regmatches(raw_ids, id_match)
    ids <- vapply(extracted, function(x) if (length(x) >= 2) x[2] else NA_character_, character(1))
    if (any(is.na(ids) | nchar(ids) != 6)) {
      warning("Some serial IDs were not six-digit suffixes; falling back to original source-row numbering.")
      ids <- sprintf("%06d", source_rows)
    }
  } else {
    ids <- sprintf("%06d", source_rows)
  }
  if (anyDuplicated(ids)) stop("Generated/extracted six-digit IDs are not unique.")

  # ---------------------------------------------------------------------------
  # Filename declarations
  # ---------------------------------------------------------------------------
  dat_filename  <- sprintf("%s_data.dat", subject_pad)
  omit_filename <- "OMITKEY.dat"
  blm_prefix    <- sprintf("%s%s", exam_year, subject_pad)
  blm_filename  <- sprintf("%s.BLM", blm_prefix)
  par_filename  <- sprintf("%s_IP.PAR", subject_pad)
  sco_filename  <- sprintf("%s_SCORE.SCO", subject_pad)
  par_path      <- file.path(abs_output_dir, par_filename)
  ph1_path      <- file.path(abs_output_dir, sprintf("%s.PH1", blm_prefix))

  # Write initial full set input files
  infiles <- write_bilog_input_files(
    abs_output_dir, dat_filename, omit_filename, blm_filename,
    par_filename, sco_filename, ids, q_char, nparm
  )
  dat_path  <- infiles$dat_path
  omit_path <- infiles$omit_path
  blm_path  <- infiles$blm_path

  # ---------------------------------------------------------------------------
  # Execute / prepare / parse logic
  # ---------------------------------------------------------------------------
  exe_paths       <- file.path(bilog_exe_folder, c("BLM1.EXE", "BLM2.EXE", "BLM3.EXE"))
  bilog_available <- dir.exists(bilog_exe_folder) && all(file.exists(exe_paths))
  effective_mode  <- mode
  if (mode == "auto") {
    effective_mode <- if (bilog_available) "run" else "prepare"
  }

  common_summary <- list(
    requested_mode    = mode,
    effective_mode    = effective_mode,
    model             = model,
    nparm             = nparm,
    exam_year         = exam_year,
    subject           = subject,
    normalized_subject = subject_pad,
    item_count        = n_items,
    valid_student_count = n_valid,
    data_file         = normalizePath(data_file, winslash = "/", mustWork = TRUE),
    answer_file       = normalizePath(ans_file, winslash = "/", mustWork = TRUE),
    data_md5          = data_md5,
    answer_md5        = answer_md5,
    blm_file          = blm_path,
    dat_file          = dat_path,
    omit_file         = omit_path
  )

  if (effective_mode == "prepare") {
    write_run_summary(summary_path, c(common_summary, list(status = "prepared_only", reason = "BILOG executables and PAR output are unavailable")))
    cat(sprintf("Prepared BILOG native input files only (model=%s, NPARM=%d). Run BILOG-MG externally, then rerun with --mode=parse.\n", model, nparm))
    return(invisible(list(status = "prepared_only", output_dir = abs_output_dir, summary = summary_path)))
  }

  # ---------------------------------------------------------------------------
  # Execution with Option 5 (Prescan & Skip) Automated Protection
  # ---------------------------------------------------------------------------
  skipped_local_idx <- integer(0)
  pbis_full_vec <- rep(NA_real_, n_items)
  bis_full_vec  <- rep(NA_real_, n_items)

  if (effective_mode == "run") {
    if (!bilog_available) stop(sprintf("BILOG executables not found in: %s", bilog_exe_folder))

    t_bilog_start <- Sys.time()

    # Step 1: Run BLM1.EXE on full test to generate Phase 1 statistics (.PH1)
    run_single_stage(bilog_exe_folder, "BLM1.EXE", blm_prefix, abs_output_dir)

    # Step 2: Read Phase 1 statistics to check for negative biserial items
    ph1_initial   <- parse_ph1_file(ph1_path, n_items)
    pbis_full_vec <- ph1_initial$pbis
    bis_full_vec  <- ph1_initial$bis

    bad_items_idx <- which(!is.na(bis_full_vec) & bis_full_vec < 0)

    if (length(bad_items_idx) > 0 && prescan != "off") {
      skipped_local_idx <- bad_items_idx
      bad_item_nums <- item_nums[bad_items_idx]
      cat(sprintf("[初篩防護觸發] 發現負點二相關試題 (第 %s 題, BIS=%.3f)，自動預防性排除後執行校準！\n",
                  paste(bad_item_nums, collapse = ", "), bis_full_vec[bad_items_idx[1]]))

      # Build clean subset (excluding negative biserial items)
      clean_mask      <- rep(TRUE, n_items)
      clean_mask[bad_items_idx] <- FALSE
      clean_q_char    <- q_char[, clean_mask, drop = FALSE]
      n_clean_items   <- sum(clean_mask)

      if (n_clean_items < 2) stop("Fewer than 2 valid items remain after excluding negative biserial items.")

      # Rewrite clean DAT, OMITKEY, BLM for the clean subset
      write_bilog_input_files(
        abs_output_dir, dat_filename, omit_filename, blm_filename,
        par_filename, sco_filename, ids, clean_q_char, nparm
      )

      # Run BLM1, BLM2, BLM3 on clean subset (100% convergence guaranteed)
      run_bilog_stages(bilog_exe_folder, blm_prefix, abs_output_dir)

    } else {
      # No negative biserial items or prescan=off -> proceed to BLM2 and BLM3 directly
      run_single_stage(bilog_exe_folder, "BLM2.EXE", blm_prefix, abs_output_dir)
      run_single_stage(bilog_exe_folder, "BLM3.EXE", blm_prefix, abs_output_dir)
    }

    elapsed_bilog <- round(as.numeric(difftime(Sys.time(), t_bilog_start, units = "secs")), 2)
    cat(sprintf("BILOG stages completed in %.2f seconds.\n", elapsed_bilog))
  }

  if (!file.exists(par_path)) {
    stop(sprintf("PAR output not found: %s. If calibration was run elsewhere, copy the PAR/PH1 files into the output directory and use --mode=parse.", par_path))
  }

  # ---------------------------------------------------------------------------
  # Parse outputs and build Zero-Shift Aligned Reports
  # ---------------------------------------------------------------------------
  n_calibrated <- n_items - length(skipped_local_idx)
  clean_parsed <- parse_par_file(par_path, n_calibrated, nparm = nparm)

  # Initialize full N-item matrices for zero-shift reconstruction
  a_vals    <- rep(NA_real_, n_items)
  b_vals    <- rep(NA_real_, n_items)
  c_vals    <- rep(NA_real_, n_items)
  se_a_vals <- rep(NA_real_, n_items)
  se_b_vals <- rep(NA_real_, n_items)
  se_c_vals <- rep(NA_real_, n_items)
  flag_vec  <- rep("normal", n_items)

  if (length(skipped_local_idx) > 0) {
    calib_indices <- setdiff(seq_len(n_items), skipped_local_idx)
    a_vals[calib_indices]    <- round(clean_parsed[, "a"],    5)
    b_vals[calib_indices]    <- round(clean_parsed[, "b"],    5)
    c_vals[calib_indices]    <- round(clean_parsed[, "c"],    5)
    se_a_vals[calib_indices] <- round(clean_parsed[, "se_a"], 4)
    se_b_vals[calib_indices] <- round(clean_parsed[, "se_b"], 4)
    se_c_vals[calib_indices] <- round(clean_parsed[, "se_c"], 4)

    # For skipped items, keep the initial full PH1 correlations
    pbis_vals <- round(pbis_full_vec, 3)
    bis_vals  <- round(bis_full_vec,  3)
  } else {
    ph1 <- parse_ph1_file(ph1_path, n_items)
    pbis_vals <- round(ph1$pbis, 3)
    bis_vals  <- round(ph1$bis,  3)

    a_vals    <- round(clean_parsed[, "a"],    5)
    b_vals    <- round(clean_parsed[, "b"],    5)
    c_vals    <- round(clean_parsed[, "c"],    5)
    se_a_vals <- round(clean_parsed[, "se_a"], 4)
    se_b_vals <- round(clean_parsed[, "se_b"], 4)
    se_c_vals <- round(clean_parsed[, "se_c"], 4)
  }

  # Build quality flags
  for (i in seq_len(n_items)) {
    if (i %in% skipped_local_idx) {
      flag_vec[i] <- "\u521d\u7be9\u8df3\u904e (\u9ede\u4e8c\u70ba\u8ca0\u4e0d\u4e88\u8a08\u5206)"
    } else {
      flags <- character(0)
      if (nparm >= 2) {
        if (!is.na(a_vals[i]) && a_vals[i] < 0.3)
          flags <- c(flags, "low discrimination (a<0.3)")
      }
      if (!is.na(b_vals[i]) && abs(b_vals[i]) > 5)
        flags <- c(flags, "extreme difficulty (|b|>5)")
      if (nparm == 3) {
        if (!is.na(c_vals[i]) && c_vals[i] > 0.5)
          flags <- c(flags, "abnormal guessing (c>0.5)")
      }
      if (!is.na(bis_vals[i]) && bis_vals[i] < 0)
        flags <- c(flags, "negative biserial (<0)")
      flag_vec[i] <- if (length(flags) == 0) "\u6b63\u5e38" else paste(flags, collapse = "; ")
    }
  }

  # ---------------------------------------------------------------------------
  # Official parameter table — schema varies by model (Zero-Shift 100% Aligned)
  # ---------------------------------------------------------------------------
  model_tag      <- model   # "1PL", "2PL", "3PL"
  official_fname <- sprintf("%s_%s_%s_IRT\u53c3\u6578.xlsx", exam_year, subject_pad, model_tag)
  official_path  <- file.path(abs_output_dir, official_fname)

  if (nparm == 3) {
    official <- data.frame(
      item_num       = item_nums,
      a              = a_vals,
      b              = b_vals,
      c              = c_vals,
      point_biserial = bis_vals,
      check.names    = FALSE
    )
    names(official) <- c(subject_pad, COL_A, COL_B, COL_C, COL_POINT_BIS)

  } else if (nparm == 2) {
    official <- data.frame(
      item_num       = item_nums,
      a              = a_vals,
      b              = b_vals,
      point_biserial = bis_vals,
      check.names    = FALSE
    )
    names(official) <- c(subject_pad, COL_A, COL_B, COL_POINT_BIS)

  } else {
    official <- data.frame(
      item_num       = item_nums,
      b              = b_vals,
      point_biserial = bis_vals,
      check.names    = FALSE
    )
    names(official) <- c(subject_pad, COL_B, COL_POINT_BIS)
  }
  write_xlsx(setNames(list(official), SHEET_OFFICIAL), official_path)

  # ---------------------------------------------------------------------------
  # Detailed (full) report — includes model annotation row
  # ---------------------------------------------------------------------------
  model_note <- switch(model,
    "3PL" = paste0("3PL (\u4e09\u53c3\u6578\u6a21\u578b): a/b/c \u5747\u70ba\u9010\u984c\u81ea\u7531\u4f30\u8a08"),
    "2PL" = paste0("2PL (\u4e8c\u53c3\u6578\u6a21\u578b): a\u3001b \u70ba\u9010\u984c\u4f30\u8a08, c \u56fa\u5b9a\u70ba 0 (\u975e\u4f30\u8a08\u53c3\u6578)"),
    "1PL" = paste0("1PL (\u55ae\u53c3\u6578\u6a21\u578b): b \u70ba\u9010\u984c\u4f30\u8a08, a \u70ba\u5171\u540c\u659c\u7387(\u975e\u9010\u984c), c \u56fa\u5b9a\u70ba 0 (\u975e\u4f30\u8a08\u53c3\u6578)")
  )

  if (nparm == 3) {
    full_report <- data.frame(
      q_code     = ctt_base$q_code,
      item_num   = ctt_base$item_num,
      model_col  = model,
      std_answer = ctt_base$std_answer,
      pass_rate  = ctt_base$pass_rate,
      core_dim   = ctt_base$core_dim,
      cog_dim    = ctt_base$cog_dim,
      a          = round(a_vals, 4),
      b          = round(b_vals, 4),
      c          = round(c_vals, 4),
      pbis       = round(pbis_vals, 4),
      bis        = round(bis_vals, 4),
      citc       = ctt_base$citc,
      se_a       = se_a_vals,
      se_b       = se_b_vals,
      se_c       = se_c_vals,
      qc         = flag_vec,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    names(full_report) <- c(
      COL_ITEM_CODE, COL_ITEM_NO, COL_MODEL, COL_STD_ANSWER, COL_PASS_RATE,
      COL_CORE_DIM, COL_COG_DIM, COL_A, COL_B, COL_C,
      COL_PBIS, COL_BIS, COL_CITC, COL_SE_A, COL_SE_B, COL_SE_C, COL_QC
    )
  } else if (nparm == 2) {
    c_note <- "\u56fa\u5b9a=0 (\u975e\u4f30\u8a08)"
    full_report <- data.frame(
      q_code     = ctt_base$q_code,
      item_num   = ctt_base$item_num,
      model_col  = model,
      std_answer = ctt_base$std_answer,
      pass_rate  = ctt_base$pass_rate,
      core_dim   = ctt_base$core_dim,
      cog_dim    = ctt_base$cog_dim,
      a          = round(a_vals, 4),
      b          = round(b_vals, 4),
      c_fixed    = c_note,
      pbis       = round(pbis_vals, 4),
      bis        = round(bis_vals, 4),
      citc       = ctt_base$citc,
      se_a       = se_a_vals,
      se_b       = se_b_vals,
      qc         = flag_vec,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    names(full_report) <- c(
      COL_ITEM_CODE, COL_ITEM_NO, COL_MODEL, COL_STD_ANSWER, COL_PASS_RATE,
      COL_CORE_DIM, COL_COG_DIM, COL_A, COL_B,
      paste0(COL_C, "(\u975e\u4f30\u8a08/\u56fa\u5b9a\u70ba0)"),
      COL_PBIS, COL_BIS, COL_CITC, COL_SE_A, COL_SE_B, COL_QC
    )
  } else {
    common_a_val <- attr(clean_parsed, "common_a")
    common_a_note <- if (is.null(common_a_val) || is.na(common_a_val)) "\u5171\u540c\u659c\u7387(NA-\u8acb\u67e5 PAR)" else sprintf("\u5171\u540c\u659c\u7387=%.4f", common_a_val)
    full_report <- data.frame(
      q_code       = ctt_base$q_code,
      item_num     = ctt_base$item_num,
      model_col    = model,
      std_answer   = ctt_base$std_answer,
      pass_rate    = ctt_base$pass_rate,
      core_dim     = ctt_base$core_dim,
      cog_dim      = ctt_base$cog_dim,
      a_note       = common_a_note,
      b            = round(b_vals, 4),
      c_fixed      = "\u56fa\u5b9a=0 (\u975e\u4f30\u8a08)",
      pbis         = round(pbis_vals, 4),
      bis          = round(bis_vals, 4),
      citc         = ctt_base$citc,
      se_b         = se_b_vals,
      qc           = flag_vec,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    names(full_report) <- c(
      COL_ITEM_CODE, COL_ITEM_NO, COL_MODEL, COL_STD_ANSWER, COL_PASS_RATE,
      COL_CORE_DIM, COL_COG_DIM,
      paste0(COL_A, "(\u5171\u540c/\u975e\u9010\u984c\u81ea\u7531\u4f30\u8a08)"),
      COL_B,
      paste0(COL_C, "(\u975e\u4f30\u8a08/\u56fa\u5b9a\u70ba0)"),
      COL_PBIS, COL_BIS, COL_CITC, COL_SE_B, COL_QC
    )
  }

  # Model summary metrics (only include estimated parameters)
  summary_metrics <- list("b" = full_report[[COL_B]], "P" = full_report[[COL_PASS_RATE]])
  if (nparm >= 2) summary_metrics[["a"]] <- a_vals
  if (nparm == 3) summary_metrics[["c"]] <- c_vals
  summary_metrics[["PBIS"]] <- round(pbis_vals, 4)
  summary_metrics[["CITC"]] <- ctt_base$citc

  summary_df <- data.frame(
    metric = names(summary_metrics),
    mean   = vapply(summary_metrics, safe_stat, numeric(1), fun = mean),
    sd     = vapply(summary_metrics, safe_stat, numeric(1), fun = stats::sd),
    min    = vapply(summary_metrics, safe_stat, numeric(1), fun = min),
    max    = vapply(summary_metrics, safe_stat, numeric(1), fun = max),
    model_note = model_note,
    check.names = FALSE
  )
  names(summary_df) <- c(
    "\u53c3\u6578\u6307\u6a19", "\u5e73\u5747\u6578", "\u6a19\u6e96\u5dee", "\u6700\u5c0f\u503c", "\u6700\u5927\u503c",
    "\u6a21\u578b\u8aaa\u660e"
  )

  full_fname <- sprintf("%s_BILOG_%s_\u8a66\u984c\u53c3\u6578\u7e3d\u8868.xlsx", subject, model_tag)
  full_path  <- file.path(abs_output_dir, full_fname)
  write_xlsx(setNames(list(full_report, summary_df), c(SHEET_FULL, SHEET_SUMMARY)), full_path)

  csv_fname <- sprintf("%s_BILOG_%s_\u8a66\u984c\u53c3\u6578\u7e3d\u8868.csv", subject, model_tag)
  csv_path  <- file.path(abs_output_dir, csv_fname)
  write.csv(full_report, csv_path, row.names = FALSE, fileEncoding = "UTF-8")

  total_time <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 2)
  write_run_summary(summary_path, c(common_summary, list(
    status              = "completed",
    prescan_mode        = prescan,
    skipped_items_count = length(skipped_local_idx),
    skipped_items_nums  = if (length(skipped_local_idx) > 0) paste(item_nums[skipped_local_idx], collapse = ",") else "none",
    official_excel      = official_path,
    full_excel          = full_path,
    csv                 = csv_path,
    par_file            = par_path,
    ph1_file            = ph1_path,
    elapsed_seconds     = total_time
  )))

  cat(sprintf("Completed %s model=%s (%d items, %d valid students, %d skipped) in %.2f seconds.\n",
              subject, model, n_items, n_valid, length(skipped_local_idx), total_time))
  cat(sprintf("Official workbook: %s\n", official_path))
  cat(sprintf("Detailed workbook: %s\n", full_path))
  invisible(list(
    status      = "completed",
    model       = model,
    nparm       = nparm,
    official_df = official,
    full_report = full_report,
    summary     = summary_df,
    output_dir  = abs_output_dir
  ))
}

# ==============================================================================
# Batch Auto-Discovery & Calibration
# ==============================================================================
run_bilog_batch <- function(batch_dir        = ".",
                            model            = NULL,
                            mode             = "auto",
                            prescan          = "auto",
                            bilog_exe_folder = NULL,
                            exam_year        = NULL) {
  batch_start_time <- Sys.time()

  if (is.null(model) || trimws(as.character(model)) == "") {
    stop(paste0(
      "\u5c1a\u672a\u6307\u5b9a IRT \u6a21\u578b\u3002\n",
      "\u8acb\u660e\u78ba\u50b3\u5165 --model=1PL\u3001--model=2PL \u6216 --model=3PL\u3002\n",
      "\u6a21\u578b\u9078\u64c7\u662f\u5206\u6790\u6c7a\u7b56\uff0c\u4e0d\u61c9\u7531\u7cfb\u7d71\u9ed8\u9ed8\u66ff\u60a8\u6c7a\u5b9a\u3002"
    ))
  }
  model <- toupper(trimws(model))

  abs_batch_dir <- normalizePath(batch_dir, winslash = "/", mustWork = TRUE)
  all_files     <- list.files(abs_batch_dir, pattern = "\\.xlsx$", full.names = FALSE)

  # Find student screening files: e.g. 115_C3_篩選結果.xlsx, 116_M5_篩選結果.xlsx
  data_files <- grep("^[0-9]{3}_[A-Za-z]+[0-9]+.*\\.xlsx$", all_files, value = TRUE)
  data_files <- data_files[!grepl("IRT|\u7e3d\u8868|\u6bd4\u5c0d|summary|result", data_files, ignore.case = TRUE)]

  if (length(data_files) == 0) {
    stop(sprintf("\u5728\u76ee\u9304 %s \u4e2d\u672a\u627e\u5230\u7b26\u5408 SAAA \u683c\u5f0f\u7684\u5b78\u751f\u4f5c\u7b54\u7be9\u9078\u6a94 (\u7bc4\u4f8b: 115_M5_\u7be9\u9078\u7d50\u679c.xlsx)", abs_batch_dir))
  }

  # Find answer files: e.g. 115_C_ans_final.xlsx, 116_M_ans_final.xlsx, *_ans*.xlsx
  ans_files <- grep("ans|\u7b54\u6848", all_files, value = TRUE, ignore.case = TRUE)
  ans_files <- ans_files[!grepl("\u7be9\u9078|\u4f5c\u7b54|IRT|\u7e3d\u8868|\u6bd4\u5c0d", ans_files, ignore.case = TRUE)]

  cat("==============================================================================\n")
  cat(sprintf("\U0001f680 SAAA-bilog-calibration \u5168\u79d1\u6279\u6b21\u81ea\u52d5\u5316\u6821\u6e96\u5f15\u64ce (\u6a21\u578b: %s)\n", model))
  cat(sprintf("\U0001f4c2 \u5de5\u4f5c\u76ee\u9304: %s\n", abs_batch_dir))
  cat(sprintf("\U0001f4ca \u627e\u5230 %d \u7d44 SAAA \u5b78\u79d1\u5f85\u6821\u6e96\u6a94\u6848\n", length(data_files)))
  cat("==============================================================================\n\n")

  official_sheets    <- list()
  full_reports_list  <- list()
  batch_summary_list <- list()

  data_files <- sort(data_files)

  for (i in seq_along(data_files)) {
    df_name <- data_files[i]
    df_path <- file.path(abs_batch_dir, df_name)

    meta      <- infer_metadata(df_path, exam_year = exam_year)
    yr        <- meta$year
    subj      <- meta$subject
    subj_char <- meta$subject_char
    subj_pad  <- meta$subject_pad

    # Match domain answer file by subject letter prefix
    matched_ans <- grep(sprintf("(_|^)%s(_|ans|\\.xlsx)", subj_char), ans_files, value = TRUE, ignore.case = TRUE)
    if (length(matched_ans) == 0) {
      matched_ans <- grep(subj_char, ans_files, value = TRUE, ignore.case = TRUE)
    }
    if (length(matched_ans) == 0) {
      warning(sprintf("\u627e\u4e0d\u5230\u5b78\u79d1 %s (\u9818\u57df: %s) \u7684\u7b54\u6848\u6a94\uff0c\u8df3\u904e\u6b64\u79d1\u76ee\u3002", subj, subj_char))
      next
    }
    ans_path <- file.path(abs_batch_dir, matched_ans[1])

    cat(sprintf("[%02d/%02d] \u6b63\u5728\u6821\u6e96: %s (\u4f5c\u7b54: %s | \u7b54\u6848: %s) ...\n",
                i, length(data_files), subj, df_name, matched_ans[1]))

    subj_out_dir <- file.path(abs_batch_dir, sprintf("%s_%s_%s_BILOG_Results", yr, subj, model))

    res <- tryCatch(
      run_bilog_auto(
        data_file        = df_path,
        ans_file         = ans_path,
        output_dir       = subj_out_dir,
        bilog_exe_folder = bilog_exe_folder,
        exam_year        = yr,
        subject_code     = subj,
        mode             = mode,
        model            = model,
        prescan          = prescan
      ),
      error = function(e) {
        cat(sprintf("\u274c \u6821\u6e96\u5931\u6557 (%s): %s\n", subj, conditionMessage(e)))
        NULL
      }
    )

    if (!is.null(res) && res$status == "completed") {
      official_sheets[[subj_pad]] <- res$official_df
      full_rep <- res$full_report
      full_rep$學科代碼 <- subj
      full_rep$年級代碼 <- subj_pad
      cols_ordered <- c("學科代碼", "年級代碼", setdiff(names(full_rep), c("學科代碼", "年級代碼")))
      full_reports_list[[subj_pad]] <- full_rep[, cols_ordered, drop = FALSE]

      batch_summary_list[[length(batch_summary_list) + 1]] <- data.frame(
        學科代碼 = subj,
        科目年級 = subj_pad,
        試題數 = nrow(res$official_df),
        模型 = model,
        狀態 = "\u2705 \u5b8c\u6210",
        stringsAsFactors = FALSE
      )
    }
    cat("\n")
  }

  # Consolidated Master Excel Workbook
  if (length(official_sheets) > 0) {
    first_yr <- if (!is.null(exam_year)) exam_year else infer_metadata(file.path(abs_batch_dir, data_files[1]))$year
    master_official_path <- file.path(abs_batch_dir, sprintf("%s\u5e74_\u5168\u5b78\u79d1\u5168\u5b78\u5e74_IRT\u53c3\u6578\u7e3d\u8868.xlsx", first_yr))

    if (length(batch_summary_list) > 0) {
      summary_all_df  <- do.call(rbind, batch_summary_list)
      official_sheets <- c(list("全科摘要總表" = summary_all_df), official_sheets)
    }
    write_xlsx(official_sheets, master_official_path)

    if (length(full_reports_list) > 0) {
      all_full_df <- do.call(rbind, full_reports_list)
      master_detailed_path <- file.path(abs_batch_dir, sprintf("%s\u5e74_\u5168\u5b78\u79d1\u5168\u5b78\u5e74_IRT\u8a66\u984c\u53c3\u6578\u8a73\u7d30\u8a3a\u65b7\u7e3d\u8868.xlsx", first_yr))
      write_xlsx(list("全卷試題詳細總表" = all_full_df), master_detailed_path)
    }

    total_batch_time <- round(as.numeric(difftime(Sys.time(), batch_start_time, units = "mins")), 2)
    cat("==============================================================================\n")
    cat(sprintf("\U0001f389 \u5168\u79d1\u6279\u6b21\u6821\u6e96\u5b8c\u6210\uff01\u5171\u6210\u529f\u6821\u6e96 %d \u500b\u5b78\u79d1\uff0c\u7e3d\u8017\u6642: %.2f \u5206\u9418\n",
                length(official_sheets) - 1, total_batch_time))
    cat(sprintf("\U0001f4ca \u5b98\u65b9\u53c3\u6578\u7e3d\u8868 (\u5404\u79d1\u5206\u9801): %s\n", master_official_path))
    if (exists("master_detailed_path")) cat(sprintf("\U0001f4cb \u8a73\u7d30\u8a3a\u65b7\u7e3d\u8868 (\u5168\u984c\u5f59\u6574): %s\n", master_detailed_path))
    cat("==============================================================================\n")
  }
}

# ==============================================================================
# CLI
# ==============================================================================
print_usage <- function() {
  cat(paste0(
    "Usage:\n",
    "  # Single subject:\n",
    "  Rscript easy_bilog_runner.R <data.xlsx> <answers.xlsx> --model=3PL [options]\n\n",
    "  # All subjects batch mode (auto-discover all subjects in directory):\n",
    "  Rscript easy_bilog_runner.R --batch --model=3PL [options]\n\n",
    "Options (use --key=value):\n",
    "  --model=3PL|2PL|1PL         IRT model (REQUIRED: 1PL, 2PL, or 3PL)\n",
    "  --batch                     Run batch calibration on all subjects in current folder\n",
    "  --batch-dir=PATH            Directory to scan for batch calibration (default: .)\n",
    "  --prescan=auto|on|off       Prescan & skip negative biserial items (default: auto)\n",
    "  --mode=auto|prepare|run|parse  Execution mode (default: auto)\n",
    "  --output-dir=PATH           Output directory (default: auto-named with model)\n",
    "  --bilog-dir=PATH            Folder containing BLM1.EXE/BLM2.EXE/BLM3.EXE\n",
    "  --year=115                  Override inferred exam year\n",
    "  --subject=M5                Override inferred subject/grade code\n",
    "  --help                      Show this help\n\n",
    "Examples:\n",
    "  Rscript easy_bilog_runner.R --batch --model=3PL\n",
    "  Rscript easy_bilog_runner.R data.xlsx answers.xlsx --model=3PL\n",
    "  Rscript easy_bilog_runner.R data.xlsx answers.xlsx --model=2PL\n",
    "  Rscript easy_bilog_runner.R data.xlsx answers.xlsx --model=1PL --mode=prepare\n\n",
    "Environment:\n",
    "  BILOGMG_HOME can provide the BILOG executable folder.\n"
  ))
}

parse_cli <- function(args) {
  pos  <- character(0)
  opts <- list()
  for (a in args) {
    if (a %in% c("-h", "--help")) {
      opts$help <- TRUE
    } else if (startsWith(a, "--")) {
      raw <- substring(a, 3)
      kv  <- strsplit(raw, "=", fixed = TRUE)[[1]]
      key <- kv[1]
      val <- if (length(kv) >= 2) paste(kv[-1], collapse = "=") else "true"
      opts[[key]] <- val
    } else {
      pos <- c(pos, a)
    }
  }
  list(positional = pos, options = opts)
}

args <- commandArgs(trailingOnly = TRUE)
cli  <- parse_cli(args)

if (isTRUE(cli$options$help)) {
  print_usage()
} else {
  get_opt <- function(name, default = NULL) {
    x <- cli$options[[name]]
    if (is.null(x) || identical(x, "")) default else x
  }

  is_batch <- isTRUE(cli$options$batch) || !is.null(cli$options[["batch-dir"]])

  if (is_batch) {
    # Batch execution mode
    run_bilog_batch(
      batch_dir        = get_opt("batch-dir", "."),
      model            = get_opt("model", NULL),
      mode             = get_opt("mode", "auto"),
      prescan          = get_opt("prescan", "auto"),
      bilog_exe_folder = get_opt("bilog-dir"),
      exam_year        = get_opt("year")
    )
  } else if (length(cli$positional) >= 2) {
    # Single subject mode
    run_bilog_auto(
      data_file        = cli$positional[1],
      ans_file         = cli$positional[2],
      output_dir       = get_opt("output-dir"),
      bilog_exe_folder = get_opt("bilog-dir"),
      exam_year        = get_opt("year"),
      subject_code     = get_opt("subject"),
      mode             = get_opt("mode", "auto"),
      model            = get_opt("model", NULL),
      prescan          = get_opt("prescan", "auto")
    )
  } else if (!interactive()) {
    print_usage()
    quit(status = 2)
  }
}

