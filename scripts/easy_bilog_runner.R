#!/usr/bin/env Rscript

# BILOG-MG 3PL calibration runner.
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

COL_ABSENT <- "\u7f3a\u8003"
COL_INVALID <- "\u7121\u6548"
COL_SERIAL <- "\u7e3d\u6d41\u6c34\u865f"
COL_ITEM_NO <- "\u984c\u865f"
COL_ITEM_CODE <- "\u8a66\u984c\u4ee3\u78bc"
COL_STD_ANSWER <- "\u6a19\u6e96\u7b54\u6848"
COL_PASS_RATE <- "\u901a\u904e\u7387(P\u503c)"
COL_CITC <- "\u6821\u6b63\u5f8c\u8a66\u984c\u7e3d\u5206\u76f8\u95dc(CITC)"
COL_CORE_DIM <- "\u6838\u5fc3\u5167\u5bb9\u5411\u5ea6"
COL_COG_DIM <- "\u8a8d\u77e5\u6b77\u7a0b\u5411\u5ea6"
COL_ALT_DIM <- "\u8a55\u91cf\u6307\u6a19\u5411\u5ea6"
COL_A <- "\u9451\u5225\u5ea6(a)"
COL_B <- "\u96e3\u5ea6(b)"
COL_C <- "\u731c\u6e2c\u5ea6(c)"
COL_PBIS <- "\u9ede\u4e8c\u7cfb\u5217\u76f8\u95dc(PBIS)"
COL_BIS <- "\u4e8c\u7cfb\u5217\u76f8\u95dc(BIS)"
COL_POINT_BIS <- "\u9ede\u4e8c\u76f8\u95dc"
COL_SE_A <- "\u9451\u5225\u5ea6\u6a19\u6e96\u8aa4(SE_a)"
COL_SE_B <- "\u96e3\u5ea6\u6a19\u6e96\u8aa4(SE_b)"
COL_SE_C <- "\u731c\u6e2c\u5ea6\u6a19\u6e96\u8aa4(SE_c)"
COL_QC <- "\u54c1\u8cea\u6aa2\u6838"
SHEET_ANSWER <- "\u7b54\u6848"
SHEET_DIM_CODE <- "\u8a55\u91cf\u6307\u6a19\u4ee3"
SHEET_DIM <- "\u5411\u5ea6"
SHEET_OFFICIAL <- "\u5de5\u4f5c\u88681"
SHEET_FULL <- "BILOG\u8a66\u984c\u53c3\u6578\u8207\u53e4\u5178\u6307\u6a19\u7e3d\u8868"
SHEET_SUMMARY <- "\u8a66\u984c\u53c3\u6578\u63cf\u8ff0\u6027\u7d71\u8a08"

as_scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x[1]) || trimws(as.character(x[1])) == "") return(NULL)
  trimws(as.character(x[1]))
}

