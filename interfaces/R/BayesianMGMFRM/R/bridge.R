.mgmfrm_session <- new.env(parent = emptyenv())
.mgmfrm_script <- function(name) system.file("julia", name, package = "BayesianMGMFRM", mustWork = TRUE)

.resolve_julia_bindir <- function(julia) {
  out <- tryCatch(
    system2(julia, c("--startup-file=no", "-e", shQuote("print(Sys.BINDIR)")), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0L)
  )
  if (length(out) >= 1L && nzchar(trimws(out[[1L]])) && dir.exists(trimws(out[[1L]]))) {
    return(normalizePath(trimws(out[[1L]]), mustWork = TRUE))
  }
  dirname(julia)
}

setup_mgmfrm <- function(project = file.path(tools::R_user_dir("BayesianMGMFRM", "cache"),
                                              "julia-dcc3c844"),
                         source_dir = NULL, julia = Sys.which("julia")) {
  if (!nzchar(julia)) stop("Install Julia 1.10.8 or later, or supply its executable path.")
  julia <- normalizePath(julia, mustWork = TRUE)
  julia_bindir <- .resolve_julia_bindir(julia)
  project <- normalizePath(project, mustWork = FALSE)
  script <- .mgmfrm_script("setup.jl")
  args <- c("--startup-file=no", shQuote(script), shQuote(project))
  if (!is.null(source_dir)) args <- c(args, shQuote(normalizePath(source_dir, mustWork = TRUE)))
  if (system2(julia, args) != 0L) stop("Julia project setup failed.")
  runtime <- list(julia = julia, julia_bindir = julia_bindir, project = normalizePath(project))
  .with_mgmfrm(runtime, NULL)
  .mgmfrm_session$runtime <- runtime
  invisible(runtime$project)
}

.with_mgmfrm <- function(runtime, expr) {
  if (is.null(runtime)) stop("Call setup_mgmfrm() in this R session first.")
  if (grepl("--project", Sys.getenv("JULIACONNECTOR_JULIAOPTS"), fixed = TRUE))
    stop("Remove the conflicting --project from JULIACONNECTOR_JULIAOPTS.")
  keys <- c("JULIA_BINDIR", "JULIA_PROJECT", "JULIA_LOAD_PATH", "JULIA_NUM_THREADS")
  old <- Sys.getenv(keys, unset = NA_character_)
  on.exit({
    for (key in keys) {
      if (is.na(old[[key]])) Sys.unsetenv(key) else do.call(Sys.setenv, setNames(list(old[[key]]), key))
    }
  })
  bindir <- if (!is.null(runtime$julia_bindir)) runtime$julia_bindir else dirname(runtime$julia)
  Sys.setenv(JULIA_BINDIR = bindir, JULIA_PROJECT = runtime$project,
             JULIA_LOAD_PATH = paste("@", "@stdlib", sep = .Platform$path.sep))
  if (is.na(old[["JULIA_NUM_THREADS"]]) || !nzchar(old[["JULIA_NUM_THREADS"]])) {
    Sys.setenv(JULIA_NUM_THREADS = "auto")
  }
  expected <- normalizePath(file.path(runtime$project, "Project.toml"))
  active <- JuliaConnectoR::juliaEval("realpath(Base.active_project())")
  if (!identical(normalizePath(active), expected))
    stop("A different Julia project is active. Use a fresh R session or stop your existing Julia connection.")
  JuliaConnectoR::juliaLet("if !isdefined(Main, :MGMFRMRBridge); Base.include(Main, path); end; nothing",
                           path = .mgmfrm_script("bridge.jl"))
  force(expr)
}

encode_mgmfrm_id <- function(x) {
  if (anyNA(x)) stop("Missing facet ID")
  if (is.factor(x)) x <- as.character(x)
  if (is.object(x) || !(is.character(x) || is.integer(x) || is.double(x)))
    stop("Use character, factor, or ordinary numeric facet IDs")
  if (is.character(x)) {
    x <- enc2utf8(x)
    if (any(!nzchar(x))) stop("Empty facet ID")
  } else if (any(!is.finite(x))) stop("Non-finite facet ID")
  labels <- sort(unique(x), method = "radix")
  list(index = match(x, labels), labels = labels)
}

.label_mgmfrm_parameters <- function(var_names, ids, step_owner = "item") {
  if (!length(var_names)) return(setNames(character(0L), character(0L)))
  id_roles <- names(ids)
  vapply(var_names, function(nm) {
    m_role <- regexec("^([A-Za-z0-9_]+)\\[([0-9]+)\\]$", nm)
    h_role <- regmatches(nm, m_role)[[1L]]
    if (length(h_role) == 3L) {
      role <- h_role[[2L]]
      idx <- as.integer(h_role[[3L]])
      if (role %in% id_roles && !is.na(idx) && idx >= 1L && idx <= length(ids[[role]]))
        return(paste0(role, "[", ids[[role]][[idx]], "]"))
      if (identical(role, "item") && !("item" %in% id_roles) && "criterion" %in% id_roles &&
          !is.na(idx) && idx >= 1L && idx <= length(ids$criterion))
        return(paste0("criterion[", ids$criterion[[idx]], "]"))
      if (identical(role, "consistency") && "rater" %in% id_roles &&
          !is.na(idx) && idx >= 1L && idx <= length(ids$rater))
        return(paste0("consistency[", ids$rater[[idx]], "]"))
      if (identical(role, "population_sd") && "group" %in% id_roles &&
          !is.na(idx) && idx >= 1L && idx <= length(ids$group))
        return(paste0("population_sd[", ids$group[[idx]], "]"))
    }
    m_pop <- regexec("^population\\[group\\[([0-9]+)\\]\\]$", nm)
    h_pop <- regmatches(nm, m_pop)[[1L]]
    if (length(h_pop) == 2L && "group" %in% id_roles) {
      idx <- as.integer(h_pop[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids$group))
        return(paste0("population[group[", ids$group[[idx]], "]]"))
    }
    m_int <- regexec("^interaction\\[([A-Za-z0-9_]+),([A-Za-z0-9_]+)\\]\\[([0-9]+),([0-9]+)\\]$", nm)
    h_int <- regmatches(nm, m_int)[[1L]]
    if (length(h_int) == 5L) {
      f1 <- h_int[[2L]]; f2 <- h_int[[3L]]
      i1 <- as.integer(h_int[[4L]]); i2 <- as.integer(h_int[[5L]])
      l1 <- if (f1 %in% id_roles && !is.na(i1) && i1 >= 1L && i1 <= length(ids[[f1]])) ids[[f1]][[i1]] else h_int[[4L]]
      l2 <- if (f2 %in% id_roles && !is.na(i2) && i2 >= 1L && i2 <= length(ids[[f2]])) ids[[f2]][[i2]] else h_int[[5L]]
      return(paste0("interaction[", f1, ",", f2, "][", l1, ",", l2, "]"))
    }
    m_foc <- regexec("^focal_dff\\[([A-Za-z0-9_]+)=([0-9]+),([A-Za-z0-9_]+)=([0-9]+)\\]$", nm)
    h_foc <- regmatches(nm, m_foc)[[1L]]
    if (length(h_foc) == 5L) {
      f1 <- h_foc[[2L]]; f2 <- h_foc[[4L]]
      i1 <- as.integer(h_foc[[3L]]); i2 <- as.integer(h_foc[[5L]])
      l1 <- if (f1 %in% id_roles && !is.na(i1) && i1 >= 1L && i1 <= length(ids[[f1]])) ids[[f1]][[i1]] else h_foc[[3L]]
      l2 <- if (f2 %in% id_roles && !is.na(i2) && i2 >= 1L && i2 <= length(ids[[f2]])) ids[[f2]][[i2]] else h_foc[[5L]]
      return(paste0("focal_dff[", f1, "=", l1, ",", f2, "=", l2, "]"))
    }
    m_step_glob <- regexec("^steps\\[:global,(-?[0-9]+)\\]$", nm)
    h_glob <- regmatches(nm, m_step_glob)[[1L]]
    if (length(h_glob) == 2L) return(paste0("steps[global,", h_glob[[2L]], "]"))
    it_key <- if ("item" %in% id_roles) "item" else if ("criterion" %in% id_roles) "criterion" else NULL
    step_default_owner <- if (!is.null(it_key)) it_key else "item"
    m_step1 <- regexec("^steps\\[([0-9]+),(-?[0-9]+)\\]$", nm)
    h1 <- regmatches(nm, m_step1)[[1L]]
    if (length(h1) == 3L) {
      idx <- as.integer(h1[[2L]])
      if (identical(step_owner, "global"))
        return(paste0("steps[global,", h1[[3L]], "]"))
      owner <- if (step_owner %in% id_roles) step_owner else step_default_owner
      if (owner %in% id_roles && !is.na(idx) && idx >= 1L && idx <= length(ids[[owner]]))
        return(paste0("steps[", ids[[owner]][[idx]], ",", h1[[3L]], "]"))
    }
    m_step2 <- regexec("^step\\[item=([0-9]+),([0-9]+)\\]$", nm)
    h2 <- regmatches(nm, m_step2)[[1L]]
    if (length(h2) == 3L && !is.null(it_key)) {
      idx <- as.integer(h2[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids[[it_key]]))
        return(paste0("step[", it_key, "=", ids[[it_key]][[idx]], ",", h2[[3L]], "]"))
    }
    m_step3 <- regexec("^step\\[([0-9]+),\\s*([0-9]+)\\]$", nm)
    h3 <- regmatches(nm, m_step3)[[1L]]
    if (length(h3) == 3L) {
      idx <- as.integer(h3[[2L]])
      owner <- if (step_owner %in% id_roles) step_owner else step_default_owner
      if (owner %in% id_roles && !is.na(idx) && idx >= 1L && idx <= length(ids[[owner]]))
        return(paste0("step[", ids[[owner]][[idx]], ", ", h3[[3L]], "]"))
    }
    m_pdim <- regexec("^person\\[([0-9]+),\\s*dim=([0-9]+)\\]$", nm)
    h_pdim <- regmatches(nm, m_pdim)[[1L]]
    if (length(h_pdim) == 3L && "person" %in% id_roles) {
      idx <- as.integer(h_pdim[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids$person))
        return(paste0("person[", ids$person[[idx]], ", dim=", h_pdim[[3L]], "]"))
    }
    m_ldim <- regexec("^(loading|standardized_loading)\\[([0-9]+),\\s*dim=([0-9]+)\\]$", nm)
    h_ldim <- regmatches(nm, m_ldim)[[1L]]
    if (length(h_ldim) == 4L && !is.null(it_key)) {
      idx <- as.integer(h_ldim[[3L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids[[it_key]]))
        return(paste0(h_ldim[[2L]], "[", ids[[it_key]][[idx]], ", dim=", h_ldim[[4L]], "]"))
    }
    m_idisc <- regexec("^item_discrimination\\[item=([0-9]+)\\]$", nm)
    h_idisc <- regmatches(nm, m_idisc)[[1L]]
    if (length(h_idisc) == 2L && "item" %in% id_roles) {
      idx <- as.integer(h_idisc[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids$item))
        return(paste0("item_discrimination[item=", ids$item[[idx]], "]"))
    }
    m_rcons <- regexec("^rater_consistency\\[rater=([0-9]+)\\]$", nm)
    h_rcons <- regmatches(nm, m_rcons)[[1L]]
    if (length(h_rcons) == 2L && "rater" %in% id_roles) {
      idx <- as.integer(h_rcons[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids$rater))
        return(paste0("rater_consistency[rater=", ids$rater[[idx]], "]"))
    }
    m_rstep <- regexec("^rater_step\\[rater=([0-9]+),m=([0-9]+)\\]$", nm)
    h_rstep <- regmatches(nm, m_rstep)[[1L]]
    if (length(h_rstep) == 3L && "rater" %in% id_roles) {
      idx <- as.integer(h_rstep[[2L]])
      if (!is.na(idx) && idx >= 1L && idx <= length(ids$rater))
        return(paste0("rater_step[rater=", ids$rater[[idx]], ",m=", h_rstep[[3L]], "]"))
    }
    nm
  }, character(1L), USE.NAMES = TRUE)
}

.rows_to_df <- function(rows) {
  if (is.null(rows) || !length(rows)) return(data.frame())
  if (is.data.frame(rows)) return(rows)
  if (!is.list(rows[[1L]])) rows <- list(rows)
  col_names <- character(0L)
  for (r in rows) {
    for (nm in names(r)) {
      val <- r[[nm]]
      if (is.null(val) || (!is.list(val) && length(val) <= 1L) ||
          (is.list(val) && "value" %in% names(val))) {
        if (!(nm %in% col_names)) col_names <- c(col_names, nm)
      }
    }
  }
  if (!length(col_names)) return(data.frame())
  cols <- lapply(setNames(col_names, col_names), function(nm) {
    vals <- lapply(rows, function(r) {
      v <- r[[nm]]
      if (is.list(v) && "value" %in% names(v)) v <- v$value
      if (is.null(v) || !length(v)) NA else v[[1L]]
    })
    types <- vapply(vals, function(v) {
      if (identical(v, NA)) "na"
      else if (is.logical(v)) "logical"
      else if (is.integer(v)) "integer"
      else if (is.numeric(v)) "double"
      else "character"
    }, character(1L))
    non_na <- types[types != "na"]
    if (!length(non_na)) return(rep(NA_real_, length(vals)))
    if (all(non_na == "logical")) return(vapply(vals, function(v) if (identical(v, NA)) NA else as.logical(v), logical(1L)))
    if (all(non_na == "integer")) return(vapply(vals, function(v) if (identical(v, NA)) NA_integer_ else as.integer(v), integer(1L)))
    if (all(non_na %in% c("integer", "double"))) return(vapply(vals, function(v) if (identical(v, NA)) NA_real_ else as.double(v), double(1L)))
    vapply(vals, function(v) if (identical(v, NA)) NA_character_ else as.character(v), character(1L))
  })
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

.summarize_bayesian_draws <- function(draws, param_labels = NULL, level = 0.95) {
  arr <- unclass(draws)
  d <- dim(arr)
  var_names <- dimnames(draws)[[3L]]
  if (is.null(param_labels)) param_labels <- setNames(var_names, var_names)
  alpha <- (1 - level) / 2
  n_var <- d[[3L]]
  means <- numeric(n_var)
  sds <- numeric(n_var)
  lows <- numeric(n_var)
  highs <- numeric(n_var)
  rhats <- numeric(n_var)
  ess_b <- numeric(n_var)
  ess_t <- numeric(n_var)
  mcses <- numeric(n_var)
  for (k in seq_len(n_var)) {
    mat <- matrix(arr[, , k], nrow = d[[1L]], ncol = d[[2L]])
    vec <- as.double(mat)
    means[[k]] <- mean(vec)
    sds[[k]] <- stats::sd(vec)
    qs <- stats::quantile(vec, probs = c(alpha, 1 - alpha), names = FALSE)
    lows[[k]] <- qs[[1L]]
    highs[[k]] <- qs[[2L]]
    rhats[[k]] <- as.double(posterior::rhat(mat))
    ess_b[[k]] <- as.double(posterior::ess_bulk(mat))
    ess_t[[k]] <- as.double(posterior::ess_tail(mat))
    mcses[[k]] <- as.double(posterior::mcse_mean(mat))
  }
  data.frame(
    variable = var_names,
    label = unname(param_labels[var_names]),
    mean = means,
    sd = sds,
    lower = lows,
    upper = highs,
    rhat = rhats,
    ess_bulk = ess_b,
    ess_tail = ess_t,
    mcse_mean = mcses,
    stringsAsFactors = FALSE
  )
}

.vcov_from_draws <- function(draws) {
  arr <- unclass(draws)
  d <- dim(arr)
  var_names <- dimnames(draws)[[3L]]
  flat <- matrix(arr, nrow = d[[1L]] * d[[2L]], ncol = d[[3L]])
  if (d[[3L]] == 1L) {
    v <- matrix(stats::cov(flat), nrow = 1L, ncol = 1L)
  } else {
    v <- stats::cov(flat)
  }
  dimnames(v) <- list(var_names, var_names)
  v
}

.format_fit_statistics <- function(raw_fs, ids) {
  if (is.null(raw_fs) || !length(raw_fs)) return(list())
  out <- list()
  for (fn in names(raw_fs)) {
    df <- .rows_to_df(raw_fs[[fn]])
    if (nrow(df) && "level" %in% names(df) && fn %in% names(ids) && is.numeric(df$level)) {
      idx <- as.integer(df$level)
      valid <- !is.na(idx) & idx >= 1L & idx <= length(ids[[fn]])
      df$level_index <- idx
      lbl <- as.character(df$level)
      lbl[valid] <- as.character(ids[[fn]][idx[valid]])
      df$level <- lbl
      if (identical(fn, "person") && "person" %in% names(df) && is.numeric(df$person)) {
        df$person <- lbl
      }
    }
    out[[fn]] <- df
  }
  out
}

fit_mgmfrm <- function(data, category_levels = NULL, person = "person", item = "item",
                       rater = "rater", score = "score", chains = 4L,
                       warmup = 1000L, draws = 1000L, seed = 1L, variables = NULL,
                       identification = c("isometric", "reference"),
                       facets = NULL, steps = "auto",
                       method = c("nuts", "mmle", "jmle", "ml", "reml"),
                       model = c("mfrm", "gmfrm", "mgmfrm", "gtheory"),
                       group = NULL, Q = NULL,
                       scale_identification = c("geometric_mean_one", "anchor_item"),
                       anchor_items = NULL, handoff_path = NULL,
                       fixed_calibration = NULL,
                       response_id = NULL, assessment_id = NULL,
                       group_equal_sd = FALSE,
                       group_sd_prior = c("lognormal", "half_normal", "half_t"),
                       dff = NULL,
                       dff_mode = c("doubly_centered", "split_rater"),
                       dff_focal = NULL,
                       slope = NULL,
                       correlation = c("independent", "lkj"),
                       lkj_eta = 2.0,
                       ability_sd_prior = c("half_normal", "lognormal", "half_t"),
                       location_identification = c("centered_items_free_mean", "zero_mean_population"),
                       random_effects = NULL,
                       random_sd_prior = c("half_normal", "half_t"),
                       random_sd_scale = 1.0,
                       nesting = NULL, counts = NULL, weights = NULL, interval = 0.95,
                       logit_scale = NULL,
                       rater_slope_scope = c("entire_linear_predictor", "ability_only"),
                       aggregation = c("additive", "softmin"),
                       softmin_kappa = NULL,
                       cross_loading_average = NULL) {
  identification <- match.arg(identification)
  method <- match.arg(method)
  model <- match.arg(model)
  if (identical(model, "gtheory")) {
    if (!is.null(category_levels) || !is.null(group) || !is.null(Q) || !is.null(dff) ||
        !is.null(fixed_calibration) || !is.null(random_effects) || !is.null(slope) ||
        !is.null(response_id) || !is.null(assessment_id) || !is.null(handoff_path) ||
        !is.null(variables) || !is.null(anchor_items) || !is.null(dff_focal) || group_equal_sd ||
        !is.null(logit_scale) || !is.null(softmin_kappa) || !is.null(cross_loading_average) ||
        steps != "auto" || identification != "isometric" ||
        !missing(item) || !missing(rater) || !missing(chains) || !missing(warmup) ||
        !missing(draws) || !missing(seed) || !missing(scale_identification) ||
        !missing(group_sd_prior) || !missing(dff_mode) || !missing(correlation) ||
        !missing(lkj_eta) || !missing(ability_sd_prior) || !missing(location_identification) ||
        !missing(random_sd_prior) || !missing(random_sd_scale) ||
        !missing(rater_slope_scope) || !missing(aggregation))
      stop("G-theory uses numeric score columns, facets and nesting; ordinal/MCMC model controls do not apply.")
    return(.fit_gtheory(data, person, score, facets, nesting, method, counts, weights, interval))
  }
  if (method %in% c("ml", "reml") || !is.null(nesting) || !is.null(counts) || !is.null(weights))
    stop("ml/reml, nesting, counts and weights apply to model = 'gtheory'.")
  if (!missing(interval))
    stop("interval applies to model = 'gtheory'; pass level = ... to summary() or contrast_mgmfrm() for ordinal models.")
  scale_identification <- match.arg(scale_identification)
  group_sd_prior <- match.arg(group_sd_prior)
  dff_mode <- match.arg(dff_mode)
  correlation <- match.arg(correlation)
  ability_sd_prior <- match.arg(ability_sd_prior)
  location_identification <- match.arg(location_identification)
  random_sd_prior <- match.arg(random_sd_prior)
  rater_slope_scope <- match.arg(rater_slope_scope)
  aggregation <- match.arg(aggregation)
  if (!is.numeric(random_sd_scale) || length(random_sd_scale) != 1L ||
      is.na(random_sd_scale) || !is.finite(random_sd_scale) || random_sd_scale <= 0)
    stop("random_sd_scale must be a single finite positive number.")
  if (!is.logical(group_equal_sd) || length(group_equal_sd) != 1L || is.na(group_equal_sd))
    stop("group_equal_sd must be TRUE or FALSE.")
  if (!is.numeric(lkj_eta) || length(lkj_eta) != 1L || is.na(lkj_eta) || !is.finite(lkj_eta) || lkj_eta <= 0)
    stop("lkj_eta must be a single finite positive number.")
  if (!is.null(slope)) {
    if (!is.character(slope) || length(slope) != 1L || is.na(slope) || !(slope %in% c("rater", "item", "both")))
      stop("slope must be NULL, 'rater', 'item', or 'both'.")
    if (identical(model, "mfrm"))
      stop("slope applies only to model = 'gmfrm' or model = 'mgmfrm'.")
  }
  if (!is.null(logit_scale)) {
    if (!is.numeric(logit_scale) || length(logit_scale) != 1L || is.na(logit_scale) || !(as.double(logit_scale) %in% c(1.0, 1.7)))
      stop("logit_scale must be NULL, 1.0, or 1.7.")
    if (identical(model, "mfrm") || (identical(model, "gmfrm") && is.null(slope)))
      stop("logit_scale applies only to scale-identified GMFRM (with explicit slope) or model = 'mgmfrm'.")
  }
  if (identical(rater_slope_scope, "ability_only")) {
    if (identical(model, "mfrm") || (identical(model, "gmfrm") && (is.null(slope) || identical(slope, "item"))) ||
        (identical(model, "mgmfrm") && identical(slope, "item")))
      stop("rater_slope_scope = 'ability_only' requires scale-identified GMFRM (slope = 'rater' or 'both') or model = 'mgmfrm' with estimated rater slopes.")
  }
  if (identical(aggregation, "softmin") && !identical(model, "mgmfrm"))
    stop("aggregation = 'softmin' applies only to multidimensional model = 'mgmfrm' with cross-loaded items.")
  if (!is.null(softmin_kappa)) {
    if (!identical(aggregation, "softmin") || !is.numeric(softmin_kappa) || length(softmin_kappa) != 1L ||
        is.na(softmin_kappa) || !is.finite(softmin_kappa) || softmin_kappa <= 0)
      stop("softmin_kappa must be NULL (estimated) or a single finite positive number when aggregation = 'softmin'.")
  }
  if (!is.null(cross_loading_average)) {
    if (!is.logical(cross_loading_average) || length(cross_loading_average) != 1L || is.na(cross_loading_average) ||
        !identical(model, "mgmfrm"))
      stop("cross_loading_average must be NULL, TRUE, or FALSE on model = 'mgmfrm'.")
    if (identical(aggregation, "softmin") && !isTRUE(cross_loading_average))
      stop("aggregation = 'softmin' requires cross_loading_average = TRUE.")
  }
  if (identical(correlation, "lkj") && !identical(model, "mgmfrm"))
    stop("correlation = 'lkj' applies only to model = 'mgmfrm'.")

  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data)))
    stop("Supply a nonempty data frame with distinct column names.")
  if (!is.character(person) || length(person) != 1L || !nzchar(person) ||
      !is.character(score) || length(score) != 1L || !nzchar(score))
    stop("person and score must be single nonempty column names.")

  if (is.null(facets)) {
    if (!is.character(item) || length(item) != 1L || !nzchar(item) ||
        !is.character(rater) || length(rater) != 1L || !nzchar(rater))
      stop("item and rater must be single nonempty column names.")
    facets_vec <- c(item = item, rater = rater)
  } else {
    if (!is.character(facets) || !length(facets) || anyNA(facets) || any(!nzchar(facets)))
      stop("facets must be a nonempty character vector of column names.")
    f_names <- names(facets)
    if (is.null(f_names)) f_names <- facets
    f_names[!nzchar(f_names)] <- facets[!nzchar(f_names)]
    if (anyDuplicated(f_names) || any(f_names %in% c("person", "steps", "global", "score", "performance", "assessment", "group")))
      stop("Facet role names must be distinct and avoid reserved names.")
    facets_vec <- setNames(as.character(facets), f_names)
  }

  if (!is.null(random_effects)) {
    if (!is.character(random_effects) || !length(random_effects) || anyNA(random_effects) ||
        anyDuplicated(random_effects) || any(!random_effects %in% names(facets_vec)))
      stop("random_effects must name distinct roles declared in facets.")
    if (model != "mfrm" || method != "nuts" || identification != "isometric" ||
        location_identification != "centered_items_free_mean")
      stop("random_effects requires isometric MFRM with NUTS and centered_items_free_mean location identification.")
  }

  req_cols <- c(person = person, facets_vec, score = score)
  if (!is.null(group)) {
    if (!is.character(group) || length(group) != 1L || !nzchar(group))
      stop("group must be NULL or a single column name.")
    req_cols <- c(req_cols, group = group)
  }
  if (!is.null(response_id)) {
    if (!is.character(response_id) || length(response_id) != 1L || !nzchar(response_id))
      stop("response_id must be NULL or a single column name.")
    req_cols <- c(req_cols, response_id = response_id)
  }
  if (!is.null(assessment_id)) {
    if (!is.character(assessment_id) || length(assessment_id) != 1L || !nzchar(assessment_id))
      stop("assessment_id must be NULL or a single column name.")
    req_cols <- c(req_cols, assessment_id = assessment_id)
  }
  # An explicitly named shared-effect facet can also supply its event metadata.
  check_cols <- req_cols
  if (length(random_effects)) {
    for (role in c("response_id", "assessment_id")) {
      if (role %in% names(check_cols) && check_cols[[role]] %in% facets_vec[random_effects])
        check_cols <- check_cols[names(check_cols) != role]
    }
  }
  if (anyDuplicated(unname(check_cols)) || !all(unname(req_cols) %in% names(data)))
    stop("Supply distinct existing rating columns in a nonempty data frame.")

  integers <- function(x) {
    if (is.object(x) || !is.numeric(x) || !length(x) || anyNA(x) ||
        any(!is.finite(x) | x != trunc(x) | abs(x) > .Machine$integer.max))
      stop("Expected a finite integer-valued score, category or control")
    as.integer(x)
  }
  scores <- integers(data[[score]])

  controls <- lapply(list(chains, warmup, draws, seed), integers)
  if (any(lengths(controls) != 1L) || any(unlist(controls) < c(1, 0, 1, 0)))
    stop("Invalid sampler controls")

  p_map <- encode_mgmfrm_id(data[[person]])
  f_maps <- lapply(facets_vec, function(col_nm) encode_mgmfrm_id(data[[col_nm]]))
  id_dict <- c(list(person = p_map$labels), lapply(f_maps, "[[", "labels"))

  is_mixed_cats <- is.list(category_levels) && !is.data.frame(category_levels)
  if (!is.character(steps) || length(steps) != 1L || !nzchar(steps))
    stop("steps must be 'auto', 'global', or a declared facet name.")

  if (is_mixed_cats) {
    if (!identical(model, "mfrm") || !identical(identification, "isometric"))
      stop("Named-list per-level category_levels is supported only for 1D isometric MFRM (model = 'mfrm', identification = 'isometric').")
    lvl_names <- names(category_levels)
    if (!length(category_levels) || is.null(lvl_names) || anyNA(lvl_names) || any(!nzchar(lvl_names)) || anyDuplicated(lvl_names))
      stop("List category_levels must be a nonempty named list mapping each step-owner level to its consecutive integer category vector.")
    eff_steps <- if (identical(steps, "auto")) {
      cand_owners <- names(facets_vec)[vapply(names(facets_vec), function(fn) {
        setequal(lvl_names, as.character(id_dict[[fn]]))
      }, logical(1L))]
      if ("item" %in% cand_owners) {
        "item"
      } else if (length(cand_owners) == 1L) {
        cand_owners[[1L]]
      } else {
        stop("When category_levels is a named list, set steps to the owning facet name (e.g., steps = 'item') and match names(category_levels) to its observed levels.")
      }
    } else {
      steps
    }
    if (identical(eff_steps, "global") || !(eff_steps %in% names(facets_vec)))
      stop("Named-list category_levels requires a single declared facet step owner (e.g., steps = 'item'); steps = '", eff_steps, "' is not supported.")
    owner_labels <- as.character(id_dict[[eff_steps]])
    if (!setequal(lvl_names, owner_labels))
      stop("names(category_levels) must match all observed levels of steps = '", eff_steps, "' (", paste(owner_labels, collapse = ", "), ").")
    owner_idx_vec <- f_maps[[eff_steps]]$index
    parsed_cat_list <- setNames(vector("list", length(owner_labels)), owner_labels)
    idx_cat_list <- setNames(vector("list", length(owner_labels)), as.character(seq_along(owner_labels)))
    for (k in seq_along(owner_labels)) {
      lbl <- owner_labels[[k]]
      v <- integers(category_levels[[lbl]])
      if (length(v) < 2L || any(diff(as.double(v)) != 1))
        stop("Each entry in category_levels[['", lbl, "']] must be a consecutive integer sequence of length >= 2.")
      rows_k <- which(owner_idx_vec == k)
      if (length(rows_k) && !all(scores[rows_k] %in% v))
        stop("Observed scores for ", eff_steps, " = '", lbl, "' fall outside declared category_levels[['", lbl, "']].")
      parsed_cat_list[[lbl]] <- v
      idx_cat_list[[as.character(k)]] <- v
    }
    levels_out <- parsed_cat_list
    all_cats <- sort(unique(unlist(parsed_cat_list, use.names = FALSE)))
    levels_wire <- as.integer(seq.int(min(all_cats), max(all_cats)))
    cat_levels_json <- as.character(jsonlite::toJSON(idx_cat_list, auto_unbox = FALSE))
  } else {
    if (is.null(category_levels))
      stop("Supply category_levels (e.g., 0:3) for ordinal models.")
    levels_wire <- integers(category_levels)
    if (length(levels_wire) < 2L || any(diff(as.double(levels_wire)) != 1) || !all(scores %in% levels_wire))
      stop("Declare the full consecutive category scale, including unobserved endpoints")
    levels_out <- levels_wire
    cat_levels_json <- ""
    eff_steps <- if (identical(steps, "auto")) {
      gen_item_role <- if ("criterion" %in% names(facets_vec) && !("item" %in% names(facets_vec))) "criterion" else "item"
      if (identical(model, "gmfrm")) {
        if (!is.null(slope) && identical(slope, "item")) gen_item_role else "rater"
      } else if (identical(model, "mgmfrm")) {
        gen_item_role
      } else if (length(levels_wire) > 2L && ("item" %in% names(facets_vec))) {
        "item"
      } else {
        "global"
      }
    } else {
      steps
    }
    if (!identical(eff_steps, "global") && !(eff_steps %in% names(facets_vec)))
      stop("steps must be 'auto', 'global', or one of the declared facet names.")
  }

  gen_item_role <- if ("criterion" %in% names(facets_vec) && !("item" %in% names(facets_vec))) "criterion" else "item"
  if (identical(model, "gmfrm") && is.null(slope) && !identical(eff_steps, "rater"))
    stop("model = 'gmfrm' without explicit slope supports only rater-owned partial-credit thresholds (steps = 'rater'); pass slope = 'rater', 'item', or 'both' for scale-identified GMFRM with steps = 'global', 'item', or 'rater'.")
  if (identical(model, "gmfrm") && !is.null(slope) && !(eff_steps %in% c("global", gen_item_role, "rater")))
    stop("model = 'gmfrm' with slope supports steps = 'global', '", gen_item_role, "', or 'rater'; requested steps = '", eff_steps, "' is not supported.")
  if (identical(model, "gmfrm") && !identical(identification, "isometric"))
    stop("model = 'gmfrm' requires identification = 'isometric'; identification = '", identification, "' is not supported.")
  if (identical(model, "mgmfrm") && !(eff_steps %in% c("global", gen_item_role, "rater")))
    stop("model = 'mgmfrm' supports steps = 'global', '", gen_item_role, "', or 'rater'; requested steps = '", eff_steps, "' is not supported.")
  if (identical(model, "mgmfrm") && !identical(identification, "isometric"))
    stop("model = 'mgmfrm' is identified via scale_identification ('geometric_mean_one' or 'anchor_item'); identification = '", identification, "' is not supported.")

  if (!is.null(variables) && (!is.character(variables) || !length(variables) ||
      anyNA(variables) || any(!nzchar(variables)) || anyDuplicated(variables)))
    stop("Choose distinct parameter names or use NULL for all parameters")
  if (!is.null(handoff_path)) {
    if (!is.character(handoff_path) || length(handoff_path) != 1L || !nzchar(handoff_path))
      stop("handoff_path must be NULL or a single file path.")
    handoff_path <- normalizePath(handoff_path, mustWork = FALSE)
  }

  fixed_cal_json <- ""
  if (!is.null(fixed_calibration)) {
    if (!identical(model, "mfrm") || !identical(identification, "isometric"))
      stop("fixed_calibration is supported only for 1D isometric MFRM (model = 'mfrm', identification = 'isometric').")
    if (!is.list(fixed_calibration) || !length(fixed_calibration) || is.null(names(fixed_calibration)) ||
        any(!nzchar(names(fixed_calibration))) || anyDuplicated(names(fixed_calibration)) ||
        !all(names(fixed_calibration) %in% c("facets", "groups")))
      stop("fixed_calibration must be a nonempty named list with elements 'facets' and/or 'groups'.")
    fc_wire <- list()
    eq_rows <- list()
    if (!is.null(fixed_calibration$facets)) {
      ff <- fixed_calibration$facets
      if (!is.list(ff) || !length(ff) || is.null(names(ff)) || anyDuplicated(names(ff)) ||
          !all(names(ff) %in% names(facets_vec)))
        stop("fixed_calibration$facets must be a nonempty named list keyed by declared facet names.")
      ff_wire <- list()
      for (fn in names(ff)) {
        fvals <- ff[[fn]]
        if (is.list(fvals)) fvals <- unlist(fvals, recursive = FALSE)
        lv_names <- names(fvals)
        if (!is.numeric(fvals) || is.logical(fvals) || !length(fvals) || is.null(lv_names) ||
            anyNA(lv_names) || any(!nzchar(lv_names)) || anyDuplicated(lv_names) ||
            anyNA(fvals) || any(!is.finite(fvals)))
          stop("fixed_calibration$facets$", fn, " must be a finite named numeric vector keyed by observed level labels.")
        obs_lbls <- as.character(id_dict[[fn]])
        idx_hit <- match(lv_names, obs_lbls)
        if (anyNA(idx_hit))
          stop("Unknown level label(s) in fixed_calibration$facets$", fn, ": ",
               paste(lv_names[is.na(idx_hit)], collapse = ", "), ".")
        ff_wire[[fn]] <- setNames(as.list(as.double(fvals)), as.character(idx_hit))
        for (j in seq_along(lv_names)) {
          eq_rows[[length(eq_rows) + 1L]] <- list(
            kind = "hard_location",
            block = fn,
            levels = list(lv_names[[j]]),
            statistic = "exact",
            weighting = "point_value",
            value = as.double(fvals[[j]]),
            equation = sprintf("%s[%s] = %.12g", fn, lv_names[[j]], as.double(fvals[[j]]))
          )
        }
      }
      fc_wire$facets <- ff_wire
    }
    if (!is.null(fixed_calibration$groups)) {
      fg <- fixed_calibration$groups
      if (!is.list(fg) || !length(fg))
        stop("fixed_calibration$groups must be a nonempty list of group constraint records.")
      fg_wire <- vector("list", length(fg))
      for (g_i in seq_along(fg)) {
        g_rec <- fg[[g_i]]
        if (!is.list(g_rec) || is.null(names(g_rec)))
          stop("Each element of fixed_calibration$groups must be a named list with 'block', 'levels', and either 'mean' or 'sum'.")
        has_mean <- "mean" %in% names(g_rec)
        has_sum <- "sum" %in% names(g_rec)
        if (!xor(has_mean, has_sum) || !all(names(g_rec) %in% c("block", "levels", "mean", "sum")) ||
            is.null(g_rec$block) || is.null(g_rec$levels))
          stop("Each element of fixed_calibration$groups requires 'block', 'levels', and exactly one of 'mean' or 'sum'.")
        blk <- as.character(g_rec$block)
        if (length(blk) != 1L || !(blk %in% names(facets_vec)))
          stop("fixed_calibration$groups[[", g_i, "]]$block must name a declared facet.")
        mems <- as.character(unlist(g_rec$levels, use.names = FALSE))
        if (!length(mems) || anyNA(mems) || any(!nzchar(mems)) || anyDuplicated(mems))
          stop("fixed_calibration$groups[[", g_i, "]]$levels must be distinct nonempty level labels.")
        obs_lbls <- as.character(id_dict[[blk]])
        idx_m <- match(mems, obs_lbls)
        if (anyNA(idx_m))
          stop("Unknown level label(s) in fixed_calibration$groups[[", g_i, "]] (", blk, "): ",
               paste(mems[is.na(idx_m)], collapse = ", "), ".")
        stat_nm <- if (has_mean) "mean" else "sum"
        tval <- g_rec[[stat_nm]]
        if (!is.numeric(tval) || is.logical(tval) || length(tval) != 1L || is.na(tval) || !is.finite(tval))
          stop("fixed_calibration$groups[[", g_i, "]]$", stat_nm, " must be a single finite number.")
        fg_wire[[g_i]] <- list(
          block = blk,
          levels = as.list(as.integer(idx_m)),
          statistic = stat_nm,
          value = as.double(tval)
        )
        eq_rows[[length(eq_rows) + 1L]] <- list(
          kind = "subset_constraint",
          block = blk,
          levels = as.list(mems),
          statistic = stat_nm,
          weighting = "unweighted_equal_levels",
          value = as.double(tval),
          equation = sprintf("%s(%s[%s]) = %.12g", stat_nm, blk, paste(mems, collapse = ", "), as.double(tval))
        )
      }
      fc_wire$groups <- fg_wire
    }
    if (!length(fc_wire))
      stop("fixed_calibration cannot be empty.")
    fc_wire$receipt <- list(
      uncertainty = "conditional_on_fixed_calibration",
      subset_weighting_convention = "unweighted_equal_levels",
      constraints = eq_rows
    )
    fixed_cal_json <- as.character(jsonlite::toJSON(fc_wire, auto_unbox = TRUE))
  }

  group_idx <- integer(0L)
  dff_facet_wire <- ""
  dff_focal_idx <- integer(0L)
  if (!is.null(group)) {
    g_map <- encode_mgmfrm_id(data[[group]])
    if (length(g_map$labels) < 2L)
      stop("group column must contain at least two distinct observed groups.")
    by_p <- split(g_map$index, p_map$index)
    if (any(vapply(by_p, function(v) length(unique(v)) != 1L, logical(1L))))
      stop("Each person must belong to a single group.")
    group_idx <- as.integer(g_map$index)
    id_dict$group <- g_map$labels
  }
  if (!is.null(dff)) {
    if (is.null(group))
      stop("Supply a person-level group column in `group` when requesting `dff`.")
    if (!is.character(dff) || length(dff) != 1L || !(dff %in% names(facets_vec)))
      stop("`dff` must name a single declared facet role (e.g., dff = 'rater').")
    dff_facet_wire <- as.character(dff)
    if (identical(dff_mode, "split_rater")) {
      if (is.null(dff_focal) || !length(dff_focal))
        stop("Supply one or more observed level labels in `dff_focal` when dff_mode = 'split_rater'.")
      obs_lv <- as.character(id_dict[[dff_facet_wire]])
      hit_foc <- match(as.character(dff_focal), obs_lv)
      if (anyNA(hit_foc) || anyDuplicated(hit_foc) || length(hit_foc) >= length(obs_lv))
        stop("`dff_focal` must select distinct observed levels of ", dff_facet_wire, " while leaving at least one invariant anchor level.")
      dff_focal_idx <- as.integer(hit_foc)
    } else if (!is.null(dff_focal)) {
      stop("`dff_focal` applies only when dff_mode = 'split_rater'.")
    }
  } else if (!is.null(dff_focal)) {
    stop("Supply `dff` (e.g., dff = 'rater') when specifying `dff_focal`.")
  }

  perf_idx <- integer(0L)
  if (!is.null(response_id)) {
    r_map <- encode_mgmfrm_id(data[[response_id]])
    perf_idx <- as.integer(r_map$index)
    id_dict$response_id <- r_map$labels
  }

  assess_idx <- integer(0L)
  if (!is.null(assessment_id)) {
    a_map <- encode_mgmfrm_id(data[[assessment_id]])
    assess_idx <- as.integer(a_map$index)
    id_dict$assessment_id <- a_map$labels
  }

  q_flat <- integer(0L)
  q_ncol <- 0L
  q_dim_labels <- character(0L)
  anchor_dims <- integer(0L)
  anchor_item_idx <- integer(0L)
  resolve_anchor_idx <- function(anchor_vals, domain_ids, role_name) {
    n_dom <- length(domain_ids)
    if (is.character(anchor_vals) || is.factor(anchor_vals)) {
      idx <- match(as.character(anchor_vals), as.character(domain_ids))
      if (anyNA(idx))
        stop("anchor_items labels must match observed ", role_name, " IDs.")
    } else {
      iv <- integers(anchor_vals)
      m_dom <- if (is.numeric(domain_ids)) match(as.character(iv), as.character(domain_ids)) else rep(NA_integer_, length(iv))
      if (!anyNA(m_dom)) {
        idx <- m_dom
      } else if (all(is.na(m_dom))) {
        if (any(iv < 1L | iv > n_dom))
          stop("Numeric anchor_items must match observed ", role_name, " IDs or be 1-based item indices in 1..n_items.")
        idx <- iv
      } else {
        stop("Numeric anchor_items must either all match observed ", role_name, " IDs or all be 1-based item indices in 1..n_items.")
      }
    }
    if (anyDuplicated(idx))
      stop("anchor_items must identify distinct ", role_name, " levels.")
    as.integer(idx)
  }
  if (identical(model, "gmfrm") && !is.null(slope) && identical(scale_identification, "anchor_item")) {
    if (identical(slope, "rater"))
      stop("scale_identification = 'anchor_item' on model = 'gmfrm' requires estimated item slopes (slope = 'item' or 'both').")
    if (!is.null(anchor_items)) {
      if (length(anchor_items) != 1L)
        stop("Supply a single anchor item ID or 1-based index for 1D GMFRM.")
      anchor_dims <- 1L
      anchor_item_idx <- resolve_anchor_idx(anchor_items, id_dict[[gen_item_role]], gen_item_role)
    }
  }
  if (identical(model, "mgmfrm")) {
    if (!(length(facets_vec) == 2L && "rater" %in% names(facets_vec) && gen_item_role %in% names(facets_vec)))
      stop("model = 'mgmfrm' requires two non-person facets c(item = ..., rater = ...) or c(criterion = ..., rater = ...).")
    if (is.null(Q) || !is.matrix(Q) || !(is.numeric(Q) || is.logical(Q)) || anyNA(Q) || !all(Q %in% c(0, 1, FALSE, TRUE)))
      stop("Supply a binary (0/1 or logical) item-by-dimension matrix Q for model = 'mgmfrm'.")
    n_items <- length(id_dict[[gen_item_role]])
    if (nrow(Q) != n_items || ncol(Q) < 1L)
      stop("nrow(Q) must match the number of observed ", gen_item_role, " levels and ncol(Q) must be >= 1.")
    if (!is.null(rownames(Q))) {
      if (anyDuplicated(rownames(Q)))
        stop("rownames(Q) must not contain duplicates.")
      ord <- match(as.character(id_dict[[gen_item_role]]), rownames(Q))
      if (anyNA(ord))
        stop("rownames(Q) must match the observed ", gen_item_role, " IDs.")
      Q <- Q[ord, , drop = FALSE]
    }
    if (!is.null(colnames(Q))) {
      c_nms <- as.character(colnames(Q))
      if (anyNA(c_nms) || any(!nzchar(c_nms)) || anyDuplicated(c_nms))
        stop("colnames(Q), when supplied, must be distinct nonempty dimension labels.")
      q_dim_labels <- c_nms
    }
    q_ncol <- as.integer(ncol(Q))
    id_dict$dimension <- if (length(q_dim_labels)) q_dim_labels else paste0("dim=", seq_len(q_ncol))
    if (identical(correlation, "lkj") && !(q_ncol %in% c(2L, 3L)))
      stop("correlation = 'lkj' requires 2 or 3 dimensions in Q; got ncol(Q) = ", q_ncol, ".")
    if (identical(aggregation, "softmin")) {
      if (q_ncol < 2L || !any(rowSums(Q > 0) >= 2L))
        stop("aggregation = 'softmin' requires at least 2 dimensions and at least one cross-loaded item in Q.")
    }
    q_flat <- as.integer(Q)
    if (identical(scale_identification, "anchor_item")) {
      if (is.null(anchor_items) || length(anchor_items) != q_ncol)
        stop("Supply one anchor item ID or 1-based index per dimension in anchor_items.")
      anchor_dims <- seq_len(q_ncol)
      anchor_item_idx <- resolve_anchor_idx(anchor_items, id_dict[[gen_item_role]], gen_item_role)
    }
  }

  facet_names <- as.character(names(facets_vec))
  facet_cols_flat <- as.integer(unlist(lapply(f_maps, "[[", "index"), use.names = FALSE))
  cl_avg_wire <- if (is.null(cross_loading_average)) -1L else as.integer(isTRUE(cross_loading_average))

  obj <- .with_mgmfrm(.mgmfrm_session$runtime, {
    fn_ref <- JuliaConnectoR::juliaEval(
      "Base.invokelatest(getfield, Base.invokelatest(getfield, Main, :MGMFRMRBridge), :fit_model)"
    )
    JuliaConnectoR::juliaCall(
      "Base.invokelatest",
      fn_ref,
      as.integer(p_map$index),
      facet_names,
      facet_cols_flat,
      scores,
      levels_wire,
      group_idx,
      model,
      method,
      eff_steps,
      identification,
      q_flat,
      q_ncol,
      scale_identification,
      anchor_dims,
      as.integer(anchor_item_idx),
      controls[[1L]],
      controls[[2L]],
      controls[[3L]],
      controls[[4L]],
      variables,
      if (is.null(handoff_path)) "" else handoff_path,
      as.character(jsonlite::toJSON(lapply(id_dict, as.character), auto_unbox = FALSE)),
      cat_levels_json,
      fixed_cal_json,
      perf_idx,
      assess_idx,
      group_equal_sd,
      group_sd_prior,
      dff_facet_wire,
      dff_mode,
      dff_focal_idx,
      if (is.null(slope)) "" else slope,
      correlation,
      as.double(lkj_eta),
      ability_sd_prior,
      location_identification,
      if (is.null(random_effects)) character() else unname(random_effects),
      random_sd_prior,
      as.double(random_sd_scale),
      if (is.null(logit_scale)) 0.0 else as.double(logit_scale),
      rater_slope_scope,
      aggregation,
      if (is.null(softmin_kappa)) 0.0 else as.double(softmin_kappa),
      as.integer(cl_avg_wire),
      q_dim_labels
    )
  })

  expected_id <- if (identical(model, "mgmfrm")) {
    scale_identification
  } else if (identical(model, "gmfrm")) {
    if (is.null(slope)) "gmfrm_item_sum_to_zero" else scale_identification
  } else if (identical(model, "mfrm") && identical(identification, "reference")) {
    "reference_first"
  } else if (!is.null(fixed_calibration)) {
    "isometric_fixed_calibration"
  } else {
    identification
  }

  .assemble_mgmfrm_fit(
    obj = obj,
    id_dict = id_dict,
    levels = levels_out,
    columns = req_cols,
    model = model,
    method = method,
    steps = eff_steps,
    identification = expected_id
  )
}