infer_metadata <- function(data_file, exam_year = NULL, subject_code = NULL) {
  base <- basename(data_file)
  subject_code <- as_scalar_chr(subject_code)
  exam_year <- as_scalar_chr(exam_year)

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
  grade_num <- as.integer(sm[3])
  if (is.na(grade_num)) stop("Invalid grade number in subject code.")
  subject_pad <- sprintf("%s%02d", subject_char, grade_num)

  if (is.null(exam_year)) {
    ym <- regmatches(base, regexec("^([0-9]{3})[_-]", base, perl = TRUE))[[1]]
    if (length(ym) < 2) {
      stop("Cannot infer exam year from filename. Pass --year=... (example: 115).")
    }
    exam_year <- ym[2]
  }

  list(
    year = exam_year,
    subject = subject_code,
    subject_char = subject_char,
    grade = grade_num,
    subject_pad = subject_pad
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
  nms <- names(ans_df)
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
    cog_dim = rep(NA_character_, length(item_nums)),
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
  idx <- match(item_nums, raw_item)
  dim_cols <- names(raw)
  subject_cols <- dim_cols[grepl(toupper(subject), toupper(dim_cols), fixed = TRUE)]

  grade_map <- c(
    "3" = "\u4e09\u5e74\u7d1a",
    "4" = "\u56db\u5e74\u7d1a",
    "5" = "\u4e94\u5e74\u7d1a",
    "6" = "\u516d\u5e74\u7d1a",
    "7" = "\u4e03\u5e74\u7d1a",
    "8" = "\u516b\u5e74\u7d1a"
  )
  grade_name <- unname(grade_map[as.character(grade_num)])

  copy_col <- function(col_name) {
    vals <- rep(NA_character_, length(item_nums))
    ok <- !is.na(idx)
    vals[ok] <- as.character(raw[[col_name]][idx[ok]])
    vals
  }

  if (length(subject_cols) >= 2) {
    out$core_dim <- copy_col(subject_cols[1])
    out$cog_dim <- copy_col(subject_cols[2])
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

parse_par_file <- function(path, n_items) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) <= 4) stop(sprintf("PAR file is too short: %s", path))
  candidates <- lines[5:length(lines)]
  records <- list()

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
    stop(sprintf("Could parse only %d/%d item rows from PAR file: %s", length(records), n_items, path))
  }
  out <- do.call(rbind, records)
  colnames(out) <- c("a", "se_a", "b", "se_b", "c", "se_c")
  out
}