.relabel_index_vec <- function(vals, labels) {
  if (is.null(vals) || !length(vals) || is.null(labels) || !length(labels)) return(vals)
  raw_v <- unlist(vals, use.names = FALSE)
  if (is.numeric(raw_v) && all(is.finite(raw_v) & raw_v == trunc(raw_v) & raw_v >= 1L & raw_v <= length(labels))) {
    return(as.list(as.character(labels[as.integer(raw_v)])))
  }
  vals
}

.relabel_design_validation <- function(dv, id_dict) {
  if (!is.list(dv) || !length(dv) || !is.list(id_dict) || !length(id_dict)) return(dv)
  relabel_subset_block <- function(blk) {
    if (!is.list(blk)) return(blk)
    if (is.list(blk$overall_subsets)) {
      blk$overall_subsets <- lapply(blk$overall_subsets, function(sub) {
        if (!is.list(sub)) return(sub)
        if (!is.null(sub$persons) && "person" %in% names(id_dict))
          sub$persons <- .relabel_index_vec(sub$persons, id_dict$person)
        if (is.list(sub$facets)) {
          for (fn in names(sub$facets)) {
            if (fn %in% names(id_dict))
              sub$facets[[fn]] <- .relabel_index_vec(sub$facets[[fn]], id_dict[[fn]])
          }
        }
        sub
      })
    }
    if (is.list(blk$by_facet)) {
      blk$by_facet <- lapply(blk$by_facet, function(bf) {
        if (!is.list(bf) || is.null(bf$facet)) return(bf)
        fn <- as.character(bf$facet)
        if (is.list(bf$subsets)) {
          bf$subsets <- lapply(bf$subsets, function(sub) {
            if (!is.list(sub)) return(sub)
            if (!is.null(sub$persons) && "person" %in% names(id_dict))
              sub$persons <- .relabel_index_vec(sub$persons, id_dict$person)
            if (!is.null(sub$levels) && fn %in% names(id_dict))
              sub$levels <- .relabel_index_vec(sub$levels, id_dict[[fn]])
            sub
          })
        }
        bf
      })
    }
    if (is.list(blk$isolated_facet_levels)) {
      blk$isolated_facet_levels <- lapply(blk$isolated_facet_levels, function(it) {
        if (is.list(it) && !is.null(it[["facet"]])) {
          fn <- as.character(it[["facet"]])
          if (fn %in% names(id_dict)) {
            if (!is.null(it[["levels"]])) {
              it[["levels"]] <- .relabel_index_vec(it[["levels"]], id_dict[[fn]])
            } else if (!is.null(it[["level"]])) {
              mapped <- .relabel_index_vec(list(it[["level"]]), id_dict[[fn]])
              it[["level"]] <- mapped[[1L]]
            }
          }
        }
        it
      })
    }
    blk
  }
  if (!is.null(dv$disjoint_subsets))
    dv$disjoint_subsets <- relabel_subset_block(dv$disjoint_subsets)
  if (!is.null(dv$score_conditioned_subsets))
    dv$score_conditioned_subsets <- relabel_subset_block(dv$score_conditioned_subsets)
  if (is.list(dv$connectedness)) {
    if (is.list(dv$connectedness$isolated_facet_levels)) {
      dv$connectedness$isolated_facet_levels <- lapply(dv$connectedness$isolated_facet_levels, function(it) {
        if (is.list(it) && !is.null(it[["facet"]])) {
          fn <- as.character(it[["facet"]])
          if (fn %in% names(id_dict)) {
            if (!is.null(it[["levels"]])) {
              it[["levels"]] <- .relabel_index_vec(it[["levels"]], id_dict[[fn]])
            } else if (!is.null(it[["level"]])) {
              mapped <- .relabel_index_vec(list(it[["level"]]), id_dict[[fn]])
              it[["level"]] <- mapped[[1L]]
            }
          }
        }
        it
      })
    }
    if (is.list(dv$connectedness$thin_bridges)) {
      dv$connectedness$thin_bridges <- lapply(dv$connectedness$thin_bridges, function(tb) {
        if (is.list(tb) && !is.null(tb$facet) && !is.null(tb$weakest_bridge_pair)) {
          fn <- as.character(tb$facet)
          if (fn %in% names(id_dict))
            tb$weakest_bridge_pair <- .relabel_index_vec(tb$weakest_bridge_pair, id_dict[[fn]])
        }
        tb
      })
    }
  }
  if (is.list(dv$one_sided_separation) && is.list(dv$one_sided_separation$by_facet)) {
    dv$one_sided_separation$by_facet <- lapply(dv$one_sided_separation$by_facet, function(bf) {
      if (is.list(bf) && !is.null(bf[["facet"]])) {
        fn <- as.character(bf[["facet"]])
        if (fn %in% names(id_dict)) {
          if (is.list(bf[["scc_level_groups"]]))
            bf[["scc_level_groups"]] <- lapply(bf[["scc_level_groups"]], function(lv) .relabel_index_vec(lv, id_dict[[fn]]))
          if (is.list(bf[["scc_facet_levels"]]))
            bf[["scc_facet_levels"]] <- lapply(bf[["scc_facet_levels"]], function(lv) .relabel_index_vec(lv, id_dict[[fn]]))
          if (!is.null(bf[["source_levels"]]))
            bf[["source_levels"]] <- .relabel_index_vec(bf[["source_levels"]], id_dict[[fn]])
          if (!is.null(bf[["sink_levels"]]))
            bf[["sink_levels"]] <- .relabel_index_vec(bf[["sink_levels"]], id_dict[[fn]])
        }
      }
      bf
    })
  }
  if (is.list(dv$nesting_and_aliasing) && is.list(dv$nesting_and_aliasing$relations)) {
    dv$nesting_and_aliasing$relations <- lapply(dv$nesting_and_aliasing$relations, function(rel) {
      if (is.list(rel) && is.list(rel$level_mapping) && !is.null(rel$nested_role) && !is.null(rel$containing_role)) {
        nr <- as.character(rel$nested_role)
        pr <- as.character(rel$containing_role)
        rel$level_mapping <- lapply(rel$level_mapping, function(m) {
          if (is.list(m)) {
            if (!is.null(m$parent_level) && pr %in% names(id_dict)) {
              mp <- .relabel_index_vec(list(m$parent_level), id_dict[[pr]])
              m$parent_level <- mp[[1L]]
            }
            if (!is.null(m$child_levels) && nr %in% names(id_dict)) {
              m$child_levels <- .relabel_index_vec(m$child_levels, id_dict[[nr]])
            }
          }
          m
        })
      }
      rel
    })
  }
  dv
}

.assemble_mgmfrm_fit <- function(obj, id_dict, levels, columns, model, method, steps, identification) {
  var_names <- as.character(obj$names)
  meta <- jsonlite::fromJSON(obj$metadata, simplifyVector = FALSE)
  eff_model <- if (!is.null(meta$model)) as.character(meta$model) else model
  eff_method <- if (!is.null(meta$method)) as.character(meta$method) else method
  eff_steps <- if (!is.null(meta$steps)) as.character(meta$steps) else steps
  eff_id <- if (!is.null(meta$identification)) as.character(meta$identification) else identification
  if (!identical(eff_model, model))
    stop("Compiled Julia model ('", eff_model, "') does not match requested model ('", model, "').")
  if (!identical(eff_method, method))
    stop("Compiled Julia estimation method ('", eff_method, "') does not match requested method ('", method, "').")
  if (!identical(eff_steps, steps))
    stop("Compiled Julia threshold owner ('", eff_steps, "') does not match requested steps ('", steps, "').")
  if (!identical(eff_id, identification))
    stop("Compiled Julia identification ('", eff_id, "') does not match expected identification ('", identification, "').")
  if (!is.null(meta$design_validation))
    meta$design_validation <- .relabel_design_validation(meta$design_validation, id_dict)
  if (is.list(meta$residual_correlation) && is.list(meta$residual_correlation$pairs)) {
    rc_f <- if (!is.null(meta$residual_correlation$facet)) as.character(meta$residual_correlation$facet) else "item"
    if (rc_f %in% names(id_dict)) {
      rc_lvls <- as.character(id_dict[[rc_f]])
      meta$residual_correlation$pairs <- lapply(meta$residual_correlation$pairs, function(pr) {
        if (is.list(pr)) {
          for (fld in c("level_1", "level_2")) {
            iv <- suppressWarnings(as.integer(pr[[fld]]))
            if (length(iv) == 1L && !is.na(iv) && iv >= 1L && iv <= length(rc_lvls))
              pr[[fld]] <- rc_lvls[[iv]]
          }
        }
        pr
      })
    }
  }
  if (is.list(meta$weighted_sufficient_score) && ("person" %in% names(id_dict))) {
    p_lvls <- as.character(id_dict$person)
    meta$weighted_sufficient_score <- lapply(meta$weighted_sufficient_score, function(w_blk) {
      if (is.list(w_blk) && is.list(w_blk$rows)) {
        w_blk$rows <- lapply(w_blk$rows, function(rw) {
          if (is.list(rw) && !is.null(rw$person)) {
            iv <- suppressWarnings(as.integer(rw$person))
            if (length(iv) == 1L && !is.na(iv) && iv >= 1L && iv <= length(p_lvls))
              rw$person <- p_lvls[[iv]]
          }
          rw
        })
      }
      w_blk
    })
  }
  param_labels <- .label_mgmfrm_parameters(var_names, id_dict, step_owner = eff_steps)
  meta$parameter_labels <- as.list(param_labels)
  meta$facet_indexing_modes <- as.list(setNames(rep("positional", length(id_dict)), names(id_dict)))
  fit_stats <- .format_fit_statistics(meta$fit_statistics, id_dict)
  rel_df <- .rows_to_df(meta$reliability)

  if (identical(as.character(obj$kind), "bayesian")) {
    values <- obj$values
    dimnames(values) <- list(iteration = NULL, chain = NULL, variable = var_names)
    draws_arr <- posterior::as_draws_array(values)
    est_df <- .summarize_bayesian_draws(draws_arr, param_labels = param_labels, level = 0.95)
    vcov_mat <- .vcov_from_draws(draws_arr)
  } else {
    draws_arr <- NULL
    est <- as.double(obj$estimates)
    se <- as.double(obj$se)
    crit <- stats::qnorm(0.975)
    est_df <- data.frame(
      variable = var_names,
      label = unname(param_labels),
      estimate = est,
      se = se,
      lower = est - crit * se,
      upper = est + crit * se,
      stringsAsFactors = FALSE
    )
    vc_names <- as.character(obj$vcov_names)
    if (length(vc_names)) {
      vcov_mat <- matrix(as.double(obj$vcov), nrow = length(vc_names), ncol = length(vc_names))
      dimnames(vcov_mat) <- list(vc_names, vc_names)
    } else {
      vcov_mat <- matrix(numeric(0L), nrow = 0L, ncol = 0L)
    }
  }

  result <- list(
    draws = draws_arr,
    estimates = est_df,
    vcov = vcov_mat,
    ids = id_dict,
    parameter_labels = param_labels,
    fit_statistics = fit_stats,
    reliability = rel_df,
    model = eff_model,
    method = eff_method,
    steps = eff_steps,
    identification = eff_id,
    category_levels = levels,
    columns = columns,
    metadata = meta
  )
  if (!isTRUE(result$metadata$qualification$qualified))
    warning("Julia numerical qualification did not pass. Inspect diagnostics_mgmfrm(fit, 'qualification') and diagnostics_mgmfrm(fit, 'sampler').")
  class(result) <- "mgmfrm_r_fit"
  result
}

as_draws_array.mgmfrm_r_fit <- function(x, ...) {
  if (is.null(x$draws))
    stop("Posterior draws are only available for Bayesian fits (method = 'nuts'). Use coef(), vcov(), or summary().")
  x$draws
}

as_draws.mgmfrm_r_fit <- function(x, ...) as_draws_array.mgmfrm_r_fit(x, ...)

coef.mgmfrm_r_fit <- function(object, ...) {
  if (!is.null(object$estimates)) {
    vals <- if ("mean" %in% names(object$estimates)) object$estimates$mean else object$estimates$estimate
    return(setNames(as.double(vals), object$estimates$variable))
  }
  if (!is.null(object$draws)) {
    est <- .summarize_bayesian_draws(object$draws, param_labels = object$parameter_labels)
    return(setNames(est$mean, est$variable))
  }
  numeric(0L)
}

vcov.mgmfrm_r_fit <- function(object, ...) {
  if (!is.null(object$vcov)) return(object$vcov)
  if (!is.null(object$draws)) return(.vcov_from_draws(object$draws))
  matrix(numeric(0L), nrow = 0L, ncol = 0L)
}

print.mgmfrm_r_fit <- function(x, ...) {
  mdl <- if (!is.null(x$model)) x$model else "mfrm"
  mth <- if (!is.null(x$method)) x$method else if (!is.null(x$draws)) "nuts" else "unknown"
  idf <- if (!is.null(x$identification)) x$identification else "unknown"
  stp <- if (!is.null(x$steps)) x$steps else "auto"
  qual <- if (!is.null(x$metadata$qualification$qualified)) isTRUE(x$metadata$qualification$qualified) else NA
  cat(sprintf("BayesianMGMFRM fit (model = %s, method = %s, steps = %s, identification = %s)\n",
              mdl, mth, stp, idf))
  ps <- x$metadata$prior_summary
  if (is.list(ps)) {
    fam <- if (!is.null(ps$family)) as.character(ps$family) else ""
    p_role <- if (is.list(ps$person) && !is.null(ps$person$role)) as.character(ps$person$role) else ""
    if (identical(fam, "scale_identified_mgmfrm") || !is.null(ps$ability_sd$label)) {
      ll_part <- if (identical(ps$item_slopes, "fixed_one")) {
        "item slopes = fixed(1)"
      } else {
        sprintf("log_loading_sd = %s", as.character(ps$log_loading_sd))
      }
      lc_part <- if (identical(ps$rater_consistency, "fixed_one")) {
        "rater consistency = fixed(1)"
      } else {
        sprintf("log_consistency_sd = %s", as.character(ps$log_consistency_sd))
      }
      cat(sprintf("Prior: ability SD ~ %s, %s, %s\n",
                  as.character(ps$ability_sd$label), ll_part, lc_part))
    } else if (identical(fam, "gmfrm")) {
      cat(sprintf("Prior (raw coordinates): person ability ~ %s, rater ~ %s, item ~ %s, log_item_discrimination ~ %s, log_rater_consistency ~ %s, step ~ %s\n",
                  as.character(ps$person$label),
                  as.character(ps$rater$label),
                  as.character(ps$item$label),
                  as.character(ps$log_item_discrimination$label),
                  as.character(ps$log_rater_consistency$label),
                  as.character(ps$step$label)))
    } else if (p_role %in% c("group_ability_sd", "shared_group_ability_sd") || !is.null(ps$population$sd_prior$label)) {
      sd_lbl <- if (!is.null(ps$population$sd_prior$label)) {
        as.character(ps$population$sd_prior$label)
      } else {
        as.character(ps$person$label)
      }
      mu_lbl <- if (!is.null(ps$population$coefficient_prior$distribution)) {
        as.character(ps$population$coefficient_prior$distribution)
      } else if (!is.null(ps$population_mean$distribution)) {
        as.character(ps$population_mean$distribution)
      } else {
        ""
      }
      mu_str <- if (nzchar(mu_lbl)) sprintf(", group mean ~ %s", mu_lbl) else ""
      cat(sprintf("Prior: group ability SD ~ %s%s\n", sd_lbl, mu_str))
    } else if (identical(p_role, "person_ability") || identical(fam, "reference_mfrm")) {
      cat(sprintf("Prior: person ability ~ %s, rater ~ %s, item ~ %s, step ~ %s\n",
                  as.character(ps$person$label),
                  as.character(ps$rater$label),
                  as.character(ps$item$label),
                  as.character(ps$step$label)))
    } else if (!is.null(ps$person$label)) {
      pm_str <- if (!is.null(ps$population_mean$distribution)) {
        sprintf(", population_mean ~ %s", as.character(ps$population_mean$distribution))
      } else {
        ""
      }
      p_prefix <- if (identical(p_role, "person_ability_fixed_sd")) "person ability SD (fixed)" else "person SD"
      cat(sprintf("Prior: %s ~ %s%s\n", p_prefix, as.character(ps$person$label), pm_str))
    }
  }
  if (!is.null(x$draws)) {
    d <- dim(x$draws)
    cat(sprintf("Posterior draws: %d iterations x %d chains (%d total draws), %d parameters\n",
                d[[1L]], d[[2L]], d[[1L]] * d[[2L]], d[[3L]]))
  } else if (!is.null(x$estimates)) {
    cat(sprintf("Frequentist estimates: %d parameters (%d in covariance matrix)\n",
                nrow(x$estimates), if (!is.null(x$vcov)) nrow(x$vcov) else 0L))
  }
  cat(sprintf("Numerical qualification passed: %s\n", as.character(qual)))
  invisible(x)
}

summary.mgmfrm_r_fit <- function(object, level = 0.95, ...) {
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || level <= 0 || level >= 1)
    stop("level must lie strictly between 0 and 1.")
  if (!is.null(object$draws)) {
    if (!is.null(object$estimates) && abs(level - 0.95) < 1e-12) {
      tbl <- object$estimates
    } else {
      tbl <- .summarize_bayesian_draws(object$draws, param_labels = object$parameter_labels, level = level)
    }
  } else if (!is.null(object$estimates)) {
    tbl <- object$estimates
    if (abs(level - 0.95) >= 1e-12) {
      crit <- stats::qnorm(1 - (1 - level) / 2)
      tbl$lower <- tbl$estimate - crit * tbl$se
      tbl$upper <- tbl$estimate + crit * tbl$se
    }
  } else {
    tbl <- data.frame()
  }
  out <- list(
    model = if (!is.null(object$model)) object$model else "mfrm",
    method = if (!is.null(object$method)) object$method else "nuts",
    steps = if (!is.null(object$steps)) object$steps else "auto",
    identification = if (!is.null(object$identification)) object$identification else "unknown",
    level = level,
    qualified = if (!is.null(object$metadata$qualification$qualified)) isTRUE(object$metadata$qualification$qualified) else NA,
    estimates = tbl,
    reliability = object$reliability
  )
  class(out) <- "summary.mgmfrm_r_fit"
  out
}