parse_ph1_file <- function(path, n_items) {
  pbis <- rep(NA_real_, n_items)
  bis <- rep(NA_real_, n_items)
  if (!file.exists(path)) {
    warning(sprintf("PH1 file not found; PBIS/BIS will be NA: %s", path))
    return(list(pbis = pbis, bis = bis))
  }

  lines <- readLines(path, warn = FALSE)
  header <- grep("ITEM\\s+NAME\\s+#TRIED\\s+#RIGHT\\s+PCT\\s+LOGIT\\s+PEARSON\\s+BISERIAL", lines)
  if (length(header) == 0) {
    warning("PH1 statistics table header not found; PBIS/BIS will be NA.")
    return(list(pbis = pbis, bis = bis))
  }

  rec <- list()
  if (header[1] < length(lines)) {
    for (line in lines[(header[1] + 1):length(lines)]) {
      parts <- unlist(strsplit(trimws(line), "[[:space:]]+"))
      if (length(parts) < 8) next
      item_index <- suppressWarnings(as.numeric(parts[1]))
      vals <- suppressWarnings(as.numeric(parts[c(7, 8)]))
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
    n <- min(nrow(mat), n_items)
    pbis[seq_len(n)] <- mat[seq_len(n), 1]
    bis[seq_len(n)] <- mat[seq_len(n), 2]
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
  out <- list()
  for (line in lines) {
    pos <- regexpr("=", line, fixed = TRUE)[1]
    if (is.na(pos) || pos < 1) next
    key <- substr(line, 1, pos - 1)
    value <- substr(line, pos + 1, nchar(line))
    out[[key]] <- value
  }
  out
}

file_md5 <- function(path) {
  unname(as.character(tools::md5sum(path)[1]))
}

run_bilog_stages <- function(bilog_exe_folder, blm_prefix, output_dir) {
  stages <- c("BLM1.EXE", "BLM2.EXE", "BLM3.EXE")
  exes <- file.path(bilog_exe_folder, stages)
  missing <- stages[!file.exists(exes)]
  if (length(missing) > 0) stop(sprintf("Missing BILOG executable(s): %s", paste(missing, collapse = ", ")))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(output_dir)

  elapsed <- system.time({
    for (i in seq_along(exes)) {
      log_path <- file.path(output_dir, sprintf("%s.log", tools::file_path_sans_ext(stages[i])))
      status <- tryCatch(
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

run_bilog_auto <- function(data_file,
                           ans_file,
                           output_dir = NULL,
                           bilog_exe_folder = NULL,
                           exam_year = NULL,
                           subject_code = NULL,
                           mode = "auto") {
  start_time <- Sys.time()
  mode <- tolower(mode)
  if (!(mode %in% c("auto", "prepare", "run", "parse"))) {
    stop("mode must be one of: auto, prepare, run, parse")
  }
  if (!file.exists(data_file)) stop(sprintf("Data file not found: %s", data_file))
  if (!file.exists(ans_file)) stop(sprintf("Answer file not found: %s", ans_file))

  meta <- infer_metadata(data_file, exam_year, subject_code)
  exam_year <- meta$year
  subject <- meta$subject
  grade_num <- meta$grade
  subject_pad <- meta$subject_pad

  if (is.null(output_dir) || trimws(output_dir) == "") {
    output_dir <- sprintf("%s_%s_BILOG_Results", exam_year, subject)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  abs_output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  summary_path <- file.path(abs_output_dir, "BILOG_RUN_SUMMARY.txt")
  data_md5 <- file_md5(data_file)
  answer_md5 <- file_md5(ans_file)

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
  cat(sprintf("Exam year: %s | subject: %s | normalized: %s\n", exam_year, subject, subject_pad))
  cat(sprintf("Output directory: %s\n", abs_output_dir))

  sheets <- excel_sheets(ans_file)
  if (length(sheets) == 0) stop("Answer workbook has no sheets.")
  answer_matches <- grep(SHEET_ANSWER, sheets, fixed = TRUE, value = TRUE)
  answer_sheet <- if (length(answer_matches) > 0) answer_matches[1] else sheets[1]
  ans_df <- read_excel(ans_file, sheet = answer_sheet)
  if (nrow(ans_df) == 0 || ncol(ans_df) == 0) stop("Answer sheet is empty.")
  ans_col <- choose_answer_column(ans_df, subject)
  raw_answers <- ans_df[[ans_col]]
  answer_chars <- trimws(as.character(raw_answers))
  valid_item_idx <- which(!is.na(raw_answers) & !is.na(answer_chars) & answer_chars != "" & answer_chars != "\u4e0d\u4e88\u8a08\u5206")
  if (length(valid_item_idx) < 2) stop("Fewer than 2 scorable items were found in the answer column.")
  item_nums <- valid_item_idx
  n_items <- length(item_nums)
  std_answers <- as.character(raw_answers[item_nums])

  dim_info <- extract_dimensions(ans_file, sheets, item_nums, subject, grade_num)

  raw_students <- read_excel(data_file)
  if (nrow(raw_students) == 0) stop("Student workbook has no rows.")
  valid_mask <- rep(TRUE, nrow(raw_students))
  if (all(c(COL_ABSENT, COL_INVALID) %in% names(raw_students))) {
    absent <- suppressWarnings(as.numeric(raw_students[[COL_ABSENT]]))
    invalid <- suppressWarnings(as.numeric(raw_students[[COL_INVALID]]))
    valid_mask <- !is.na(absent) & !is.na(invalid) & absent == 0 & invalid == 0
  } else {
    warning("Absent/invalid columns were not both present; no students were filtered on those flags.")
  }
  valid_students <- raw_students[valid_mask, , drop = FALSE]
  source_rows <- which(valid_mask)
  n_valid <- nrow(valid_students)
  if (n_valid < 3) stop("Fewer than 3 valid students remain after filtering.")

  q_cols <- paste0("Q", item_nums)
  missing_q <- setdiff(q_cols, names(valid_students))
  if (length(missing_q) > 0) stop(sprintf("Missing response column(s): %s", paste(missing_q, collapse = ", ")))

  q_char <- do.call(cbind, lapply(q_cols, function(nm) normalize_response_column(valid_students[[nm]], nm)))
  colnames(q_char) <- q_cols
  num_mat <- matrix(as.numeric(q_char), nrow = n_valid, ncol = n_items, dimnames = list(NULL, q_cols))
  num_mat_clean <- num_mat
  num_mat_clean[num_mat_clean == 9] <- NA_real_
  p_values <- colMeans(num_mat_clean, na.rm = TRUE)

  item_rest_corr <- vapply(seq_len(n_items), function(j) {
    other <- num_mat_clean[, -j, drop = FALSE]
    rest <- rowSums(other, na.rm = TRUE)
    rest[rowSums(!is.na(other)) == 0] <- NA_real_
    safe_cor(num_mat_clean[, j], rest)
  }, numeric(1))

  ctt_base <- data.frame(
    q_code = q_cols,
    item_num = item_nums,
    std_answer = std_answers,
    pass_rate = round(p_values, 4),
    citc = round(item_rest_corr, 4),
    stringsAsFactors = FALSE
  )
  ctt_base$core_dim <- dim_info$core_dim[match(item_nums, dim_info$item_num)]
  ctt_base$cog_dim <- dim_info$cog_dim[match(item_nums, dim_info$item_num)]

  if (COL_SERIAL %in% names(valid_students)) {
    raw_ids <- as.character(valid_students[[COL_SERIAL]])
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

  resp_strings <- apply(q_char, 1, paste0, collapse = "")
  data_lines <- paste0(ids, " ", resp_strings)
  dat_filename <- sprintf("%s_data.dat", subject_pad)
  dat_path <- file.path(abs_output_dir, dat_filename)
  writeLines(data_lines, dat_path, useBytes = TRUE)

  omit_filename <- "OMITKEY.dat"
  omit_path <- file.path(abs_output_dir, omit_filename)
  writeLines(paste0(strrep(" ", 7), strrep("9", n_items)), omit_path, useBytes = TRUE)

  blm_prefix <- sprintf("%s%s", exam_year, subject_pad)
  blm_filename <- sprintf("%s.BLM", blm_prefix)
  blm_path <- file.path(abs_output_dir, blm_filename)
  par_filename <- sprintf("%s_IP.PAR", subject_pad)
  sco_filename <- sprintf("%s_SCORE.SCO", subject_pad)
  par_path <- file.path(abs_output_dir, par_filename)
  ph1_path <- file.path(abs_output_dir, sprintf("%s.PH1", blm_prefix))

  inames <- sprintf("I%03d", seq_len(n_items))
  iname_clause <- sprintf("INAME=(%s(1)%s)", inames[1], inames[n_items])
  format_str <- sprintf("(6A1,1X,%dA1)", n_items)
  blm_content <- c(
    "",
    "",
    ">COMMENTS",
    sprintf(">GLOBAL DFNAME='%s', NPARM=3, LOGISTIC, OMITS, SAVE;", dat_filename),
    sprintf(">SAVE PARM='%s', SCORE='%s';", par_filename, sco_filename),
    sprintf(">LENGTH NITEMS=%d;", n_items),
    sprintf(">INPUT NTOTAL=%d, NALT=4, NIDCH=6, OFNAME='%s';", n_items, omit_filename),
    sprintf(">ITEMS INUM=(1(1)%d), %s;", n_items, iname_clause),
    sprintf(">TEST TNAME=E, INUMBER=(1(1)%d),", n_items),
    sprintf(" FIX=(0(0)%d);", n_items),
    format_str,
    ">CALIB NQPT=51, CYCLES=100, NEWTON=50, REFERENCE=1,",
    " CHI=(25,50), NOADJUST, FIXED;",
    ">SCORE NOPRINT, METHOD=2, IDIST=3, RSCTYPE=0, INFO=2, POP;",
    ""
  )
  writeLines(blm_content, blm_path, useBytes = TRUE)

  exe_paths <- file.path(bilog_exe_folder, c("BLM1.EXE", "BLM2.EXE", "BLM3.EXE"))
  bilog_available <- dir.exists(bilog_exe_folder) && all(file.exists(exe_paths))
  effective_mode <- mode
  if (mode == "auto") {
    # Never auto-parse an existing PAR file: it may be stale or belong to another run.
    effective_mode <- if (bilog_available) "run" else "prepare"
  }

  common_summary <- list(
    requested_mode = mode,
    effective_mode = effective_mode,
    exam_year = exam_year,
    subject = subject,
    normalized_subject = subject_pad,
    item_count = n_items,
    valid_student_count = n_valid,
    data_file = normalizePath(data_file, winslash = "/", mustWork = TRUE),
    answer_file = normalizePath(ans_file, winslash = "/", mustWork = TRUE),
    data_md5 = data_md5,
    answer_md5 = answer_md5,
    blm_file = blm_path,
    dat_file = dat_path,
    omit_file = omit_path
  )

  if (effective_mode == "prepare") {
    write_run_summary(summary_path, c(common_summary, list(status = "prepared_only", reason = "BILOG executables and PAR output are unavailable")))
    cat("Prepared BILOG native input files only. Run BILOG-MG externally, then rerun with --mode=parse.\n")
    return(invisible(list(status = "prepared_only", output_dir = abs_output_dir, summary = summary_path)))
  }

  if (effective_mode == "run") {
    if (!bilog_available) stop(sprintf("BILOG executables not found in: %s", bilog_exe_folder))
    elapsed_bilog <- run_bilog_stages(bilog_exe_folder, blm_prefix, abs_output_dir)
    cat(sprintf("BILOG stages completed in %.2f seconds.\n", elapsed_bilog))
  }

  if (!file.exists(par_path)) {
    stop(sprintf("PAR output not found: %s. If calibration was run elsewhere, copy the PAR/PH1 files into the output directory and use --mode=parse.", par_path))
  }

  parsed <- parse_par_file(par_path, n_items)
  ph1 <- parse_ph1_file(ph1_path, n_items)
  pbis_vec <- ph1$pbis
  bis_vec <- ph1$bis
  a_vals <- round(parsed[, "a"], 5)
  b_vals <- round(parsed[, "b"], 5)
  c_vals <- round(parsed[, "c"], 5)
  pbis_vals <- round(pbis_vec, 3)

  flag_vec <- vapply(seq_len(n_items), function(i) {
    flags <- character(0)
    if (!is.na(a_vals[i]) && a_vals[i] < 0.3) flags <- c(flags, "low discrimination (a<0.3)")
    if (!is.na(b_vals[i]) && abs(b_vals[i]) > 5) flags <- c(flags, "extreme difficulty (|b|>5)")
    if (!is.na(pbis_vals[i]) && pbis_vals[i] < 0) flags <- c(flags, "negative point-biserial (<0)")
    if (length(flags) == 0) "normal" else paste(flags, collapse = "; ")
  }, character(1))

  official <- data.frame(
    item_num = item_nums,
    a = a_vals,
    b = b_vals,
    c = c_vals,
    point_biserial = pbis_vals,
    check.names = FALSE
  )
  names(official) <- c(subject_pad, COL_A, COL_B, COL_C, COL_POINT_BIS)
  official_path <- file.path(abs_output_dir, sprintf("%s_%s_IRT\u53c3\u6578.xlsx", exam_year, subject_pad))
  write_xlsx(setNames(list(official), SHEET_OFFICIAL), official_path)

  full_report <- data.frame(
    q_code = ctt_base$q_code,
    item_num = ctt_base$item_num,
    std_answer = ctt_base$std_answer,
    pass_rate = ctt_base$pass_rate,
    core_dim = ctt_base$core_dim,
    cog_dim = ctt_base$cog_dim,
    a = round(parsed[, "a"], 4),
    b = round(parsed[, "b"], 4),
    c = round(parsed[, "c"], 4),
    pbis = round(pbis_vec, 4),
    bis = round(bis_vec, 4),
    citc = ctt_base$citc,
    se_a = round(parsed[, "se_a"], 4),
    se_b = round(parsed[, "se_b"], 4),
    se_c = round(parsed[, "se_c"], 4),
    qc = flag_vec,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  names(full_report) <- c(
    COL_ITEM_CODE, COL_ITEM_NO, COL_STD_ANSWER, COL_PASS_RATE,
    COL_CORE_DIM, COL_COG_DIM, COL_A, COL_B, COL_C,
    COL_PBIS, COL_BIS, COL_CITC, COL_SE_A, COL_SE_B, COL_SE_C, COL_QC
  )

  summary_metrics <- list(
    "a" = full_report[[COL_A]],
    "b" = full_report[[COL_B]],
    "c" = full_report[[COL_C]],
    "P" = full_report[[COL_PASS_RATE]],
    "PBIS" = full_report[[COL_PBIS]],
    "CITC" = full_report[[COL_CITC]]
  )
  summary_df <- data.frame(
    metric = names(summary_metrics),
    mean = vapply(summary_metrics, safe_stat, numeric(1), fun = mean),
    sd = vapply(summary_metrics, safe_stat, numeric(1), fun = stats::sd),
    min = vapply(summary_metrics, safe_stat, numeric(1), fun = min),
    max = vapply(summary_metrics, safe_stat, numeric(1), fun = max),
    check.names = FALSE
  )
  names(summary_df) <- c(
    "\u53c3\u6578\u6307\u6a19", "\u5e73\u5747\u6578", "\u6a19\u6e96\u5dee", "\u6700\u5c0f\u503c", "\u6700\u5927\u503c"
  )

  full_path <- file.path(abs_output_dir, sprintf("%s_BILOG_3PL_\u8a66\u984c\u53c3\u6578\u7e3d\u8868.xlsx", subject))
  write_xlsx(setNames(list(full_report, summary_df), c(SHEET_FULL, SHEET_SUMMARY)), full_path)
  csv_path <- file.path(abs_output_dir, sprintf("%s_BILOG_3PL_\u8a66\u984c\u53c3\u6578\u7e3d\u8868.csv", subject))
  write.csv(full_report, csv_path, row.names = FALSE, fileEncoding = "UTF-8")

  total_time <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 2)
  write_run_summary(summary_path, c(common_summary, list(
    status = "completed",
    official_excel = official_path,
    full_excel = full_path,
    csv = csv_path,
    par_file = par_path,
    ph1_file = ph1_path,
    elapsed_seconds = total_time
  )))

  cat(sprintf("Completed %s (%d items, %d valid students) in %.2f seconds.\n", subject, n_items, n_valid, total_time))
  cat(sprintf("Official five-column workbook: %s\n", official_path))
  cat(sprintf("Detailed workbook: %s\n", full_path))
  invisible(list(status = "completed", official_df = official, full_report = full_report, summary = summary_df, output_dir = abs_output_dir))
}

print_usage <- function() {
  cat(paste0(
    "Usage:\n",
    "  Rscript easy_bilog_runner.R <data.xlsx> <answers.xlsx> [options]\n\n",
    "Options (use --key=value):\n",
    "  --mode=auto|prepare|run|parse   Default: auto (run if BILOG exists; otherwise prepare)\n",
    "  --output-dir=PATH               Output directory\n",
    "  --bilog-dir=PATH                Folder containing BLM1.EXE/BLM2.EXE/BLM3.EXE\n",
    "  --year=115                      Override inferred exam year\n",
    "  --subject=M5                    Override inferred subject/grade code\n",
    "  --help                          Show this help\n\n",
    "Environment:\n",
    "  BILOGMG_HOME can provide the BILOG executable folder.\n"
  ))
}

parse_cli <- function(args) {
  pos <- character(0)
  opts <- list()
  for (a in args) {
    if (a %in% c("-h", "--help")) {
      opts$help <- TRUE
    } else if (startsWith(a, "--")) {
      raw <- substring(a, 3)
      kv <- strsplit(raw, "=", fixed = TRUE)[[1]]
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
cli <- parse_cli(args)
if (isTRUE(cli$options$help)) {
  print_usage()
} else if (length(cli$positional) >= 2) {
  get_opt <- function(name, default = NULL) {
    x <- cli$options[[name]]
    if (is.null(x) || identical(x, "")) default else x
  }
  run_bilog_auto(
    data_file = cli$positional[1],
    ans_file = cli$positional[2],
    output_dir = get_opt("output-dir"),
    bilog_exe_folder = get_opt("bilog-dir"),
    exam_year = get_opt("year"),
    subject_code = get_opt("subject"),
    mode = get_opt("mode", "auto")
  )
} else if (!interactive()) {
  print_usage()
  quit(status = 2)
}