print.summary.mgmfrm_r_fit <- function(x, ...) {
  cat(sprintf("Summary of BayesianMGMFRM fit (model = %s, method = %s, identification = %s, level = %.2f)\n",
              x$model, x$method, x$identification, x$level))
  cat(sprintf("Numerical qualification passed: %s\n\n", as.character(x$qualified)))
  if (nrow(x$estimates)) {
    show_n <- min(nrow(x$estimates), 25L)
    print(x$estimates[seq_len(show_n), , drop = FALSE], row.names = FALSE)
    if (nrow(x$estimates) > show_n)
      cat(sprintf("... (%d additional parameter rows omitted; inspect summary(fit)$estimates)\n",
                  nrow(x$estimates) - show_n))
  }
  invisible(x)
}

diagnostics_mgmfrm <- function(object,
                               type = c("fit_statistics", "reliability", "sampler", "qualification",
                                        "validation", "prior", "residual_correlation",
                                        "weighted_sufficient_score", "fair_average",
                                        "pair_bias", "classification", "ranking"),
                               facet = NULL, counts = NULL, weights = NULL,
                               interval = NULL, interval_method = NULL,
                               reference_plan = NULL, threshold = NULL, comparisons = NULL,
                               shared_effects = NULL, quadrature_orders = c(61L, 121L), quadrature_tolerance = 1e-7,
                               interaction_effects = NULL,
                               baseline = c("sample_mean", "zero_origin"), step_group = NULL,
                               pair = NULL, min_obs = 1L,
                               cutoff = NULL, pass_probability = 0.5,
                               direction = c("higher", "lower"), top_k = NULL,
                               dimension = NULL, parameters = NULL,
                               location = c("parameter", "linked")) {
  type <- match.arg(type)
  has_nondefault_baseline <- !missing(baseline)
  has_nondefault_min_obs <- !missing(min_obs)
  has_nondefault_pass_prob <- !missing(pass_probability)
  has_nondefault_direction <- !missing(direction)
  has_nondefault_location <- !missing(location)

  if (identical(type, "fair_average")) {
    if (!inherits(object, "mgmfrm_r_fit"))
      stop("Fair Average requires a fitted mgmfrm_r_fit object.")
    if (any(!vapply(list(counts, weights, interval_method, pair, cutoff, top_k, dimension, parameters), is.null, logical(1))) ||
        has_nondefault_min_obs || has_nondefault_pass_prob || has_nondefault_direction || has_nondefault_location)
      stop("Unsupported options passed to type = 'fair_average'.")
    if (!is.null(reference_plan)) {
      if (any(!vapply(list(facet, step_group), is.null, logical(1))) || has_nondefault_baseline)
        stop("Use reference_plan and its Weight column for common-plan Fair Average; omit facet, baseline, and step_group.")
      return(.fair_reference(object, reference_plan, if (is.null(interval)) .95 else interval, threshold, comparisons,
                             shared_effects, quadrature_orders, quadrature_tolerance, interaction_effects))
    }
    if (is.null(facet))
      stop("Fair Average requires either an explicit reference_plan (for common-plan person scores) or facet = 'rater' / 'person' / '<facet>' (for FACETS-style marginal Fair-M / Fair-Z).")
    if (any(!vapply(list(threshold, comparisons, shared_effects, interaction_effects), is.null, logical(1))))
      stop("threshold, comparisons, shared_effects, and interaction_effects require an explicit reference_plan.")
    return(.marginal_fair_average(object, facet = facet, baseline = match.arg(baseline),
                                  step_group = step_group, interval = if (is.null(interval)) .95 else interval))
  }
  if (any(!vapply(list(reference_plan, threshold, comparisons, shared_effects, interaction_effects, step_group), is.null, logical(1))) ||
      has_nondefault_baseline)
    stop("reference_plan, threshold, comparisons, baseline, and step_group apply only to fair_average.")

  if (identical(type, "pair_bias")) {
    if (!inherits(object, "mgmfrm_r_fit"))
      stop("pair_bias requires a fitted mgmfrm_r_fit object.")
    if (any(!vapply(list(facet, counts, weights, interval_method, cutoff, top_k, dimension, parameters), is.null, logical(1))) ||
        has_nondefault_pass_prob || has_nondefault_direction || has_nondefault_location)
      stop("pair_bias accepts only pair, min_obs, and interval.")
    return(.pair_bias_mgmfrm(object, pair = pair, min_obs = min_obs,
                             interval = if (is.null(interval)) .95 else interval))
  }
  if (!is.null(pair) || has_nondefault_min_obs)
    stop("pair and min_obs apply only to type = 'pair_bias'.")

  if (identical(type, "classification")) {
    if (!inherits(object, "mgmfrm_r_fit"))
      stop("classification requires a fitted mgmfrm_r_fit object.")
    if (any(!vapply(list(counts, weights, interval_method, top_k), is.null, logical(1))) || has_nondefault_direction)
      stop("classification accepts cutoff, pass_probability, facet, dimension, parameters, interval, and location.")
    if (is.null(cutoff))
      stop("Supply an explicit ability cutoff for type = 'classification'.")
    return(.classification_mgmfrm(
      object, cutoff = cutoff, pass_probability = pass_probability,
      facet = if (is.null(facet)) "person" else facet,
      dimension = dimension, parameters = parameters,
      interval = if (is.null(interval)) .90 else interval,
      location = match.arg(location)
    ))
  }
  if (!is.null(cutoff) || has_nondefault_pass_prob || has_nondefault_location)
    stop("cutoff, pass_probability, and location apply only to type = 'classification'.")

  if (identical(type, "ranking")) {
    if (!inherits(object, "mgmfrm_r_fit"))
      stop("ranking requires a fitted mgmfrm_r_fit object.")
    if (any(!vapply(list(counts, weights, interval_method), is.null, logical(1))))
      stop("ranking accepts direction, top_k, facet, dimension, parameters, and interval.")
    return(.ranking_mgmfrm(
      object, direction = match.arg(direction), top_k = top_k,
      facet = if (is.null(facet)) "person" else facet,
      dimension = dimension, parameters = parameters,
      interval = if (is.null(interval)) .90 else interval
    ))
  }
  if (!is.null(top_k) || has_nondefault_direction || !is.null(dimension) || !is.null(parameters))
    stop("ranking/classification options (direction, top_k, dimension, parameters) do not apply to type = '", type, "'.")
  if (inherits(object, "mgmfrm_gtheory_fit")) {
    type <- match.arg(type)
    if (!is.null(facet)) stop("facet selection does not apply to G-theory diagnostics.")
    if (any(!vapply(list(counts, weights, interval, interval_method), is.null, logical(1)))) {
      if (type != "reliability") stop("D-study options require type = 'reliability'.")
      return(.gtheory_dstudy(object,
        counts = if (is.null(counts)) object$counts else counts,
        weights = if (is.null(weights)) object$weights else weights,
        interval = if (is.null(interval)) object$interval else interval,
        interval_method = if (is.null(interval_method)) "delta" else interval_method))
    }
    return(switch(type, fit_statistics = object$components, reliability = object$dstudy,
                  qualification = object$report$diagnostics, validation = object$report$design$allocation,
                  stop("Requested diagnostic does not apply to ML/REML G-theory.")))
  }
  if (any(!vapply(list(counts, weights, interval, interval_method), is.null, logical(1))))
    stop("D-study options apply to G-theory reliability diagnostics.")
  if (!inherits(object, "mgmfrm_r_fit"))
    stop("Supply an mgmfrm_r_fit object.")
  type <- match.arg(type)
  if (identical(type, "fit_statistics")) {
    fs <- if (!is.null(object$fit_statistics)) object$fit_statistics else list()
    if (is.null(facet)) return(fs)
    if (!is.character(facet) || length(facet) != 1L || !(facet %in% names(fs)))
      stop("Requested facet not found in stored fit_statistics; available: ",
           paste(names(fs), collapse = ", "))
    return(fs[[facet]])
  }
  if (identical(type, "reliability")) {
    return(if (!is.null(object$reliability)) object$reliability else data.frame())
  }
  if (identical(type, "sampler")) {
    s <- object$metadata$sampler
    if (is.null(s)) return(data.frame())
    if (is.list(s) && "retained" %in% names(s)) return(.rows_to_df(s$retained))
    return(.rows_to_df(s))
  }
  if (identical(type, "qualification")) {
    q <- object$metadata$qualification
    if (is.null(q)) return(list())
    return(q)
  }
  if (identical(type, "validation")) {
    dv <- object$metadata$design_validation
    if (is.null(dv)) return(list())
    return(dv)
  }
  if (identical(type, "prior")) {
    ps <- object$metadata$prior_summary
    if (is.null(ps)) return(list())
    return(ps)
  }
  if (identical(type, "residual_correlation")) {
    rc <- object$metadata$residual_correlation
    if (is.null(rc) || !is.list(rc)) return(list())
    return(list(
      facet = rc$facet,
      unit = rc$unit,
      unit_binding = rc$unit_binding,
      n_units = rc$n_units,
      level = rc$level,
      n_draws_evaluated = rc$n_draws_evaluated,
      pairs = .rows_to_df(rc$pairs),
      summary = rc$summary,
      warnings = if (!is.null(rc$warnings)) as.character(unlist(rc$warnings, use.names = FALSE)) else character(0L)
    ))
  }
  if (identical(type, "weighted_sufficient_score")) {
    wss <- object$metadata$weighted_sufficient_score
    if (is.null(wss) || !length(wss)) return(data.frame())
    dfs <- lapply(wss, function(w_blk) {
      df <- .rows_to_df(w_blk$rows)
      if (nrow(df) && !is.null(w_blk$dimension) && !("dimension" %in% names(df))) {
        df <- cbind(data.frame(dimension = rep(as.integer(w_blk$dimension), nrow(df)), stringsAsFactors = FALSE), df)
      }
      df
    })
    all_df <- do.call(rbind, dfs)
    if (!is.null(facet) && nrow(all_df) && ("dimension" %in% names(all_df))) {
      d_idx <- suppressWarnings(as.integer(facet))
      if (length(d_idx) == 1L && !is.na(d_idx)) {
        all_df <- all_df[all_df$dimension == d_idx, , drop = FALSE]
        rownames(all_df) <- NULL
      }
    }
    return(all_df)
  }
}

.mgmfrm_fixed_param_lookup <- function(object) {
  fp <- object$metadata$fixed_parameters
  if (is.null(fp) || !length(fp)) return(numeric(0L))
  vals <- numeric(0L)
  nms <- character(0L)
  for (entry in fp) {
    if (is.list(entry) && !is.null(entry$name) && !is.null(entry$value)) {
      v <- suppressWarnings(as.double(entry$value))
      if (length(v) == 1L && is.finite(v)) {
        nms <- c(nms, as.character(entry$name))
        vals <- c(vals, v)
      }
    }
  }
  setNames(vals, nms)
}

.resolve_contrast_term <- function(key, facet, object, avail_names) {
  key_chr <- as.character(key)
  fixed_map <- .mgmfrm_fixed_param_lookup(object)

  # 1) Explicit stored parameter name (e.g., "rater[2]" or "rater[\"Bea\"]")
  if (key_chr %in% names(fixed_map))
    return(list(param = key_chr, fixed = TRUE, fixed_value = unname(fixed_map[[key_chr]])))
  if (key_chr %in% avail_names) return(list(param = key_chr, fixed = FALSE, fixed_value = 0.0))

  # 2) Resolve bare level through the facet ID dictionary FIRST (prevents numeric-ID vs positional collision!)
  if (!is.null(object$ids) && facet %in% names(object$ids)) {
    lvls <- as.character(object$ids[[facet]])
    idx <- match(key_chr, lvls)
    if (!is.na(idx)) {
      cand_display <- paste0(facet, "[", key_chr, "]")
      if (!is.null(object$parameter_labels) && length(object$parameter_labels)) {
        lbl_hit <- match(cand_display, unname(object$parameter_labels))
        if (!is.na(lbl_hit)) {
          p_nm <- names(object$parameter_labels)[[lbl_hit]]
          if (p_nm %in% names(fixed_map))
            return(list(param = p_nm, fixed = TRUE, fixed_value = unname(fixed_map[[p_nm]])))
          if (p_nm %in% avail_names) return(list(param = p_nm, fixed = FALSE, fixed_value = 0.0))
        }
      }

      mode <- NULL
      if (!is.null(object$metadata$facet_indexing_modes) && facet %in% names(object$metadata$facet_indexing_modes)) {
        mode <- as.character(object$metadata$facet_indexing_modes[[facet]])
      }
      cand_quoted <- paste0(facet, "[\"", key_chr, "\"]")
      cand_pos <- paste0(facet, "[", idx, "]")
      cand_lit <- paste0(facet, "[", key_chr, "]")

      candidates <- if (identical(mode, "quoted_literal")) {
        c(cand_quoted)
      } else if (identical(mode, "literal")) {
        c(cand_lit, cand_quoted)
      } else if (identical(mode, "positional")) {
        c(cand_pos)
      } else {
        # Legacy object without facet_indexing_modes: check quoted literal first, then positional;
        # only allow unquoted literal fallback when key is non-numeric (never let bare "2" hijack "rater[2]"!)
        if (grepl("^[0-9]+$", key_chr)) c(cand_quoted, cand_pos) else c(cand_quoted, cand_pos, cand_lit)
      }
      if (identical(facet, "criterion") && !("item" %in% names(object$ids))) {
        it_quoted <- paste0("item[\"", key_chr, "\"]")
        it_pos <- paste0("item[", idx, "]")
        it_lit <- paste0("item[", key_chr, "]")
        it_cands <- if (identical(mode, "quoted_literal")) {
          c(it_quoted)
        } else if (identical(mode, "literal")) {
          c(it_lit, it_quoted)
        } else if (identical(mode, "positional")) {
          c(it_pos)
        } else {
          if (grepl("^[0-9]+$", key_chr)) c(it_quoted, it_pos) else c(it_quoted, it_pos, it_lit)
        }
        candidates <- c(candidates, it_cands)
      }
      for (cand in unique(candidates)) {
        if (cand %in% names(fixed_map))
          return(list(param = cand, fixed = TRUE, fixed_value = unname(fixed_map[[cand]])))
        if (cand %in% avail_names) return(list(param = cand, fixed = FALSE, fixed_value = 0.0))
      }

      if (identical(facet, "group")) {
        if (idx == 1L) return(list(param = NA_character_, fixed = TRUE, fixed_value = 0.0))
        cand_grp <- paste0("population[group[", idx, "]]")
        if (cand_grp %in% names(fixed_map))
          return(list(param = cand_grp, fixed = TRUE, fixed_value = unname(fixed_map[[cand_grp]])))
        if (cand_grp %in% avail_names) return(list(param = cand_grp, fixed = FALSE, fixed_value = 0.0))
      }
      # Only permit implicit reference-level zero when explicitly 1D MFRM reference-coded AND no fixed_parameters manifest overrides it
      if (identical(object$model, "mfrm") && (object$identification %in% c("reference", "reference_first")) &&
          (facet %in% c("rater", "item")) && idx == 1L && is.null(object$metadata$fixed_parameters)) {
        return(list(param = NA_character_, fixed = TRUE, fixed_value = 0.0))
      }
      stop(sprintf(
        "Free parameter '%s' (level '%s' in facet '%s') is absent from the stored parameters (for example, omitted via `variables`) and cannot be assumed zero.",
        candidates[[1L]], key_chr, facet
      ))
    }
  }

  # 3) Explicit display label (e.g., "rater[7]" or "rater[Bea]" matching parameter_labels)
  if (!is.null(object$parameter_labels) && length(object$parameter_labels)) {
    lbl_hit <- match(key_chr, unname(object$parameter_labels))
    if (!is.na(lbl_hit)) {
      p_nm <- names(object$parameter_labels)[[lbl_hit]]
      if (p_nm %in% names(fixed_map))
        return(list(param = p_nm, fixed = TRUE, fixed_value = unname(fixed_map[[p_nm]])))
      if (p_nm %in% avail_names) return(list(param = p_nm, fixed = FALSE, fixed_value = 0.0))
    }
  }

  # 4) Fallback only when facet has no ID dictionary at all
  if (is.null(object$ids) || !(facet %in% names(object$ids))) {
    for (cand in c(paste0(facet, "[\"", key_chr, "\"]"), paste0(facet, "[", key_chr, "]"))) {
      if (cand %in% names(fixed_map))
        return(list(param = cand, fixed = TRUE, fixed_value = unname(fixed_map[[cand]])))
      if (cand %in% avail_names) return(list(param = cand, fixed = FALSE, fixed_value = 0.0))
    }
  }
  stop(sprintf("Could not resolve level '%s' in facet '%s'.", key_chr, facet))
}

contrast_mgmfrm <- function(object, facet = "rater", a = NULL, b = NULL,
                            weights = NULL, level = 0.95) {
  if (!inherits(object, "mgmfrm_r_fit"))
    stop("Supply an mgmfrm_r_fit object.")
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || level <= 0 || level >= 1)
    stop("level must lie strictly between 0 and 1.")

  has_pair <- !is.null(a) && !is.null(b) && is.null(weights)
  has_weights <- is.null(a) && is.null(b) && !is.null(weights)
  if (!xor(has_pair, has_weights))
    stop("Supply either both a and b (pairwise difference a - b) or a named numeric vector weights.")

  if (has_pair) {
    if (length(a) != 1L || length(b) != 1L)
      stop("a and b must each name a single level.")
    raw_w <- c(1.0, -1.0)
    raw_keys <- c(as.character(a), as.character(b))
    contrast_label <- sprintf("%s: %s - %s", facet, as.character(a), as.character(b))
  } else {
    if (!is.numeric(weights) || !length(weights) || is.null(names(weights)) ||
        anyNA(weights) || any(!is.finite(weights)) || any(!nzchar(names(weights))))
      stop("weights must be a finite named numeric vector.")
    raw_w <- as.double(weights)
    raw_keys <- names(weights)
    contrast_label <- sprintf("%s: weighted (%s)", facet,
                              paste(sprintf("%g*%s", raw_w, raw_keys), collapse = " + "))
  }

  alpha <- (1 - level) / 2
  if (!is.null(object$draws)) {
    arr <- unclass(object$draws)
    d <- dim(arr)
    avail <- dimnames(object$draws)[[3L]]
    d_mat <- matrix(0.0, nrow = d[[1L]], ncol = d[[2L]])
    for (j in seq_along(raw_w)) {
      term <- .resolve_contrast_term(raw_keys[[j]], facet, object, avail)
      if (!term$fixed) {
        col_idx <- match(term$param, avail)
        d_mat <- d_mat + raw_w[[j]] * matrix(arr[, , col_idx], nrow = d[[1L]], ncol = d[[2L]])
      } else if (!is.null(term$fixed_value) && term$fixed_value != 0.0) {
        d_mat <- d_mat + raw_w[[j]] * term$fixed_value
      }
    }
    vec <- as.double(d_mat)
    qs <- stats::quantile(vec, probs = c(alpha, 1 - alpha), names = FALSE)
    return(data.frame(
      contrast = contrast_label,
      estimate = mean(vec),
      sd = stats::sd(vec),
      lower = qs[[1L]],
      upper = qs[[2L]],
      prob_gt_zero = mean(vec > 0),
      rhat = as.double(posterior::rhat(d_mat)),
      ess_bulk = as.double(posterior::ess_bulk(d_mat)),
      ess_tail = as.double(posterior::ess_tail(d_mat)),
      mcse_mean = as.double(posterior::mcse_mean(d_mat)),
      stringsAsFactors = FALSE
    ))
  }

  V <- vcov(object)
  c_vec <- coef(object)
  v_avail <- rownames(V)
  c_avail <- names(c_vec)
  if (is.null(v_avail) || !length(v_avail))
    stop("No parameter covariance matrix is stored on this fit object.")
  avail <- intersect(v_avail, c_avail)
  w_map <- setNames(numeric(length(avail)), avail)
  fixed_offset <- 0.0
  for (j in seq_along(raw_w)) {
    term <- .resolve_contrast_term(raw_keys[[j]], facet, object, avail)
    if (!term$fixed) {
      w_map[[term$param]] <- w_map[[term$param]] + raw_w[[j]]
    } else if (!is.null(term$fixed_value) && term$fixed_value != 0.0) {
      fixed_offset <- fixed_offset + raw_w[[j]] * term$fixed_value
    }
  }
  nz <- which(w_map != 0)
  if (!length(nz)) {
    return(data.frame(
      contrast = contrast_label,
      estimate = fixed_offset,
      se = 0.0,
      se_diagonal_only = 0.0,
      lower = fixed_offset,
      upper = fixed_offset,
      z = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  p_sub <- avail[nz]
  w_sub <- w_map[nz]
  c_sub <- c_vec[p_sub]
  if (anyNA(c_sub) || any(!is.finite(c_sub)))
    stop("Contrast requires non-finite or missing parameter estimates for: ", paste(p_sub[is.na(c_sub) | !is.finite(c_sub)], collapse = ", "), ".")
  V_sub <- V[p_sub, p_sub, drop = FALSE]
  if (anyNA(V_sub) || any(!is.finite(V_sub)))
    stop("Contrast requires non-finite or missing covariance entries for: ", paste(p_sub, collapse = ", "), ".")
  est <- fixed_offset + sum(w_sub * c_sub)
  var_full <- as.double(t(w_sub) %*% V_sub %*% w_sub)
  se_full <- sqrt(max(0.0, var_full))
  se_diag <- sqrt(max(0.0, sum((w_sub^2) * diag(V_sub))))
  crit <- stats::qnorm(1 - alpha)
  data.frame(
    contrast = contrast_label,
    estimate = est,
    se = se_full,
    se_diagonal_only = se_diag,
    lower = est - crit * se_full,
    upper = est + crit * se_full,
    z = if (se_full > 0) est / se_full else NA_real_,
    stringsAsFactors = FALSE
  )
}

.mgmfrm_normalize_sha256 <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x))
    stop("expected_sha256 must be a single 64-character hexadecimal SHA-256 string.")
  h <- tolower(sub("^sha256:", "", trimws(x)))
  if (!grepl("^[0-9a-f]{64}$", h))
    stop("expected_sha256 must be a 64-character hexadecimal SHA-256 digest.")
  h
}

.mgmfrm_sha256_file <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  if (requireNamespace("digest", quietly = TRUE)) {
    return(tolower(digest::digest(file = path, algo = "sha256", serialize = FALSE)))
  }
  shasum <- Sys.which("shasum")
  if (nzchar(shasum)) {
    out <- system2(shasum, c("-a", "256", shQuote(path)), stdout = TRUE, stderr = FALSE)
    if (length(out) >= 1L) {
      tok <- tolower(strsplit(trimws(out[[1L]]), "\\s+")[[1L]][[1L]])
      if (grepl("^[0-9a-f]{64}$", tok)) return(tok)
    }
  }
  sha256sum <- Sys.which("sha256sum")
  if (nzchar(sha256sum)) {
    out <- system2(sha256sum, shQuote(path), stdout = TRUE, stderr = FALSE)
    if (length(out) >= 1L) {
      tok <- tolower(strsplit(trimws(out[[1L]]), "\\s+")[[1L]][[1L]])
      if (grepl("^[0-9a-f]{64}$", tok)) return(tok)
    }
  }
  certutil <- Sys.which("certutil")
  if (nzchar(certutil)) {
    out <- system2(certutil, c("-hashfile", shQuote(path), "SHA256"), stdout = TRUE, stderr = FALSE)
    hits <- grep("^[0-9A-Fa-f]{64}$", gsub("\\s+", "", out), value = TRUE)
    if (length(hits) >= 1L) return(tolower(hits[[1L]]))
  }
  stop("SHA-256 verification requires the 'digest' R package or a system SHA-256 tool (shasum/sha256sum/certutil).")
}

.mgmfrm_sha256_raw <- function(raw_bytes) {
  if (!is.raw(raw_bytes))
    stop("Expected raw byte vector for SHA-256 computation.")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(tolower(digest::digest(raw_bytes, algo = "sha256", serialize = FALSE)))
  }
  tf <- tempfile("mgmfrm-sha-raw-")
  on.exit(unlink(tf), add = TRUE)
  con <- file(tf, open = "wb")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeBin(raw_bytes, con)
  close(con)
  .mgmfrm_sha256_file(tf)
}

.mgmfrm_sha256_string <- function(text) {
  .mgmfrm_sha256_raw(charToRaw(enc2utf8(text)))
}

.mgmfrm_draws_ieee754_sha256 <- function(schema, source_family, scale, parameter_names,
                                         chain_ids, iterations, draw_mat, fixed_parameters,
                                         qualified) {
  wstr <- function(s) c(charToRaw(enc2utf8(as.character(s))), as.raw(0L))
  wi32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")
  wf64 <- function(v) {
    v <- as.double(v)
    v[v == 0] <- 0.0
    writeBin(v, raw(), size = 8L, endian = "little")
  }
  S <- nrow(draw_mat)
  P <- ncol(draw_mat)
  fp_list <- if (is.list(fixed_parameters)) fixed_parameters else list()
  parts <- list(
    wstr("bayesianmgmfrm.draws_ieee754_sha256.v1"),
    wstr(schema),
    wstr(source_family),
    wstr(scale),
    wi32(S),
    wi32(P)
  )
  for (j in seq_len(P)) parts[[length(parts) + 1L]] <- wstr(parameter_names[[j]])
  parts[[length(parts) + 1L]] <- wi32(chain_ids)
  parts[[length(parts) + 1L]] <- wi32(iterations)
  parts[[length(parts) + 1L]] <- wf64(as.double(t(draw_mat)))
  parts[[length(parts) + 1L]] <- wi32(length(fp_list))
  for (fp in fp_list) {
    parts[[length(parts) + 1L]] <- wstr(fp$block)
    parts[[length(parts) + 1L]] <- wstr(fp$name)
    parts[[length(parts) + 1L]] <- wf64(fp$value)
  }
  parts[[length(parts) + 1L]] <- as.raw(if (isTRUE(qualified)) 1L else 0L)
  .mgmfrm_sha256_raw(unlist(parts, use.names = FALSE))
}

.mgmfrm_bundle_constraint_keys <- c(
  "category_levels", "family", "identification", "location_mode", "scale_identification",
  "status", "step_owner", "threshold_owner", "thresholds"
)

.mgmfrm_handoff_bundle_sha256 <- function(draws_ieee754_sha256, ids, prior_and_reference, missing_audit) {
  wstr <- function(s) c(charToRaw(enc2utf8(as.character(s))), as.raw(0L))
  wi32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "little")
  parts <- list(
    wstr("bayesianmgmfrm.handoff_bundle_sha256.v1"),
    wstr(tolower(as.character(draws_ieee754_sha256)))
  )

  # 1) Canonical ids dictionary (ASCII-sorted keys via C locale, ordered string labels)
  if (is.null(ids) || !is.list(ids) || !length(ids)) {
    parts[[length(parts) + 1L]] <- wi32(0L)
  } else {
    id_keys <- names(ids)
    id_keys <- id_keys[order(id_keys, method = "radix")]
    parts[[length(parts) + 1L]] <- wi32(length(id_keys))
    for (ks in id_keys) {
      vals <- as.character(unlist(ids[[ks]], use.names = FALSE))
      parts[[length(parts) + 1L]] <- wstr(ks)
      parts[[length(parts) + 1L]] <- wi32(length(vals))
      for (v in vals) parts[[length(parts) + 1L]] <- wstr(v)
    }
  }

  # 2) Canonical effective constraint fields from prior_and_reference
  c_keys <- character(0L)
  c_vals <- character(0L)
  if (is.list(prior_and_reference) && length(prior_and_reference)) {
    for (ck in .mgmfrm_bundle_constraint_keys) {
      if (ck %in% names(prior_and_reference)) {
        v <- prior_and_reference[[ck]]
        if (identical(ck, "category_levels") && (is.list(v) || is.numeric(v)) && length(v) >= 1L && is.null(names(v))) {
          iv <- .mgmfrm_strict_int_vec(v, "prior_and_reference$category_levels")
          c_keys <- c(c_keys, ck)
          c_vals <- c(c_vals, paste(iv, collapse = ","))
        } else if (!is.null(v) && length(v) == 1L && (is.character(v) || is.numeric(v) || is.logical(v)) && !is.na(v)) {
          vs <- if (is.logical(v)) tolower(as.character(v)) else as.character(v)
          c_keys <- c(c_keys, ck)
          c_vals <- c(c_vals, vs)
        }
      }
    }
  }
  parts[[length(parts) + 1L]] <- wi32(length(c_keys))
  for (i in seq_along(c_keys)) {
    parts[[length(parts) + 1L]] <- wstr(c_keys[[i]])
    parts[[length(parts) + 1L]] <- wstr(c_vals[[i]])
  }

  # 3) Canonical missing_audit record
  if (is.null(missing_audit) || !is.list(missing_audit)) {
    parts[[length(parts) + 1L]] <- as.raw(0L)
  } else {
    parts[[length(parts) + 1L]] <- as.raw(1L)
    parts[[length(parts) + 1L]] <- wi32(if (!is.null(missing_audit$n_input_rows)) missing_audit$n_input_rows else 0L)
    parts[[length(parts) + 1L]] <- wi32(if (!is.null(missing_audit$n_retained_rows)) missing_audit$n_retained_rows else 0L)
    parts[[length(parts) + 1L]] <- wi32(if (!is.null(missing_audit$n_dropped_rows)) missing_audit$n_dropped_rows else 0L)
    drows <- if (!is.null(missing_audit$dropped_rows) && length(missing_audit$dropped_rows)) {
      as.integer(unlist(missing_audit$dropped_rows, use.names = FALSE))
    } else {
      integer(0L)
    }
    parts[[length(parts) + 1L]] <- wi32(length(drows))
    if (length(drows)) parts[[length(parts) + 1L]] <- wi32(drows)
    dbc <- missing_audit$dropped_by_column
    if (is.null(dbc) || !is.list(dbc) || !length(dbc)) {
      parts[[length(parts) + 1L]] <- wi32(0L)
    } else {
      dbc_keys <- names(dbc)
      dbc_keys <- dbc_keys[order(dbc_keys, method = "radix")]
      parts[[length(parts) + 1L]] <- wi32(length(dbc_keys))
      for (ks in dbc_keys) {
        parts[[length(parts) + 1L]] <- wstr(ks)
        parts[[length(parts) + 1L]] <- wi32(dbc[[ks]])
      }
    }
  }
  .mgmfrm_sha256_raw(unlist(parts, use.names = FALSE))
}

.mgmfrm_reconstruct_native_ids <- function(raw, all_names) {
  if (is.list(raw$ids) && length(raw$ids)) {
    return(lapply(raw$ids, function(x) as.character(unlist(x, use.names = FALSE))))
  }
  out <- list()
  m <- regexec("^([A-Za-z0-9_]+)\\[([^\\]]+)\\]$", all_names, perl = TRUE)
  reg <- regmatches(all_names, m)
  for (tok in reg) {
    if (length(tok) == 3L) {
      blk <- tok[[2L]]
      lvl <- sub('^"(.*)"$', "\\1", tok[[3L]], perl = TRUE)
      if (blk %in% c("step", "steps", "population", "population_sd", "residual_sd",
                     "loading", "standardized_loading", "consistency", "ability_sd", "ability_mean",
                     "latent_correlation", "partial_correlation")) next
      if (is.null(out[[blk]])) out[[blk]] <- character(0L)
      if (!(lvl %in% out[[blk]])) out[[blk]] <- c(out[[blk]], lvl)
    }
  }
  out
}

.mgmfrm_native_param_labels <- function(sel_names, all_names, id_dict, eff_steps) {
  modes <- list()
  lbl_map <- setNames(sel_names, sel_names)
  for (fn in names(id_dict)) {
    lvls <- as.character(id_dict[[fn]])
    L <- length(lvls)
    pat <- paste0("^", fn, "\\[([^\\]]+)\\]$")
    all_hits <- grep(pat, all_names, value = TRUE, perl = TRUE)
    if (!length(all_hits) && identical(fn, "criterion") && !("item" %in% names(id_dict))) {
      pat <- "^item\\[([^\\]]+)\\]$"
      all_hits <- grep(pat, all_names, value = TRUE, perl = TRUE)
    }
    if (!length(all_hits)) {
      modes[[fn]] <- "positional"
      next
    }
    toks <- sub(pat, "\\1", all_hits, perl = TRUE)
    if (any(grepl('^".*"$', toks, perl = TRUE))) {
      modes[[fn]] <- "quoted_literal"
    } else if (identical(toks, lvls) || (all(toks %in% lvls) && any(!(toks %in% as.character(seq_len(L)))))) {
      modes[[fn]] <- "literal"
    } else if (all(toks %in% as.character(seq_len(L)))) {
      modes[[fn]] <- "positional"
    } else {
      modes[[fn]] <- "literal"
    }
    sel_hits <- grep(pat, sel_names, value = TRUE, perl = TRUE)
    for (nm in sel_hits) {
      tk <- sub(pat, "\\1", nm, perl = TRUE)
      if (identical(modes[[fn]], "quoted_literal")) {
        lbl_map[[nm]] <- paste0(fn, "[", sub('^"(.*)"$', "\\1", tk, perl = TRUE), "]")
      } else if (identical(modes[[fn]], "positional")) {
        idx <- suppressWarnings(as.integer(tk))
        if (!is.na(idx) && idx >= 1L && idx <= L) {
          lbl_map[[nm]] <- paste0(fn, "[", lvls[[idx]], "]")
        }
      } else {
        lbl_map[[nm]] <- paste0(fn, "[", tk, "]")
      }
    }
  }
  # Also relabel step / population / generalized parameters when positional
  if (length(id_dict)) {
    other_idx <- which(lbl_map == sel_names &
                       grepl("^(steps?|population|rater_consistency|consistency|loading|standardized_loading|person|item)\\[", sel_names, perl = TRUE))
    if (length(other_idx)) {
      lbl_map[other_idx] <- .label_mgmfrm_parameters(sel_names[other_idx], id_dict, step_owner = eff_steps)
    }
  }
  list(labels = lbl_map, modes = modes)
}

.mgmfrm_strict_int_vec <- function(x, label) {
  if (is.null(x))
    stop("Missing required integer vector '", label, "' in handoff JSON.")
  raw_u <- unlist(x, use.names = FALSE)
  if (is.null(raw_u) || !length(raw_u))
    return(integer(0L))
  if (!is.numeric(raw_u) || anyNA(raw_u) || any(!is.finite(raw_u) | raw_u != trunc(raw_u)))
    stop("Non-integer or missing entry in '", label, "' in handoff JSON.")
  as.integer(raw_u)
}

.mgmfrm_strict_dbl_vec <- function(x, label) {
  if (is.null(x))
    stop("Missing required numeric vector '", label, "' in handoff JSON.")
  raw_u <- unlist(x, use.names = FALSE)
  if (is.null(raw_u) || !length(raw_u))
    return(numeric(0L))
  if (!is.numeric(raw_u) || anyNA(raw_u) || any(!is.finite(raw_u)))
    stop("Non-finite, non-numeric, or missing entry in '", label, "' in handoff JSON.")
  as.double(raw_u)
}

.mgmfrm_strict_chr_vec <- function(x, label) {
  if (is.null(x))
    stop("Missing required character vector '", label, "' in handoff JSON.")
  raw_u <- unlist(x, use.names = FALSE)
  if (is.null(raw_u) || !length(raw_u))
    return(character(0L))
  if (!is.character(raw_u) || anyNA(raw_u) || any(!nzchar(raw_u)))
    stop("Invalid or empty string in '", label, "' in handoff JSON.")
  as.character(raw_u)
}

.mgmfrm_canonical_payload_digest <- function(payload_core) {
  json_txt <- as.character(jsonlite::toJSON(
    payload_core, auto_unbox = TRUE, digits = NA, null = "null", na = "null"
  ))
  norm_obj <- jsonlite::fromJSON(json_txt, simplifyVector = FALSE)
  norm_txt <- as.character(jsonlite::toJSON(
    norm_obj, auto_unbox = TRUE, digits = NA, null = "null", na = "null"
  ))
  .mgmfrm_sha256_string(norm_txt)
}

handoff_mgmfrm <- function(object, path, return_receipt = FALSE) {
  if (!inherits(object, "mgmfrm_r_fit"))
    stop("Supply an mgmfrm_r_fit object.")
  if (!is.character(path) || length(path) != 1L || !nzchar(path))
    stop("Supply a single target file path.")
  if (!is.logical(return_receipt) || length(return_receipt) != 1L || is.na(return_receipt))
    stop("return_receipt must be TRUE or FALSE.")
  path <- normalizePath(path, mustWork = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  is_bayes <- !is.null(object$draws)
  V <- vcov(object)
  draws_dim <- if (is_bayes) as.integer(dim(object$draws)) else integer(0L)
  draws_iters <- if (is_bayes) rep(seq_len(draws_dim[[1L]]), times = draws_dim[[2L]]) else integer(0L)
  draws_chains <- if (is_bayes) rep(seq_len(draws_dim[[2L]]), each = draws_dim[[1L]]) else integer(0L)
  payload_core <- list(
    schema = "bayesianmgmfrm.r_portable_fit.v2",
    kind = if (is_bayes) "bayesian" else "frequentist",
    model = if (!is.null(object$model)) object$model else "mfrm",
    method = if (!is.null(object$method)) object$method else if (is_bayes) "nuts" else "mmle",
    steps = if (!is.null(object$steps)) object$steps else "auto",
    identification = if (!is.null(object$identification)) object$identification else "isometric",
    category_levels = if (is.list(object$category_levels)) {
      lapply(object$category_levels, function(v) as.list(as.integer(v)))
    } else {
      as.integer(object$category_levels)
    },
    columns = as.list(object$columns),
    ids = lapply(object$ids, as.list),
    parameter_labels = as.list(object$parameter_labels),
    draws_dim = draws_dim,
    draws_variables = if (is_bayes) dimnames(object$draws)[[3L]] else character(0L),
    draws_iterations = draws_iters,
    draws_chains = draws_chains,
    draws_flat = if (is_bayes) as.double(unclass(object$draws)) else numeric(0L),
    estimates = if (!is.null(object$estimates)) object$estimates else data.frame(),
    vcov_names = if (!is.null(rownames(V))) rownames(V) else character(0L),
    vcov_flat = as.double(V),
    fit_statistics = object$fit_statistics,
    reliability = if (!is.null(object$reliability)) object$reliability else data.frame(),
    metadata = object$metadata
  )
  payload_sha256 <- .mgmfrm_canonical_payload_digest(payload_core)
  payload <- c(payload_core, list(payload_sha256 = payload_sha256))
  # Preserve binary64 draws: 15-digit rounding can change folded-rank ties in R-hat.
  jsonlite::write_json(payload, path = path, auto_unbox = TRUE, digits = I(17L), null = "null", na = "null")
  out_path <- normalizePath(path, mustWork = TRUE)
  if (isTRUE(return_receipt)) {
    return(list(
      path = out_path,
      schema = payload_core$schema,
      kind = payload_core$kind,
      sha256 = .mgmfrm_sha256_file(out_path),
      payload_sha256 = payload_sha256,
      n_variables = if (is_bayes) length(payload_core$draws_variables) else nrow(payload_core$estimates),
      draws_dim = draws_dim
    ))
  }
  invisible(out_path)
}

read_handoff_mgmfrm <- function(path, variables = NULL, expected_sha256 = NULL) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path))
    stop("Supply a single handoff JSON file path.")
  path <- normalizePath(path, mustWork = TRUE)
  if (!is.null(variables) && (!is.character(variables) || !length(variables) ||
      anyNA(variables) || any(!nzchar(variables)) || anyDuplicated(variables)))
    stop("Choose distinct parameter names or use NULL for all parameters.")

  file_sha256 <- NULL
  if (!is.null(expected_sha256)) {
    exp_h <- .mgmfrm_normalize_sha256(expected_sha256)
    file_sha256 <- .mgmfrm_sha256_file(path)
    if (!identical(file_sha256, exp_h))
      stop("Handoff file SHA-256 mismatch: expected ", exp_h, ", got ", file_sha256, ".")
  }

  raw <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(raw))
    stop("Invalid handoff JSON: top-level object must be a JSON object.")
  schema <- if (!is.null(raw$schema) && length(raw$schema) == 1L) as.character(raw$schema) else ""

  if (identical(schema, "bayesianmgmfrm.r_portable_fit.v2")) {
    receipt_present <- !is.null(raw$payload_sha256)
    if (receipt_present) {
      stored_h <- .mgmfrm_normalize_sha256(as.character(raw$payload_sha256))
      raw_core <- raw[setdiff(names(raw), "payload_sha256")]
      actual_h <- .mgmfrm_canonical_payload_digest(raw_core)
      if (!identical(actual_h, stored_h))
        stop("Handoff payload_sha256 mismatch (file was modified or corrupted): expected ", stored_h, ", got ", actual_h, ".")
    }

    kind <- if (!is.null(raw$kind) && length(raw$kind) == 1L) as.character(raw$kind) else ""
    if (!(kind %in% c("bayesian", "frequentist")))
      stop("Invalid handoff kind '", kind, "'; expected 'bayesian' or 'frequentist'.")

    id_dict <- if (is.list(raw$ids)) lapply(raw$ids, function(x) unlist(x, use.names = FALSE)) else list()
    cols <- unlist(raw$columns)
    levels <- if (is.null(raw$category_levels) || !length(raw$category_levels)) {
      integer(0L)
    } else if (is.list(raw$category_levels) && !is.null(names(raw$category_levels))) {
      lapply(raw$category_levels, .mgmfrm_strict_int_vec, "category_levels")
    } else {
      .mgmfrm_strict_int_vec(raw$category_levels, "category_levels")
    }
    param_labels <- if (is.list(raw$parameter_labels) && length(raw$parameter_labels)) {
      setNames(as.character(unlist(raw$parameter_labels, use.names = FALSE)),
               names(raw$parameter_labels))
    } else {
      character(0L)
    }
    fit_stats <- if (is.list(raw$fit_statistics)) lapply(raw$fit_statistics, .rows_to_df) else list()
    rel_df <- .rows_to_df(raw$reliability)

    if (identical(kind, "bayesian")) {
      d <- .mgmfrm_strict_int_vec(raw$draws_dim, "draws_dim")
      if (length(d) != 3L || any(d < 1L))
        stop("Invalid draws_dim in handoff JSON: expected 3 positive integers (iteration, chain, variable).")
      v_names <- .mgmfrm_strict_chr_vec(raw$draws_variables, "draws_variables")
      if (length(v_names) != d[[3L]] || anyDuplicated(v_names))
        stop("Invalid draws_variables in handoff JSON: expected ", d[[3L]], " distinct nonempty parameter names, got ", length(v_names), ".")

      expected_len <- as.double(d[[1L]]) * as.double(d[[2L]]) * as.double(d[[3L]])
      flat_vals <- .mgmfrm_strict_dbl_vec(raw$draws_flat, "draws_flat")
      if (as.double(length(flat_vals)) != expected_len)
        stop("Corrupted or truncated handoff draws_flat: expected ", expected_len,
             " finite values for dim (", paste(d, collapse = "x"), "), got ", length(flat_vals), ".")

      # Validate explicit chain/iteration mapping if present (mandatory complete bijection, no duplicates)
      has_iter <- !is.null(raw$draws_iterations) && length(raw$draws_iterations) > 0L
      has_chain <- !is.null(raw$draws_chains) && length(raw$draws_chains) > 0L
      if (xor(has_iter, has_chain))
        stop("Incomplete draw index metadata: draws_iterations and draws_chains must either both be present or both absent.")
      if (has_iter && has_chain) {
        iters <- .mgmfrm_strict_int_vec(raw$draws_iterations, "draws_iterations")
        chains <- .mgmfrm_strict_int_vec(raw$draws_chains, "draws_chains")
        n_draws_total <- d[[1L]] * d[[2L]]
        if (length(iters) != n_draws_total || length(chains) != n_draws_total)
          stop("Corrupted draw index vectors: expected length ", n_draws_total,
               ", got iterations=", length(iters), ", chains=", length(chains), ".")
        if (any(iters < 1L | iters > d[[1L]]) || any(chains < 1L | chains > d[[2L]]))
          stop("Out-of-range draw index in draws_iterations or draws_chains.")
        pair_key <- (chains - 1L) * d[[1L]] + iters
        if (anyDuplicated(pair_key))
          stop("Duplicate (iteration, chain) index detected in handoff JSON.")
        if (length(unique(pair_key)) != n_draws_total)
          stop("Incomplete (iteration, chain) coverage in handoff JSON.")
        # Reorder into canonical (iteration, chain, variable) array if stored in non-canonical order
        canonical_key <- seq_len(n_draws_total)
        if (!identical(pair_key, canonical_key)) {
          mat_raw <- matrix(flat_vals, nrow = n_draws_total, ncol = d[[3L]])
          arr <- array(NA_real_, dim = d,
                       dimnames = list(iteration = NULL, chain = NULL, variable = v_names))
          for (idx_row in seq_len(n_draws_total)) {
            arr[iters[[idx_row]], chains[[idx_row]], ] <- mat_raw[idx_row, ]
          }
        } else {
          arr <- array(flat_vals, dim = d,
                       dimnames = list(iteration = NULL, chain = NULL, variable = v_names))
        }
      } else {
        arr <- array(flat_vals, dim = d,
                     dimnames = list(iteration = NULL, chain = NULL, variable = v_names))
      }

      if (length(param_labels) && !all(v_names %in% names(param_labels)))
        stop("parameter_labels in handoff JSON does not cover all draws_variables.")
      if (!is.null(variables)) {
        idx <- match(variables, v_names)
        if (anyNA(idx))
          stop("Unknown draw variable; available: ", paste(v_names, collapse = ", "))
        arr <- arr[, , idx, drop = FALSE]
        v_names <- variables
        if (length(param_labels)) param_labels <- param_labels[v_names]
      }
      draws_arr <- posterior::as_draws_array(arr)
      est_df <- .summarize_bayesian_draws(draws_arr, param_labels = param_labels, level = 0.95)
      vcov_mat <- .vcov_from_draws(draws_arr)
    } else {
      draws_arr <- NULL
      est_df <- .rows_to_df(raw$estimates)
      if (!nrow(est_df) || !all(c("variable", "estimate", "se") %in% names(est_df)))
        stop("Frequentist handoff JSON must include nonempty estimates with columns variable, estimate, and se.")
      if (anyNA(est_df$variable) || anyDuplicated(est_df$variable))
        stop("Frequentist handoff estimates contain missing or duplicated variable names.")
      if (anyNA(est_df$estimate) || any(!is.finite(as.double(est_df$estimate))))
        stop("Frequentist handoff estimates contain non-finite estimate values.")
      if (!is.null(variables) && nrow(est_df)) {
        idx <- match(variables, est_df$variable)
        if (anyNA(idx))
          stop("Unknown parameter; available: ", paste(est_df$variable, collapse = ", "))
        est_df <- est_df[idx, , drop = FALSE]
        rownames(est_df) <- NULL
        if (length(param_labels)) param_labels <- param_labels[variables]
      }
      vc_names <- if (is.null(raw$vcov_names) || !length(raw$vcov_names)) character(0L) else
        .mgmfrm_strict_chr_vec(raw$vcov_names, "vcov_names")
      if (anyDuplicated(vc_names))
        stop("Duplicate names in vcov_names in handoff JSON.")
      if (length(vc_names)) {
        vc_flat <- .mgmfrm_strict_dbl_vec(raw$vcov_flat, "vcov_flat")
        expected_vc <- as.double(length(vc_names)) * as.double(length(vc_names))
        if (as.double(length(vc_flat)) != expected_vc)
          stop("Corrupted or truncated vcov_flat: expected ", expected_vc,
               " finite values for ", length(vc_names), "x", length(vc_names), " matrix, got ", length(vc_flat), ".")
        vcov_mat <- matrix(vc_flat, nrow = length(vc_names), ncol = length(vc_names),
                           dimnames = list(vc_names, vc_names))
        if (max(abs(vcov_mat - t(vcov_mat))) > 1e-8 * max(1.0, max(abs(vcov_mat))))
          stop("Corrupted vcov matrix in handoff JSON: matrix is not symmetric.")
        if (!is.null(variables)) {
          keep_vc <- intersect(variables, vc_names)
          vcov_mat <- if (length(keep_vc)) vcov_mat[keep_vc, keep_vc, drop = FALSE] else
            matrix(numeric(0L), nrow = 0L, ncol = 0L)
        }
      } else {
        vc_flat <- unlist(raw$vcov_flat, use.names = FALSE)
        if (!is.null(vc_flat) && length(vc_flat) > 0L)
          stop("vcov_flat is nonempty while vcov_names is empty in handoff JSON.")
        vcov_mat <- matrix(numeric(0L), nrow = 0L, ncol = 0L)
      }
    }

    meta_out <- if (is.list(raw$metadata)) raw$metadata else list()
    meta_out$handoff_verification <- list(
      schema = schema,
      verification_kind = if (!is.null(expected_sha256) && receipt_present) {
        "file_sha256_and_payload_sha256"
      } else if (receipt_present) {
        "payload_sha256_only"
      } else if (!is.null(expected_sha256)) {
        "file_sha256_only"
      } else {
        "unverified"
      },
      file_sha256_verified = !is.null(expected_sha256),
      file_sha256 = file_sha256,
      payload_sha256_present = receipt_present,
      payload_sha256_verified = receipt_present
    )

    res <- list(
      draws = draws_arr,
      estimates = est_df,
      vcov = vcov_mat,
      ids = id_dict,
      parameter_labels = param_labels,
      fit_statistics = fit_stats,
      reliability = rel_df,
      model = as.character(raw$model),
      method = as.character(raw$method),
      steps = as.character(raw$steps),
      identification = as.character(raw$identification),
      category_levels = levels,
      columns = cols,
      metadata = meta_out
    )
    class(res) <- "mgmfrm_r_fit"
    return(res)
  }

  if (schema %in% c("bayesianmgmfrm.portable_joint_draws_handoff.v1",
                    "bayesianmgmfrm.portable_joint_draws.v1")) {
    all_names <- .mgmfrm_strict_chr_vec(raw$parameter_names, "parameter_names")
    if (!length(all_names) || anyDuplicated(all_names))
      stop("Invalid or duplicated parameter_names in native PortableHandoff JSON.")
    sel_names <- if (is.null(variables)) all_names else variables
    cols_idx <- match(sel_names, all_names)
    if (anyNA(cols_idx))
      stop("Unknown draw variable; available: ", paste(all_names, collapse = ", "))

    n_iter <- .mgmfrm_strict_int_vec(raw$draws_per_chain, "draws_per_chain")
    n_chains <- .mgmfrm_strict_int_vec(raw$n_chains, "n_chains")
    if (length(n_iter) != 1L || n_iter < 1L || length(n_chains) != 1L || n_chains < 1L)
      stop("Invalid draws_per_chain or n_chains in native PortableHandoff JSON.")
    n_total <- n_iter * n_chains

    iters <- .mgmfrm_strict_int_vec(raw$iterations, "iterations")
    chains_id <- .mgmfrm_strict_int_vec(raw$chain_ids, "chain_ids")
    if (!is.list(raw$draws) || length(raw$draws) != n_total ||
        length(iters) != n_total || length(chains_id) != n_total)
      stop("Corrupted or truncated native PortableHandoff JSON: expected ", n_total,
           " draw rows, got draws=", length(raw$draws),
           ", iterations=", length(iters), ", chain_ids=", length(chains_id), ".")

    arr <- array(NA_real_, dim = c(n_iter, n_chains, length(sel_names)),
                 dimnames = list(iteration = NULL, chain = NULL, variable = sel_names))
    draw_mat_all <- matrix(NA_real_, nrow = n_total, ncol = length(all_names))
    seen <- matrix(FALSE, nrow = n_iter, ncol = n_chains)
    n_all <- length(all_names)
    for (i in seq_len(n_total)) {
      it <- iters[[i]]
      ch <- chains_id[[i]]
      if (it < 1L || it > n_iter || ch < 1L || ch > n_chains)
        stop("Out-of-range (iteration, chain) index (", it, ", ", ch, ") at row ", i, " in native PortableHandoff JSON.")
      if (seen[it, ch])
        stop("Duplicate (iteration, chain) index (", it, ", ", ch, ") in native PortableHandoff JSON.")
      row_vals <- .mgmfrm_strict_dbl_vec(raw$draws[[i]], paste0("draws[[", i, "]]"))
      if (length(row_vals) != n_all)
        stop("Draw row ", i, " has length ", length(row_vals), "; expected ", n_all, " parameters.")
      draw_mat_all[i, ] <- row_vals
      arr[it, ch, ] <- row_vals[cols_idx]
      seen[it, ch] <- TRUE
    }
    if (!all(seen))
      stop("Incomplete (iteration, chain) coverage in native PortableHandoff JSON.")

    src_fam <- if (!is.null(raw$source_family) && length(raw$source_family) == 1L && nzchar(as.character(raw$source_family))) {
      as.character(raw$source_family)
    } else if (!is.null(raw$producer$model_family) && length(raw$producer$model_family) == 1L && nzchar(as.character(raw$producer$model_family))) {
      as.character(raw$producer$model_family)
    } else {
      "mfrm"
    }
    scale_str <- if (!is.null(raw$scale) && length(raw$scale) == 1L) as.character(raw$scale) else "model"

    ieee_present <- !is.null(raw$draws_ieee754_sha256) && length(raw$draws_ieee754_sha256) == 1L && nzchar(as.character(raw$draws_ieee754_sha256))
    ieee_verified <- FALSE
    actual_ieee <- NULL
    if (ieee_present) {
      stored_ieee <- .mgmfrm_normalize_sha256(as.character(raw$draws_ieee754_sha256))
      q_flag <- isTRUE(raw$qualification$qualified)
      actual_ieee <- .mgmfrm_draws_ieee754_sha256(
        schema = schema,
        source_family = src_fam,
        scale = scale_str,
        parameter_names = all_names,
        chain_ids = chains_id,
        iterations = iters,
        draw_mat = draw_mat_all,
        fixed_parameters = raw$fixed_parameters,
        qualified = q_flag
      )
      if (!identical(actual_ieee, stored_ieee))
        stop("Native PortableHandoff draws_ieee754_sha256 mismatch (file was modified or corrupted): expected ",
             stored_ieee, ", got ", actual_ieee, ".")
      ieee_verified <- TRUE
    }

    bundle_present <- !is.null(raw$handoff_bundle_sha256) && length(raw$handoff_bundle_sha256) == 1L && nzchar(as.character(raw$handoff_bundle_sha256))
    bundle_verified <- FALSE
    if (bundle_present) {
      if (!ieee_verified)
        stop("Native PortableHandoff handoff_bundle_sha256 requires a valid draws_ieee754_sha256.")
      stored_bundle <- .mgmfrm_normalize_sha256(as.character(raw$handoff_bundle_sha256))
      actual_bundle <- .mgmfrm_handoff_bundle_sha256(
        draws_ieee754_sha256 = actual_ieee,
        ids = raw$ids,
        prior_and_reference = raw$prior_and_reference,
        missing_audit = raw$missing_audit
      )
      if (!identical(actual_bundle, stored_bundle))
        stop("Native PortableHandoff handoff_bundle_sha256 mismatch (IDs, effective constraints, or missing_audit modified): expected ",
             stored_bundle, ", got ", actual_bundle, ".")
      bundle_verified <- TRUE
    }

    ids_and_audit_verified <- !is.null(expected_sha256) || bundle_verified
    if (!ids_and_audit_verified) {
      if (ieee_verified) {
        warning("Native PortableHandoff JSON verified numeric draws only (draws_ieee754_sha256); handoff_bundle_sha256 is absent and expected_sha256 was not supplied, so ID dictionary, constraints, and missing_audit are NOT verified.")
      } else {
        warning("Native PortableHandoff JSON has no verified checksum (handoff_bundle_sha256 and draws_ieee754_sha256 are absent and expected_sha256 was not supplied); Julia handoff_hash is not verified offline in R.")
      }
    }

    mdl <- if (identical(src_fam, "gmfrm")) {
      "gmfrm"
    } else if (src_fam %in% c("mgmfrm", "scale_identified_mgmfrm")) {
      "mgmfrm"
    } else if (src_fam %in% c("mfrm", "additive_facets")) {
      "mfrm"
    } else {
      src_fam
    }
    pr <- if (is.list(raw$prior_and_reference)) raw$prior_and_reference else list()
    eff_steps <- if (!is.null(pr$threshold_owner) && length(pr$threshold_owner) == 1L && is.character(pr$threshold_owner)) {
      as.character(pr$threshold_owner)
    } else if (!is.null(pr$step_owner) && length(pr$step_owner) == 1L && is.character(pr$step_owner)) {
      as.character(pr$step_owner)
    } else if (identical(mdl, "gmfrm")) {
      "rater"
    } else if (identical(mdl, "mgmfrm")) {
      "item"
    } else {
      "handoff"
    }
    eff_id <- if (!is.null(pr$scale_identification) && length(pr$scale_identification) == 1L && is.character(pr$scale_identification)) {
      as.character(pr$scale_identification)
    } else if (!is.null(pr$facet_identification) && length(pr$facet_identification) == 1L && is.character(pr$facet_identification)) {
      as.character(pr$facet_identification)
    } else if (!is.null(pr$identification) && length(pr$identification) == 1L && is.character(pr$identification)) {
      as.character(pr$identification)
    } else if (identical(mdl, "gmfrm")) {
      "gmfrm_item_sum_to_zero"
    } else {
      "handoff"
    }
    pop_loc_mode <- if (!is.null(pr$population_location_mode) && length(pr$population_location_mode) == 1L && is.character(pr$population_location_mode)) {
      as.character(pr$population_location_mode)
    } else if (!is.null(pr$location_mode) && length(pr$location_mode) == 1L && is.character(pr$location_mode)) {
      as.character(pr$location_mode)
    } else {
      NULL
    }

    id_dict <- .mgmfrm_reconstruct_native_ids(raw, all_names)
    lbl_info <- .mgmfrm_native_param_labels(sel_names, all_names, id_dict, eff_steps)
    param_labels <- lbl_info$labels

    relabel_native_lvl <- function(val, blk) {
      if (!is.null(blk) && blk %in% names(id_dict) && identical(lbl_info$modes[[blk]], "positional")) {
        iv <- suppressWarnings(as.integer(val))
        if (length(iv) == 1L && !is.na(iv) && iv == as.numeric(val) && iv >= 1L && iv <= length(id_dict[[blk]])) {
          return(as.character(id_dict[[blk]][[iv]]))
        }
      }
      as.character(val)
    }

    parse_native_cat_decl <- function(decl, label_ctx) {
      if (is.list(decl) && !is.null(names(decl)) && length(decl)) {
        cats_by_g <- lapply(decl, .mgmfrm_strict_int_vec, label_ctx)
        all_same <- length(cats_by_g) <= 1L || all(vapply(cats_by_g[-1L], function(v) identical(v, cats_by_g[[1L]]), logical(1L)))
        if (all_same) {
          return(unname(cats_by_g[[1L]]))
        }
        g_names <- vapply(names(decl), function(nm) relabel_native_lvl(nm, eff_steps), character(1L))
        return(setNames(cats_by_g, g_names))
      }
      .mgmfrm_strict_int_vec(decl, label_ctx)
    }

    nat_levels <- integer(0L)
    rec_nat <- if (is.list(pr$record)) pr$record else NULL
    if (is.list(rec_nat$category_support) && length(rec_nat$category_support)) {
      cs_list <- rec_nat$category_support
      cats_by_g <- lapply(cs_list, function(e) .mgmfrm_strict_int_vec(e$categories, "category_support$categories"))
      all_same <- length(cats_by_g) <= 1L || all(vapply(cats_by_g[-1L], function(v) identical(v, cats_by_g[[1L]]), logical(1L)))
      if (all_same) {
        nat_levels <- cats_by_g[[1L]]
      } else {
        g_names <- vapply(cs_list, function(e) {
          ow <- if (!is.null(e$owner)) as.character(e$owner) else eff_steps
          relabel_native_lvl(e$level, ow)
        }, character(1L))
        nat_levels <- setNames(cats_by_g, g_names)
      }
    } else if (!is.null(rec_nat$categories) && length(rec_nat$categories) &&
               is.list(rec_nat$supports) && length(rec_nat$supports)) {
      cats_all <- .mgmfrm_strict_int_vec(rec_nat$categories, "record$categories")
      cats_by_g <- lapply(rec_nat$supports, function(s_idx) {
        iv <- .mgmfrm_strict_int_vec(s_idx, "record$supports")
        cats_all[iv]
      })
      all_same <- length(cats_by_g) <= 1L || all(vapply(cats_by_g[-1L], function(v) identical(v, cats_by_g[[1L]]), logical(1L)))
      if (all_same) {
        nat_levels <- cats_by_g[[1L]]
      } else {
        ow_rec <- if (!is.null(rec_nat$owner)) as.character(rec_nat$owner) else eff_steps
        gl_raw <- unlist(rec_nat$group_levels, use.names = FALSE)
        g_names <- vapply(gl_raw, function(gl) relabel_native_lvl(gl, ow_rec), character(1L))
        nat_levels <- setNames(cats_by_g, g_names)
      }
    } else if (!is.null(rec_nat$categories) && length(rec_nat$categories)) {
      nat_levels <- .mgmfrm_strict_int_vec(rec_nat$categories, "record$categories")
    } else if (!is.null(rec_nat$category_levels) && length(rec_nat$category_levels)) {
      nat_levels <- parse_native_cat_decl(rec_nat$category_levels, "record$category_levels")
    } else if (!is.null(pr$category_levels) && length(pr$category_levels)) {
      nat_levels <- parse_native_cat_decl(pr$category_levels, "prior_and_reference$category_levels")
    } else if (is.list(pr$payload) && !is.null(pr$payload$category_levels) && length(pr$payload$category_levels)) {
      nat_levels <- parse_native_cat_decl(pr$payload$category_levels, "prior_and_reference$payload$category_levels")
    }

    draws_arr <- posterior::as_draws_array(arr)
    est_df <- .summarize_bayesian_draws(draws_arr, param_labels = param_labels, level = 0.95)
    vcov_mat <- .vcov_from_draws(draws_arr)
    meta_out <- raw[setdiff(names(raw), c("draws", "chain_ids", "iterations"))]
    meta_out$facet_indexing_modes <- lbl_info$modes
    if (!is.null(pop_loc_mode)) meta_out$population_location_mode <- pop_loc_mode
    fc_nat <- if (is.list(rec_nat$fixed_calibration)) {
      rec_nat$fixed_calibration
    } else if (is.list(rec_nat$spec_record) && is.list(rec_nat$spec_record$fixed_calibration)) {
      rec_nat$spec_record$fixed_calibration
    } else {
      NULL
    }
    if (is.list(fc_nat)) {
      eq_nat <- list()
      if (is.list(fc_nat$anchors)) {
        for (anc in fc_nat$anchors) {
          blk_a <- as.character(anc$block)
          lv_a <- relabel_native_lvl(anc$level, blk_a)
          val_a <- as.double(anc$value)
          eq_nat[[length(eq_nat) + 1L]] <- list(
            kind = if (identical(as.character(anc$kind), "hard")) "hard_location" else as.character(anc$kind),
            block = blk_a,
            levels = list(lv_a),
            statistic = "exact",
            weighting = "point_value",
            value = val_a,
            equation = sprintf("%s[%s] = %.12g", blk_a, lv_a, val_a)
          )
        }
      }
      if (is.list(fc_nat$groups)) {
        for (grp in fc_nat$groups) {
          blk_g <- as.character(grp$block)
          lvs_g <- vapply(unlist(grp$levels, use.names = FALSE), function(x) relabel_native_lvl(x, blk_g), character(1L))
          stat_g <- as.character(grp$statistic)
          val_g <- as.double(grp$value)
          eq_nat[[length(eq_nat) + 1L]] <- list(
            kind = "subset_constraint",
            block = blk_g,
            levels = as.list(unname(lvs_g)),
            statistic = stat_g,
            weighting = "unweighted_equal_levels",
            value = val_g,
            equation = sprintf("%s(%s[%s]) = %.12g", stat_g, blk_g, paste(lvs_g, collapse = ", "), val_g)
          )
        }
      }
      meta_out$fixed_calibration <- list(
        uncertainty = if (!is.null(fc_nat$uncertainty)) as.character(fc_nat$uncertainty) else "conditional_on_fixed_calibration",
        subset_weighting_convention = "unweighted_equal_levels",
        constraints = eq_nat
      )
    }
    v_scope <- if (!is.null(expected_sha256) && bundle_verified) {
      "file_and_decision_bundle"
    } else if (bundle_verified) {
      "decision_bundle_embedded"
    } else if (!is.null(expected_sha256)) {
      "file_sha256_only"
    } else if (ieee_verified) {
      "numeric_draws_only"
    } else {
      "unverified"
    }
    meta_out$handoff_verification <- list(
      schema = schema,
      verification_scope = v_scope,
      verification_kind = v_scope,
      ids_and_audit_verified = ids_and_audit_verified,
      file_sha256_verified = !is.null(expected_sha256),
      file_sha256 = file_sha256,
      bundle_sha256_present = bundle_present,
      bundle_sha256_verified = bundle_verified,
      embedded_ieee754_sha256_present = ieee_present,
      embedded_ieee754_sha256_verified = ieee_verified,
      handoff_hash_present = !is.null(raw$handoff_hash),
      handoff_hash_verified_in_r = FALSE
    )
    res <- list(
      draws = draws_arr,
      estimates = est_df,
      vcov = vcov_mat,
      ids = id_dict,
      parameter_labels = param_labels,
      fit_statistics = list(),
      reliability = data.frame(),
      model = mdl,
      method = "nuts",
      steps = eff_steps,
      identification = eff_id,
      category_levels = nat_levels,
      columns = character(0L),
      metadata = meta_out
    )
    class(res) <- "mgmfrm_r_fit"
    return(res)
  }

  stop("Unsupported handoff schema: ", schema)
}
