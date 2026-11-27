library(BayesianMGMFRM)

ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
stopifnot(nrow(ratings) == 72L)

encode <- getFromNamespace("encode_mgmfrm_id", "BayesianMGMFRM")
label_fn <- getFromNamespace(".label_mgmfrm_parameters", "BayesianMGMFRM")

labels <- factor(c("A", "01", "1", "01"), levels = c("unused", "1", "A", "01"))
ids <- encode(labels)
stopifnot(
  identical(ids$labels[ids$index], as.character(labels)),
  identical(ids$labels, c("01", "1", "A")),
  identical(encode(c(10L, 2L))$labels, c(2L, 10L))
)

mapped_lbl <- label_fn(
  c("task[2]", "population[group[2]]", "population_sd[1]",
    "person[1, dim=2]", "loading[2, dim=1]", "consistency[1]",
    "rater_consistency[rater=2]", "item_discrimination[item=1]"),
  list(person = c("P01", "P02"), item = c("I1", "I2"),
       rater = c("R1", "R2"), task = c("T1", "T2"), group = c("G1", "G2"))
)
stopifnot(identical(
  unname(mapped_lbl),
  c("task[T2]", "population[group[G2]]", "population_sd[G1]",
    "person[P01, dim=2]", "loading[I2, dim=1]", "consistency[R1]",
    "rater_consistency[rater=R2]", "item_discrimination[item=I1]")
))

# Input validation guards (without requiring an active Julia session)
n_it_guard <- length(unique(ratings$item))
Q_guard <- matrix(0.0, nrow = n_it_guard, ncol = 2L)
Q_guard[seq_len(ceiling(n_it_guard / 2)), 1L] <- 1.0
Q_guard[seq(ceiling(n_it_guard / 2) + 1L, n_it_guard), 2L] <- 1.0
stopifnot(
  inherits(try(fit_mgmfrm(ratings, c(0L, 2L)), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, facets = c(person = "item")), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", Q = NULL), silent = TRUE), "try-error"),
  # CR5 / P2-2 model-mismatch guards: legacy GMFRM (slope=NULL) requires steps="rater"; MGMFRM rejects unknown steps and between-item softmin
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "gmfrm", steps = "item"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "gmfrm", steps = "global"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", Q = Q_guard, steps = "unknown"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", Q = Q_guard, aggregation = "softmin"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mfrm", rater_slope_scope = "ability_only"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mfrm", logit_scale = 1.7), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mfrm", slope = "rater"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mfrm", correlation = "lkj"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", Q = matrix(1, nrow = n_it_guard, ncol = 1L), correlation = "lkj"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", Q = Q_guard, correlation = "lkj", lkj_eta = 0), silent = TRUE), "try-error")
)

# Backward-compatible minimal S3 fit + offline contrast/handoff checks
draws <- posterior::as_draws_array(array(
  c(-0.4, -0.2, -0.3, -0.1, 0.4, 0.2, 0.3, 0.1),
  dim = c(2L, 2L, 2L),
  dimnames = list(NULL, NULL, c("rater[1]", "rater[2]"))
))
saved <- structure(
  list(
    draws = draws,
    ids = list(rater = c("R1", "R2")),
    parameter_labels = c("rater[1]" = "rater[R1]", "rater[2]" = "rater[R2]"),
    model = "mfrm",
    method = "nuts",
    steps = "item",
    identification = "isometric",
    category_levels = 0:3,
    columns = c(person = "person", item = "item", rater = "rater", score = "score"),
    metadata = list(qualification = list(qualified = TRUE))
  ),
  class = "mgmfrm_r_fit"
)
stopifnot(
  identical(posterior::as_draws_array(saved), draws),
  identical(posterior::as_draws(saved), draws),
  length(coef(saved)) == 2L,
  identical(dim(vcov(saved)), c(2L, 2L)),
  nrow(summary(saved)$estimates) == 2L
)
ctr_b <- contrast_mgmfrm(saved, facet = "rater", a = "R2", b = "R1")
stopifnot(abs(ctr_b$estimate - 0.5) < 1e-12, ctr_b$prob_gt_zero == 1)

# Offline frequentist covariance contrast check (off-diagonal zero-sum covariance)
V_mock <- matrix(c(0.04, -0.02, -0.02, 0.04), nrow = 2L, ncol = 2L,
                 dimnames = list(c("rater[1]", "rater[2]"), c("rater[1]", "rater[2]")))
freq_mock <- structure(
  list(
    draws = NULL,
    estimates = data.frame(
      variable = c("rater[1]", "rater[2]"),
      label = c("rater[R1]", "rater[R2]"),
      estimate = c(-0.3, 0.3),
      se = c(0.2, 0.2),
      lower = c(-0.692, -0.092),
      upper = c(0.092, 0.692),
      stringsAsFactors = FALSE
    ),
    vcov = V_mock,
    ids = list(rater = c("R1", "R2")),
    parameter_labels = c("rater[1]" = "rater[R1]", "rater[2]" = "rater[R2]"),
    fit_statistics = list(),
    reliability = data.frame(),
    model = "mfrm",
    method = "mmle",
    steps = "item",
    identification = "isometric",
    category_levels = 0:3,
    columns = c(person = "person", item = "item", rater = "rater", score = "score"),
    metadata = list(qualification = list(qualified = TRUE))
  ),
  class = "mgmfrm_r_fit"
)
ctr_f <- contrast_mgmfrm(freq_mock, facet = "rater", a = "R2", b = "R1")
stopifnot(
  abs(ctr_f$estimate - 0.6) < 1e-12,
  abs(ctr_f$se - sqrt(0.12)) < 1e-12,
  abs(ctr_f$se_diagonal_only - sqrt(0.08)) < 1e-12,
  ctr_f$se > ctr_f$se_diagonal_only
)

ho_tmp <- tempfile(fileext = ".json")
freq_receipt <- handoff_mgmfrm(freq_mock, ho_tmp, return_receipt = TRUE)
freq_reloaded <- read_handoff_mgmfrm(ho_tmp, expected_sha256 = freq_receipt$sha256)
stopifnot(
  identical(coef(freq_reloaded), coef(freq_mock)),
  max(abs(vcov(freq_reloaded) - vcov(freq_mock))) < 1e-12,
  isTRUE(freq_reloaded$metadata$handoff_verification$file_sha256_verified),
  isTRUE(freq_reloaded$metadata$handoff_verification$payload_sha256_verified)
)

# Exact reproducer of the 86ea2a3 truncated/corrupted JSON bug (8 iter x 2 chain x 2 rater)
# True R2 - R1 mean = 0.85; truncating 16 of 32 draws must fail rather than recycling to 0!
r1_vals <- rep(-0.425, 16L)
r2_vals <- rep(0.425, 16L)
draws8 <- posterior::as_draws_array(array(
  c(r1_vals, r2_vals),
  dim = c(8L, 2L, 2L),
  dimnames = list(NULL, NULL, c("rater[1]", "rater[2]"))
))
saved8 <- structure(
  list(
    draws = draws8,
    ids = list(rater = c("R1", "R2")),
    parameter_labels = c("rater[1]" = "rater[R1]", "rater[2]" = "rater[R2]"),
    model = "mfrm",
    method = "nuts",
    steps = "item",
    identification = "isometric",
    category_levels = 0:3,
    columns = c(person = "person", item = "item", rater = "rater", score = "score"),
    metadata = list(qualification = list(qualified = TRUE))
  ),
  class = "mgmfrm_r_fit"
)
ho8 <- tempfile(fileext = ".json")
rec8 <- handoff_mgmfrm(saved8, ho8, return_receipt = TRUE)
re8 <- read_handoff_mgmfrm(ho8, expected_sha256 = rec8$sha256)
ctr8 <- contrast_mgmfrm(re8, facet = "rater", a = "R2", b = "R1")
stopifnot(abs(ctr8$estimate - 0.85) < 1e-12, isTRUE(re8$metadata$qualification$qualified))

# Preserve full doubles: tiny round-trip changes can break folded-rank ties.
exact_draws <- saved8
exact_draws$draws <- posterior::as_draws_array(array(sin(seq_len(80L)/7), c(20L,2L,2L),
  dimnames=list(NULL,NULL,c("rater[1]","rater[2]"))))
exact_path <- tempfile(fileext=".json")
exact_receipt <- handoff_mgmfrm(exact_draws,exact_path,return_receipt=TRUE)
exact_restored <- read_handoff_mgmfrm(exact_path,expected_sha256=exact_receipt$sha256)
stopifnot(identical(as.array(exact_draws$draws),as.array(exact_restored$draws)))
unlink(exact_path)

# Tamper A1: truncated draws_flat (16 of 32 removed) with payload_sha256 intact -> must fail
raw8 <- jsonlite::fromJSON(ho8, simplifyVector = FALSE)
tamper_trunc <- raw8
tamper_trunc$draws_flat <- raw8$draws_flat[1:16]
p_trunc1 <- tempfile(fileext = ".json")
jsonlite::write_json(tamper_trunc, p_trunc1, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_trunc1), silent = TRUE), "try-error"))

# Tamper A2: truncated draws_flat with payload_sha256 removed (simulating pre-receipt v2 file) -> must still fail!
tamper_trunc_norec <- tamper_trunc[setdiff(names(tamper_trunc), "payload_sha256")]
p_trunc2 <- tempfile(fileext = ".json")
jsonlite::write_json(tamper_trunc_norec, p_trunc2, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_trunc2), silent = TRUE), "try-error"))

# Tamper B: single value modified in place (same length 32) -> caught by payload_sha256 and expected_sha256
tamper_val <- raw8
tamper_val$draws_flat[[1L]] <- 99.0
p_val <- tempfile(fileext = ".json")
jsonlite::write_json(tamper_val, p_val, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(
  inherits(try(read_handoff_mgmfrm(p_val), silent = TRUE), "try-error"),
  inherits(try(read_handoff_mgmfrm(p_val, expected_sha256 = rec8$sha256), silent = TRUE), "try-error")
)

# Tamper C: duplicated (iteration, chain) index (without receipt) -> must fail
tamper_dup <- raw8[setdiff(names(raw8), "payload_sha256")]
tamper_dup$draws_iterations[[2L]] <- tamper_dup$draws_iterations[[1L]]
p_dup <- tempfile(fileext = ".json")
jsonlite::write_json(tamper_dup, p_dup, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_dup), silent = TRUE), "try-error"))

# Tamper D: truncated frequentist vcov_flat (without receipt) -> must fail
raw_f <- jsonlite::fromJSON(ho_tmp, simplifyVector = FALSE)
tamper_vc <- raw_f[setdiff(names(raw_f), "payload_sha256")]
tamper_vc$vcov_flat <- raw_f$vcov_flat[1:2]
p_vc <- tempfile(fileext = ".json")
jsonlite::write_json(tamper_vc, p_vc, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_vc), silent = TRUE), "try-error"))

# Tamper E: native Julia PortableHandoff JSON with duplicate (iteration, chain) -> must fail
native_dup <- list(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  parameter_names = list("rater[1]", "rater[2]"),
  draws_per_chain = 2L,
  n_chains = 1L,
  iterations = list(1L, 1L),
  chain_ids = list(1L, 1L),
  draws = list(list(-0.4, 0.4), list(-0.3, 0.3))
)
p_ndup <- tempfile(fileext = ".json")
jsonlite::write_json(native_dup, p_ndup, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_ndup), silent = TRUE), "try-error"))

# Reopened CR5 Cluster 3 offline guards:
# 3a. GMFRM & MGMFRM reject identification = "reference" before calling Julia
stopifnot(inherits(try(fit_mgmfrm(ratings, 0:3, model = "gmfrm", identification = "reference"), silent = TRUE), "try-error"))
stopifnot(inherits(try(fit_mgmfrm(ratings, 0:3, model = "mgmfrm", identification = "reference",
                                  Q = matrix(1L, nrow = length(unique(ratings$item)), ncol = 1L)), silent = TRUE), "try-error"))

# 3b. GMFRM contrast must NEVER silently zero-fill omitted free rater[1] (0.50 vs 0.80 bug)
gm_full_arr <- array(c(rep(0.30, 6L), rep(0.80, 6L)), dim = c(3L, 2L, 2L),
                     dimnames = list(iteration = NULL, chain = NULL, variable = c("rater[1]", "rater[2]")))
gm_full_fit <- structure(
  list(
    draws = posterior::as_draws_array(gm_full_arr),
    estimates = data.frame(variable = c("rater[1]", "rater[2]"), mean = c(0.30, 0.80), stringsAsFactors = FALSE),
    vcov = matrix(0, 2L, 2L, dimnames = list(c("rater[1]", "rater[2]"), c("rater[1]", "rater[2]"))),
    ids = list(rater = c("R1", "R2")),
    parameter_labels = c("rater[1]" = "rater[R1]", "rater[2]" = "rater[R2]"),
    model = "gmfrm", method = "nuts", steps = "rater", identification = "gmfrm_item_sum_to_zero",
    metadata = list(fixed_parameters = list())
  ),
  class = "mgmfrm_r_fit"
)
stopifnot(abs(contrast_mgmfrm(gm_full_fit, facet = "rater", a = "R2", b = "R1")$estimate - 0.50) < 1e-12)
gm_sub_arr <- array(rep(0.80, 6L), dim = c(3L, 2L, 1L),
                    dimnames = list(iteration = NULL, chain = NULL, variable = "rater[2]"))
gm_sub_fit <- gm_full_fit
gm_sub_fit$draws <- posterior::as_draws_array(gm_sub_arr)
gm_sub_fit$estimates <- gm_full_fit$estimates[2L, , drop = FALSE]
gm_sub_fit$parameter_labels <- gm_full_fit$parameter_labels["rater[2]"]
# Even if identification were erroneously set to "reference" on gmfrm, rater[1] is FREE and must error!
gm_sub_fit_ref <- gm_sub_fit
gm_sub_fit_ref$identification <- "reference"
stopifnot(inherits(try(contrast_mgmfrm(gm_sub_fit, facet = "rater", a = "R2", b = "R1"), silent = TRUE), "try-error"))
stopifnot(inherits(try(contrast_mgmfrm(gm_sub_fit_ref, facet = "rater", a = "R2", b = "R1"), silent = TRUE), "try-error"))

# 3c. Frequentist read_handoff_mgmfrm(variables = "rater[2]") subsets BOTH estimates and vcov; contrast errors instead of NA/0.346
f_sub_ho <- read_handoff_mgmfrm(ho_tmp, variables = "rater[2]")
stopifnot(
  identical(f_sub_ho$estimates$variable, "rater[2]"),
  identical(rownames(vcov(f_sub_ho)), "rater[2]"),
  identical(dim(vcov(f_sub_ho)), c(1L, 1L)),
  inherits(try(contrast_mgmfrm(f_sub_ho, facet = "rater", a = "R2", b = "R1"), silent = TRUE), "try-error")
)

# 3d. Native Julia PortableHandoff GMFRM JSON: source_family, ids, original-label contrast, bundle & draws SHA-256 tamper detection
nat_mat <- matrix(c(0.30, 0.31, 0.29, 0.30, 0.80, 0.81, 0.79, 0.80), nrow = 4L, ncol = 2L)
nat_ieee <- BayesianMGMFRM:::.mgmfrm_draws_ieee754_sha256(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "gmfrm",
  scale = "model",
  parameter_names = c("rater[R1]", "rater[R2]"),
  chain_ids = c(1L, 1L, 2L, 2L),
  iterations = c(1L, 2L, 1L, 2L),
  draw_mat = nat_mat,
  fixed_parameters = list(),
  qualified = TRUE
)
nat_pr <- list(threshold_owner = "rater", identification = "gmfrm_item_sum_to_zero")
nat_ids <- list(rater = list("R1", "R2"))
nat_ma <- list(n_input_rows = 10L, n_retained_rows = 9L, n_dropped_rows = 1L,
               dropped_rows = list(5L), dropped_by_column = list(score = 1L))
nat_bundle <- BayesianMGMFRM:::.mgmfrm_handoff_bundle_sha256(
  draws_ieee754_sha256 = nat_ieee,
  ids = nat_ids,
  prior_and_reference = nat_pr,
  missing_audit = nat_ma
)
nat_gm_obj <- list(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "gmfrm",
  scale = "model",
  n_chains = 2L,
  draws_per_chain = 2L,
  total_draws = 4L,
  n_parameters = 2L,
  chain_ids = list(1L, 1L, 2L, 2L),
  iterations = list(1L, 2L, 1L, 2L),
  parameter_names = list("rater[R1]", "rater[R2]"),
  parameter_blocks = list("rater", "rater"),
  fixed_parameters = list(),
  draws = lapply(seq_len(4L), function(i) as.list(nat_mat[i, ])),
  qualification = list(qualified = TRUE),
  prior_and_reference = nat_pr,
  ids = nat_ids,
  missing_audit = nat_ma,
  handoff_hash = paste(rep("a", 64L), collapse = ""),
  draws_ieee754_sha256 = nat_ieee,
  handoff_bundle_sha256 = nat_bundle
)
p_nat_gm <- tempfile(fileext = ".json")
jsonlite::write_json(nat_gm_obj, p_nat_gm, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
nat_gm_reloaded <- read_handoff_mgmfrm(p_nat_gm)
stopifnot(
  identical(nat_gm_reloaded$model, "gmfrm"),
  identical(nat_gm_reloaded$steps, "rater"),
  identical(nat_gm_reloaded$identification, "gmfrm_item_sum_to_zero"),
  identical(nat_gm_reloaded$ids$rater, c("R1", "R2")),
  isTRUE(nat_gm_reloaded$metadata$handoff_verification$bundle_sha256_verified),
  isTRUE(nat_gm_reloaded$metadata$handoff_verification$ids_and_audit_verified),
  identical(nat_gm_reloaded$metadata$handoff_verification$verification_scope, "decision_bundle_embedded"),
  abs(contrast_mgmfrm(nat_gm_reloaded, facet = "rater", a = "R2", b = "R1")$estimate - 0.50) < 1e-12
)

# 3d-bis. Native Julia GMFRM handoff with explicit 1:25 category_levels restores exact 1:25 values/order and rejects category tampering
nat_pr25 <- list(threshold_owner = "rater", identification = "gmfrm_isometric_geometric_mean_one",
                 category_levels = as.list(1L:25L), n_categories = 25L)
nat_bundle25 <- BayesianMGMFRM:::.mgmfrm_handoff_bundle_sha256(
  draws_ieee754_sha256 = nat_ieee,
  ids = nat_ids,
  prior_and_reference = nat_pr25,
  missing_audit = nat_ma
)
nat_gm25_obj <- nat_gm_obj
nat_gm25_obj$prior_and_reference <- nat_pr25
nat_gm25_obj$handoff_bundle_sha256 <- nat_bundle25
p_nat_gm25 <- tempfile(fileext = ".json")
jsonlite::write_json(nat_gm25_obj, p_nat_gm25, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
nat_gm25_reloaded <- read_handoff_mgmfrm(p_nat_gm25)
stopifnot(
  identical(nat_gm25_reloaded$category_levels, 1L:25L),
  isTRUE(nat_gm25_reloaded$metadata$handoff_verification$bundle_sha256_verified)
)
# Tamper category_levels from 1:25 to 0:24 or reverse 25:1 while keeping draws untouched -> bundle_sha256 MUST fail!
nat_gm25_shift <- nat_gm25_obj
nat_gm25_shift$prior_and_reference$category_levels <- as.list(0L:24L)
p_nat_gm25_shift <- tempfile(fileext = ".json")
jsonlite::write_json(nat_gm25_shift, p_nat_gm25_shift, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_gm25_shift), silent = TRUE), "try-error"))
nat_gm25_rev <- nat_gm25_obj
nat_gm25_rev$prior_and_reference$category_levels <- as.list(25L:1L)
p_nat_gm25_rev <- tempfile(fileext = ".json")
jsonlite::write_json(nat_gm25_rev, p_nat_gm25_rev, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_gm25_rev), silent = TRUE), "try-error"))
# Tamper ONE finite draw value WITHOUT expected_sha256 -> MUST FAIL!
nat_gm_tampered <- nat_gm_obj
nat_gm_tampered$draws[[1L]][[2L]] <- 9.99
p_nat_tamper <- tempfile(fileext = ".json")
jsonlite::write_json(nat_gm_tampered, p_nat_tamper, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_tamper), silent = TRUE), "try-error"))

# Tamper ONLY rater IDs (swap R1/R2) or missing_audit while keeping draws bit-identical -> bundle hash MUST FAIL!
nat_swap_ids <- nat_gm_obj
nat_swap_ids$ids <- list(rater = list("R2", "R1"))
p_nat_swap <- tempfile(fileext = ".json")
jsonlite::write_json(nat_swap_ids, p_nat_swap, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_swap), silent = TRUE), "try-error"))

nat_bad_ma <- nat_gm_obj
nat_bad_ma$missing_audit$n_dropped_rows <- 2L
p_nat_ma <- tempfile(fileext = ".json")
jsonlite::write_json(nat_bad_ma, p_nat_ma, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_ma), silent = TRUE), "try-error"))

# Draw-only native JSON (has draws_ieee754_sha256 but NO handoff_bundle_sha256 and NO expected_sha256) -> warns & marks numeric_draws_only!
nat_draw_only <- nat_gm_obj[setdiff(names(nat_gm_obj), "handoff_bundle_sha256")]
p_nat_do <- tempfile(fileext = ".json")
jsonlite::write_json(nat_draw_only, p_nat_do, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
do_warned <- FALSE
nat_do_reloaded <- withCallingHandlers(
  read_handoff_mgmfrm(p_nat_do),
  warning = function(w) { do_warned <<- TRUE; invokeRestart("muffleWarning") }
)
stopifnot(
  do_warned,
  identical(nat_do_reloaded$metadata$handoff_verification$verification_scope, "numeric_draws_only"),
  isTRUE(nat_do_reloaded$metadata$handoff_verification$embedded_ieee754_sha256_verified),
  isFALSE(nat_do_reloaded$metadata$handoff_verification$ids_and_audit_verified)
)

# 3e. Direct Julia-origin MRCML JSON with Julia-quoted string IDs (rater["Alice"], rater["Bea"]) -> Bea - Alice works & omitted free stops!
nat_q_ieee <- BayesianMGMFRM:::.mgmfrm_draws_ieee754_sha256(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "additive_facets",
  scale = "model",
  parameter_names = c("rater[\"Alice\"]", "rater[\"Bea\"]"),
  chain_ids = c(1L, 1L, 2L, 2L),
  iterations = c(1L, 2L, 1L, 2L),
  draw_mat = nat_mat,
  fixed_parameters = list(),
  qualified = TRUE
)
nat_q_ids <- list(rater = list("Alice", "Bea"))
nat_q_pr <- list(family = "mrcml_linear_logit_1d", step_owner = "global", location_mode = "zero_mean_population")
nat_q_bundle <- BayesianMGMFRM:::.mgmfrm_handoff_bundle_sha256(nat_q_ieee, nat_q_ids, nat_q_pr, NULL)
nat_q_obj <- list(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "additive_facets",
  scale = "model",
  n_chains = 2L,
  draws_per_chain = 2L,
  total_draws = 4L,
  n_parameters = 2L,
  chain_ids = list(1L, 1L, 2L, 2L),
  iterations = list(1L, 2L, 1L, 2L),
  parameter_names = list("rater[\"Alice\"]", "rater[\"Bea\"]"),
  parameter_blocks = list("rater", "rater"),
  fixed_parameters = list(),
  draws = lapply(seq_len(4L), function(i) as.list(nat_mat[i, ])),
  qualification = list(qualified = TRUE),
  prior_and_reference = nat_q_pr,
  ids = nat_q_ids,
  handoff_hash = paste(rep("b", 64L), collapse = ""),
  draws_ieee754_sha256 = nat_q_ieee,
  handoff_bundle_sha256 = nat_q_bundle
)
p_nat_q <- tempfile(fileext = ".json")
jsonlite::write_json(nat_q_obj, p_nat_q, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
nat_q_reloaded <- read_handoff_mgmfrm(p_nat_q)
stopifnot(
  identical(nat_q_reloaded$ids$rater, c("Alice", "Bea")),
  abs(contrast_mgmfrm(nat_q_reloaded, facet = "rater", a = "Bea", b = "Alice")$estimate - 0.50) < 1e-12,
  abs(contrast_mgmfrm(nat_q_reloaded, facet = "rater", a = "Alice", b = "Bea")$estimate + 0.50) < 1e-12
)
nat_q_sub <- read_handoff_mgmfrm(p_nat_q, variables = "rater[\"Bea\"]")
stopifnot(inherits(try(contrast_mgmfrm(nat_q_sub, facet = "rater", a = "Bea", b = "Alice"), silent = TRUE), "try-error"))

# 3e2. Criterion-role ScaleIdentifiedMGMFRM handoffs (both R-origin positional and Julia-origin literal) + fixed slope print
crit_mat <- cbind(nat_mat, -nat_mat)
crit_ids <- list(person = list("P1", "P2"), criterion = list("CritA", "CritB"),
                 rater = list("R1", "R2"), dimension = list("D1"))
crit_pr <- list(family = "mgmfrm_adjacent_logit_scale_identified", step_owner = "criterion",
                threshold_owner = "criterion", scale_identification = "geometric_mean_one")
crit_ps_r <- list(family = "scale_identified_mgmfrm", ability_sd = list(label = "HalfNormal(1.0)"),
                  item_slopes = "fixed_one", rater_consistency = "estimated_positive",
                  log_loading_sd = 0.35, log_consistency_sd = 0.35, step_owner = "criterion")
crit_ps_i <- list(family = "scale_identified_mgmfrm", ability_sd = list(label = "HalfNormal(1.0)"),
                  item_slopes = "estimated_positive", rater_consistency = "fixed_one",
                  log_loading_sd = 0.35, log_consistency_sd = 0.35, step_owner = "criterion")
for (p_case in list(
  list(pnames = c("item[1]", "item[2]", "step[1, 1]", "step[2, 1]"), ps = crit_ps_r, exp_txt = "item slopes = fixed\\(1\\)"),
  list(pnames = c("item[CritA]", "item[CritB]", "step[CritA, 1]", "step[CritB, 1]"), ps = crit_ps_i, exp_txt = "rater consistency = fixed\\(1\\)")
)) {
  c_ieee <- BayesianMGMFRM:::.mgmfrm_draws_ieee754_sha256(
    schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
    source_family = "scale_identified_mgmfrm",
    scale = "model",
    parameter_names = p_case$pnames,
    chain_ids = c(1L, 1L, 2L, 2L),
    iterations = c(1L, 2L, 1L, 2L),
    draw_mat = crit_mat,
    fixed_parameters = list(),
    qualified = TRUE
  )
  c_bundle <- BayesianMGMFRM:::.mgmfrm_handoff_bundle_sha256(c_ieee, crit_ids, crit_pr, NULL)
  c_obj <- list(
    schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
    source_family = "scale_identified_mgmfrm",
    scale = "model",
    n_chains = 2L,
    draws_per_chain = 2L,
    total_draws = 4L,
    n_parameters = 4L,
    chain_ids = list(1L, 1L, 2L, 2L),
    iterations = list(1L, 2L, 1L, 2L),
    parameter_names = as.list(p_case$pnames),
    parameter_blocks = list("item", "item", "step", "step"),
    fixed_parameters = list(),
    draws = lapply(seq_len(4L), function(i) as.list(crit_mat[i, ])),
    qualification = list(qualified = TRUE),
    prior_and_reference = crit_pr,
    prior_summary = p_case$ps,
    ids = crit_ids,
    handoff_hash = paste(rep("d", 64L), collapse = ""),
    draws_ieee754_sha256 = c_ieee,
    handoff_bundle_sha256 = c_bundle
  )
  p_crit_ho <- tempfile(fileext = ".json")
  jsonlite::write_json(c_obj, p_crit_ho, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  crit_re <- read_handoff_mgmfrm(p_crit_ho)
  pr_lines <- paste(capture.output(print(crit_re)), collapse = "\n")
  stopifnot(
    isTRUE(crit_re$metadata$handoff_verification$bundle_sha256_verified),
    identical(crit_re$ids$criterion, c("CritA", "CritB")),
    all(c("criterion[CritA]", "criterion[CritB]", "step[CritA, 1]", "step[CritB, 1]") %in% unname(crit_re$parameter_labels)),
    abs(contrast_mgmfrm(crit_re, facet = "criterion", a = "CritB", b = "CritA")$estimate - 0.50) < 1e-12,
    grepl(p_case$exp_txt, pr_lines)
  )
}

# 3f. Relabeling helper restores ALL isolated facet levels and SCC groups (not just the first element!)
dv_mock <- list(
  connectedness = list(
    isolated_facet_levels = list(list(facet = "rater", levels = list(3L, 4L)))
  ),
  one_sided_separation = list(
    by_facet = list(list(
      facet = "rater",
      scc_level_groups = list(list(1L, 2L), list(3L, 4L)),
      source_levels = list(1L, 2L),
      sink_levels = list(3L, 4L)
    ))
  )
)
dv_rel <- BayesianMGMFRM:::.relabel_design_validation(dv_mock, list(rater = c("R1", "R2", "R3", "R4")))
stopifnot(
  identical(unlist(dv_rel$connectedness$isolated_facet_levels[[1L]]$levels), c("R3", "R4")),
  identical(unlist(dv_rel$one_sided_separation$by_facet[[1L]]$source_levels), c("R1", "R2")),
  identical(unlist(dv_rel$one_sided_separation$by_facet[[1L]]$sink_levels), c("R3", "R4")),
  identical(unlist(dv_rel$one_sided_separation$by_facet[[1L]]$scc_level_groups[[2L]]), c("R3", "R4"))
)

# 3g. Pre-CR5 native JSON lacking both hashes without expected_sha256 warns & marks unverified
nat_legacy <- nat_gm_obj[setdiff(names(nat_gm_obj), c("draws_ieee754_sha256", "handoff_bundle_sha256"))]
p_nat_leg <- tempfile(fileext = ".json")
jsonlite::write_json(nat_legacy, p_nat_leg, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
leg_warned <- FALSE
nat_leg_reloaded <- withCallingHandlers(
  read_handoff_mgmfrm(p_nat_leg),
  warning = function(w) { leg_warned <<- TRUE; invokeRestart("muffleWarning") }
)
stopifnot(
  leg_warned,
  identical(nat_leg_reloaded$metadata$handoff_verification$verification_scope, "unverified"),
  isFALSE(nat_leg_reloaded$metadata$handoff_verification$embedded_ieee754_sha256_verified),
  isFALSE(nat_leg_reloaded$metadata$handoff_verification$ids_and_audit_verified),
  isFALSE(nat_leg_reloaded$metadata$handoff_verification$handoff_hash_verified_in_r)
)

# 3h. Offline mixed-category list validation, fixed_calibration guards, and mrcml_design_matrix / fixed-anchor handoff reload
mix_guard_cats <- list(I1 = 0:3, I2 = 0:3, I3 = 0:2, I4 = 0:2)
stopifnot(
  inherits(try(fit_mgmfrm(ratings, mix_guard_cats, steps = "global", method = "mmle"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, mix_guard_cats, identification = "reference", method = "nuts"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, mix_guard_cats, model = "gmfrm", steps = "rater", method = "nuts"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, list(I1 = c(0L, 2L), I2 = 0:3, I3 = 0:2, I4 = 0:2), steps = "item", method = "mmle"), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, identification = "reference",
                          fixed_calibration = list(facets = list(item = c(I1 = -0.5)))), silent = TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, fixed_calibration = list(unknown = 1)), silent = TRUE), "try-error")
)

# Native PortableHandoff custom TAM design (`mrcml_design_matrix`, fixed `item["I1"] = -0.5`) & mixed supports reconstruction
tam_mat <- matrix(c(-0.5, -0.5, -0.5, -0.5, 0.25, 0.35, 0.15, 0.25), nrow = 4L, ncol = 2L)
tam_fp <- list(list(block = "item", name = "item[\"I1\"]", value = -0.5))
tam_ieee <- BayesianMGMFRM:::.mgmfrm_draws_ieee754_sha256(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "additive_facets",
  scale = "model",
  parameter_names = c("item[\"I1\"]", "item[\"I2\"]"),
  chain_ids = c(1L, 1L, 2L, 2L),
  iterations = c(1L, 2L, 1L, 2L),
  draw_mat = tam_mat,
  fixed_parameters = tam_fp,
  qualified = TRUE
)
tam_ids <- list(item = list("I1", "I2"))
tam_pr <- list(
  family = "mrcml_linear_logit_1d",
  threshold_owner = "item",
  step_owner = "item",
  facet_identification = "mrcml_design_matrix",
  identification = "mrcml_design_matrix",
  population_location_mode = "zero_mean_population",
  record = list(
    categories = list(0L, 1L, 2L, 3L),
    supports = list(list(1L, 2L, 3L), list(1L, 2L, 3L, 4L)),
    group_levels = list("I1", "I2"),
    owner = "item"
  )
)
tam_bundle <- BayesianMGMFRM:::.mgmfrm_handoff_bundle_sha256(tam_ieee, tam_ids, tam_pr, NULL)
tam_obj <- list(
  schema = "bayesianmgmfrm.portable_joint_draws_handoff.v1",
  source_family = "additive_facets",
  scale = "model",
  n_chains = 2L,
  draws_per_chain = 2L,
  total_draws = 4L,
  n_parameters = 2L,
  chain_ids = list(1L, 1L, 2L, 2L),
  iterations = list(1L, 2L, 1L, 2L),
  parameter_names = list("item[\"I1\"]", "item[\"I2\"]"),
  parameter_blocks = list("item", "item"),
  fixed_parameters = tam_fp,
  draws = lapply(seq_len(4L), function(i) as.list(tam_mat[i, ])),
  qualification = list(qualified = TRUE),
  prior_and_reference = tam_pr,
  ids = tam_ids,
  handoff_hash = paste(rep("c", 64L), collapse = ""),
  draws_ieee754_sha256 = tam_ieee,
  handoff_bundle_sha256 = tam_bundle
)
p_tam_ho <- tempfile(fileext = ".json")
jsonlite::write_json(tam_obj, p_tam_ho, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
tam_re <- read_handoff_mgmfrm(p_tam_ho, variables = "item[\"I2\"]")
ctr_tam_re <- contrast_mgmfrm(tam_re, facet = "item", a = "I2", b = "I1")
stopifnot(
  identical(tam_re$identification, "mrcml_design_matrix"),
  is.list(tam_re$category_levels),
  identical(tam_re$category_levels$I1, 0:2),
  identical(tam_re$category_levels$I2, 0:3),
  abs(ctr_tam_re$estimate - 0.75) < 1e-12
)

source_dir <- Sys.getenv("BAYESIANMGMFRM_R_CHECK_SOURCE")
if (nzchar(source_dir)) {
  setup_mgmfrm(project = tempfile("julia-project-"), source_dir = source_dir)

  # 1. Default isometric 1D MFRM + native PortableHandoff JSON export
  native_ho <- tempfile("native-handoff-", fileext = ".json")
  fit <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, chains = 2L, warmup = 35L, draws = 40L, seed = 92L,
    variables = c("rater[1]", "rater[2]", "rater[3]", "population_mean", "residual_sd[person]"),
    handoff_path = native_ho
  ))
  x <- posterior::as_draws_array(fit)
  stopifnot(
    identical(dim(x), c(40L, 2L, 5L)),
    identical(fit$identification, "isometric"),
    identical(unname(fit$parameter_labels[1:3]), c("rater[R1]", "rater[R2]", "rater[R3]")),
    max(abs(x[, , 1L] + x[, , 2L] + x[, , 3L])) < 1e-12,
    all(x[, , 5L] > 0),
    all(is.finite(x)),
    is.logical(fit$metadata$qualification$qualified),
    file.exists(native_ho)
  )
  fs_rater <- diagnostics_mgmfrm(fit, "fit_statistics", facet = "rater")
  rel_tbl <- diagnostics_mgmfrm(fit, "reliability")
  stopifnot(
    is.data.frame(fs_rater),
    identical(fs_rater$level, c("R1", "R2", "R3")),
    all(c("infit_mnsq_mean", "plugin_infit_mnsq", "ppp_infit_mcse") %in% names(fs_rater)),
    is.data.frame(rel_tbl),
    "population_marginal_reliability" %in% names(rel_tbl),
    all(is.na(rel_tbl$population_marginal_reliability)),
    all(is.na(rel_tbl$reliability_lower)),
    all(rel_tbl$interval_status == "not_defined_for_posterior_functional"),
    all(rel_tbl$population_status == "requires_population_and_design_marginalization")
  )
  ctr_live <- contrast_mgmfrm(fit, facet = "rater", a = "R2", b = "R1")
  ctr_w <- contrast_mgmfrm(fit, facet = "rater", weights = c(R1 = -0.5, R2 = 1.0, R3 = -0.5))
  stopifnot(nrow(ctr_live) == 1L, is.finite(ctr_live$estimate), nrow(ctr_w) == 1L)

  # 2. Legacy reference-anchored 1D MFRM backward compatibility
  fit_ref <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, chains = 2L, warmup = 35L, draws = 40L, seed = 92L,
    variables = c("rater[2]", "rater[1]"), identification = "reference"
  ))
  x_ref <- posterior::as_draws_array(fit_ref)
  stopifnot(
    identical(dim(x_ref), c(40L, 2L, 2L)),
    identical(fit_ref$identification, "reference_first"),
    all(x_ref[, , 2L] == 0),
    all(is.finite(x_ref))
  )

  # 3. 4-facet Rating Scale Model (steps = "global")
  ratings4 <- ratings
  ratings4$domain <- ifelse((seq_len(nrow(ratings4)) %% 5L) < 2L, "D1", "D2")
  fit_4f <- suppressWarnings(fit_mgmfrm(
    ratings4, 0:3, chains = 2L, warmup = 25L, draws = 25L, seed = 93L,
    facets = c(item = "item", rater = "rater", domain = "domain"),
    steps = "global"
  ))
  stopifnot(
    "domain" %in% names(fit_4f$ids),
    any(grepl("^domain\\[", names(coef(fit_4f)))),
    any(grepl("^steps\\[", unname(fit_4f$parameter_labels)))
  )

  # 4. Multi-group 1D MFRM (group = "cohort")
  p_levels <- sort(unique(ratings$person))
  ratings_grp <- ratings
  ratings_grp$cohort <- ifelse(match(ratings$person, p_levels) <= length(p_levels) / 2, "G1", "G2")
  fit_grp <- suppressWarnings(fit_mgmfrm(
    ratings_grp, 0:3, chains = 2L, warmup = 25L, draws = 25L, seed = 94L,
    group = "cohort"
  ))
  ctr_grp <- contrast_mgmfrm(fit_grp, facet = "group", a = "G2", b = "G1")
  stopifnot("population[group[G2]]" %in% unname(fit_grp$parameter_labels), is.finite(ctr_grp$estimate))

  # 4b. Multi-group MMLE + HalfNormal equal_sd + rater x group DFF (doubly_centered & split_rater)
  dff_rows <- list()
  p_eff <- c(-1.4, -0.9, -0.4, 0.3, 0.9, 1.5, -1.1, -0.5, 0.0, 0.6, 1.2, 1.8)
  for (p in 1:12) {
    grp_lbl <- if (p <= 6L) "G1" else "G2"
    r_pair <- c(((p - 1L) %% 3L) + 1L, (p %% 3L) + 1L)
    for (ri in r_pair) {
      for (ii in 1:3) {
        dff_shift <- if (ri == 1L && grp_lbl == "G2") 1.0 else 0.0
        raw_lat <- p_eff[[p]] - 0.4 * (ii - 2.0) - 0.3 * (ri - 2.0) - dff_shift + 0.35 * (((p * 3L + ri + ii) %% 5L) - 2.0)
        sc <- max(0L, min(3L, as.integer(round(1.5 + raw_lat))))
        dff_rows[[length(dff_rows) + 1L]] <- data.frame(
          person = sprintf("DP%02d", p), item = paste0("I", ii), rater = paste0("R", ri),
          score = sc, cohort = grp_lbl, stringsAsFactors = FALSE
        )
      }
    }
  }
  dff_df <- do.call(rbind, dff_rows)
  fit_grp_mmle <- suppressWarnings(fit_mgmfrm(
    dff_df, 0:3, steps = "global", method = "mmle",
    group = "cohort", group_equal_sd = TRUE, dff = "rater", dff_mode = "doubly_centered"
  ))
  ctr_grp_mmle <- contrast_mgmfrm(fit_grp_mmle, facet = "group", a = "G2", b = "G1")
  fit_grp_split_mmle <- suppressWarnings(fit_mgmfrm(
    dff_df, 0:3, steps = "global", method = "mmle",
    group = "cohort", group_equal_sd = TRUE, dff = "rater", dff_mode = "split_rater", dff_focal = "R1"
  ))
  fit_grp_hn <- suppressWarnings(fit_mgmfrm(
    dff_df, 0:3, steps = "global", chains = 2L, warmup = 25L, draws = 25L, seed = 95L,
    group = "cohort", group_equal_sd = TRUE, group_sd_prior = "half_normal",
    dff = "rater", dff_mode = "split_rater", dff_focal = "R1"
  ))
  stopifnot(
    is.finite(ctr_grp_mmle$estimate),
    is.finite(ctr_grp_mmle$se) && ctr_grp_mmle$se > 0,
    any(grepl("^interaction\\[rater,group\\]", unname(fit_grp_mmle$parameter_labels))),
    "focal_dff[rater=R1,group=G2]" %in% unname(fit_grp_split_mmle$parameter_labels),
    "focal_dff[rater=R1,group=G2]" %in% unname(fit_grp_hn$parameter_labels),
    "population_sd" %in% names(coef(fit_grp_hn))
  )

  # 5. Frequentist MMLE & JMLE with full constrained-subspace covariance
  # Unpenalized item-PCM rejects unobserved item endpoint categories, whereas global RSM is identified:
  stopifnot(inherits(try(fit_mgmfrm(ratings, 0:3, steps = "item", method = "mmle"), silent = TRUE), "try-error"))
  fit_mmle <- suppressWarnings(fit_mgmfrm(ratings, 0:3, steps = "global", method = "mmle"))
  fit_jmle <- suppressWarnings(fit_mgmfrm(ratings, 0:3, steps = "global", method = "jmle"))
  ctr_mmle <- contrast_mgmfrm(fit_mmle, facet = "rater", a = "R2", b = "R1")
  ctr_jmle <- contrast_mgmfrm(fit_jmle, facet = "rater", a = "R2", b = "R1")
  stopifnot(
    is.null(fit_mmle$draws),
    nrow(vcov(fit_mmle)) > 0L,
    ctr_mmle$se > ctr_mmle$se_diagonal_only,
    ctr_jmle$se > ctr_jmle$se_diagonal_only,
    nrow(diagnostics_mgmfrm(fit_mmle, "reliability")) == 3L,
    nrow(diagnostics_mgmfrm(fit_grp_mmle, "reliability")) == 3L,
    all(is.finite(diagnostics_mgmfrm(fit_grp_mmle, "reliability")$strata)),
    all(c("population_separation", "real_separation", "facets_conditional_separation") %in%
        names(diagnostics_mgmfrm(fit_grp_mmle, "reliability"))),
    identical(diagnostics_mgmfrm(fit_grp_mmle, "fit_statistics", facet = "rater")$level, c("R1", "R2", "R3")),
    all(is.finite(diagnostics_mgmfrm(fit_grp_mmle, "fit_statistics", facet = "rater")$infit_zstd)),
    identical(diagnostics_mgmfrm(fit_grp_mmle, "fit_statistics", facet = "person")$level[[1L]], "DP01")
  )

  # 5b. Reopened CR5 Cluster 1 live Julia<->R connectedness & qualification parity
  # 5-person x 2-rater binary panel with 1 all-max person removed -> 1 residual component & qualified JMLE!
  bin5_df <- data.frame(
    person = c("P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5"),
    rater  = c("R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"),
    score  = c(1L, 1L, 1L, 0L, 1L, 0L, 0L, 1L, 0L, 1L),
    stringsAsFactors = FALSE
  )
  fit_bin5_jmle <- fit_mgmfrm(bin5_df, 0:1, facets = c(rater = "rater"), steps = "global", method = "jmle")
  q_bin5 <- diagnostics_mgmfrm(fit_bin5_jmle, "qualification")
  v_bin5 <- diagnostics_mgmfrm(fit_bin5_jmle, "validation")
  stopifnot(
    isTRUE(q_bin5$qualified),
    isTRUE(q_bin5$hessian_gate_passed),
    isTRUE(q_bin5$gradient_gate_passed),
    isTRUE(q_bin5$boundary_gate_passed),
    identical(as.integer(v_bin5$connectedness$n_score_conditioned_subsets), 1L),
    isTRUE(v_bin5$connectedness$score_conditioned_connected)
  )

  # Fischer (1981) one-sided separation (R1/R2 + R3/R4 joined only by 1/0 bridge) -> MUST refuse unadjusted JMLE!
  sep_df <- data.frame(
    person = c("P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5"),
    rater  = c("R1", "R2", "R1", "R2", "R3", "R4", "R3", "R4", "R2", "R3"),
    score  = c(1L, 0L, 0L, 1L, 1L, 0L, 0L, 1L, 1L, 0L),
    stringsAsFactors = FALSE
  )
  stopifnot(inherits(try(
    fit_mgmfrm(sep_df, 0:1, facets = c(rater = "rater"), steps = "global", method = "jmle"),
    silent = TRUE
  ), "try-error"))

  # 5c. Numeric original rater IDs 2 and 7 (positional collision regression: a=7, b=2 MUST NOT return 0, 0, [0, 0]!)
  num_id_df <- data.frame(
    person = c("P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4", "P5", "P5"),
    rater  = c(2L, 7L, 2L, 7L, 2L, 7L, 2L, 7L, 2L, 7L),
    score  = c(1L, 0L, 1L, 0L, 1L, 0L, 0L, 1L, 0L, 1L),
    stringsAsFactors = FALSE
  )
  fit_num_jmle <- fit_mgmfrm(num_id_df, 0:1, facets = c(rater = "rater"), steps = "global", method = "jmle")
  ctr_num_id  <- contrast_mgmfrm(fit_num_jmle, facet = "rater", a = 7, b = 2)
  ctr_num_raw <- contrast_mgmfrm(fit_num_jmle, facet = "rater", a = "rater[2]", b = "rater[1]")
  ctr_num_rev <- contrast_mgmfrm(fit_num_jmle, facet = "rater", a = 2, b = 7)
  stopifnot(
    isTRUE(diagnostics_mgmfrm(fit_num_jmle, "qualification")$qualified),
    abs(ctr_num_id$estimate - ctr_num_raw$estimate) < 1e-12,
    abs(ctr_num_id$se - ctr_num_raw$se) < 1e-12,
    abs(ctr_num_id$estimate) > 0.5,
    abs(ctr_num_rev$estimate + ctr_num_id$estimate) < 1e-12
  )
  # Round-trip numeric-ID frequentist fit via R handoff JSON -> identical 7 - 2 contrast; omitted rater[1] stops!
  num_ho <- tempfile("num-id-ho-", fileext = ".json")
  num_rec <- handoff_mgmfrm(fit_num_jmle, num_ho, return_receipt = TRUE)
  fit_num_re <- read_handoff_mgmfrm(num_ho, expected_sha256 = num_rec$sha256)
  ctr_num_re <- contrast_mgmfrm(fit_num_re, facet = "rater", a = 7, b = 2)
  stopifnot(
    abs(ctr_num_re$estimate - ctr_num_id$estimate) < 1e-12,
    abs(ctr_num_re$lower - ctr_num_id$lower) < 1e-12,
    abs(ctr_num_re$upper - ctr_num_id$upper) < 1e-12
  )
  fit_num_sub <- read_handoff_mgmfrm(num_ho, variables = "rater[2]")
  stopifnot(inherits(try(contrast_mgmfrm(fit_num_sub, facet = "rater", a = 7, b = 2), silent = TRUE), "try-error"))

  # 6. Experimental GMFRM & Scale-Identified 2D MGMFRM
  gm_native_ho <- tempfile("gm-native-handoff-", fileext = ".json")
  fit_gm <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, model = "gmfrm", chains = 2L, warmup = 20L, draws = 20L, seed = 95L,
    handoff_path = gm_native_ho
  ))
  ctr_gm_live <- contrast_mgmfrm(fit_gm, facet = "rater", a = "R2", b = "R1")
  stopifnot(
    any(grepl("^rater_consistency\\[", names(coef(fit_gm)))),
    identical(fit_gm$steps, "rater"),
    identical(fit_gm$identification, "gmfrm_item_sum_to_zero"),
    identical(fit_gm$metadata$effective_model$threshold_owner, "rater"),
    is.list(diagnostics_mgmfrm(fit_gm, "validation")$connectedness),
    nzchar(fit_gm$metadata$package_version),
    file.exists(gm_native_ho)
  )

  n_it <- length(unique(ratings$item))
  Q_mat <- matrix(0.0, nrow = n_it, ncol = 2L)
  Q_mat[seq_len(ceiling(n_it / 2)), 1L] <- 1.0
  Q_mat[seq(ceiling(n_it / 2) + 1L, n_it), 2L] <- 1.0
  fit_mg <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, model = "mgmfrm", Q = Q_mat,
    scale_identification = "geometric_mean_one",
    chains = 2L, warmup = 20L, draws = 20L, seed = 96L
  ))
  x_mg <- posterior::as_draws_array(fit_mg)
  d1_cols <- grep("^loading\\[[0-9]+, dim=1\\]$", dimnames(x_mg)[[3L]])
  active_d1 <- d1_cols[which(Q_mat[, 1L] > 0)]
  geom_means <- exp(apply(log(x_mg[, , active_d1, drop = FALSE]), c(1L, 2L), mean))
  stopifnot(
    max(abs(geom_means - 1.0)) < 1e-10,
    nrow(diagnostics_mgmfrm(fit_mg, "reliability")) == 2L,
    identical(fit_mg$steps, "item")
  )

  # P2-2: 1D residual_correlation (Yen Q3 / Q3*), scale-identified GMFRM (slope + steps = "item"), and LKJ-correlated 2D MGMFRM
  rc_1d <- diagnostics_mgmfrm(fit, "residual_correlation")
  stopifnot(
    is.list(rc_1d),
    is.data.frame(rc_1d$pairs),
    nrow(rc_1d$pairs) >= 1L,
    all(rc_1d$pairs$level_1 %in% unique(ratings$item)),
    all(rc_1d$pairs$level_2 %in% unique(ratings$item)),
    is.numeric(rc_1d$summary$ppp_mean_q3)
  )
  fit_gm_si <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, model = "gmfrm", slope = "rater", steps = "item",
    chains = 2L, warmup = 15L, draws = 15L, seed = 98L
  ))
  ratings_crit <- ratings
  names(ratings_crit)[names(ratings_crit) == "item"] <- "criterion"
  gm_crit_ho <- tempfile("gm-crit-handoff-", fileext = ".json")
  fit_gm_crit <- suppressWarnings(fit_mgmfrm(
    ratings_crit, 0:3, facets = c(criterion = "criterion", rater = "rater"),
    model = "gmfrm", slope = "rater", steps = "criterion",
    chains = 2L, warmup = 12L, draws = 12L, seed = 101L, handoff_path = gm_crit_ho
  ))
  ctr_gm_crit_live <- contrast_mgmfrm(fit_gm_crit, facet = "criterion", a = "I2", b = "I1")
  wss_gm <- diagnostics_mgmfrm(fit_gm_si, "weighted_sufficient_score")
  stopifnot(
    identical(fit_gm_si$identification, "geometric_mean_one"),
    identical(fit_gm_si$steps, "item"),
    is.data.frame(wss_gm),
    nrow(wss_gm) == length(unique(ratings$person)),
    all(wss_gm$person %in% unique(ratings$person))
  )
  mg_lkj_ho <- tempfile("mg-lkj-handoff-", fileext = ".json")
  fit_mg_lkj <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, model = "mgmfrm", Q = Q_mat,
    scale_identification = "geometric_mean_one",
    correlation = "lkj", lkj_eta = 2.0, ability_sd_prior = "half_normal",
    chains = 2L, warmup = 15L, draws = 15L, seed = 99L,
    handoff_path = mg_lkj_ho
  ))
  wss_mg1 <- diagnostics_mgmfrm(fit_mg_lkj, "weighted_sufficient_score", facet = 1L)
  stopifnot(
    "latent_correlation[dim=1, dim=2]" %in% names(coef(fit_mg_lkj)),
    all(abs(posterior::as_draws_array(fit_mg_lkj)[, , "latent_correlation[dim=1, dim=2]"]) <= 1.0),
    is.data.frame(wss_mg1),
    nrow(wss_mg1) == length(unique(ratings$person)),
    file.exists(mg_lkj_ho)
  )

  # Permuted rownames(Q) + colnames(Q), steps = "global", rater_slope_scope = "ability_only", and aggregation = "softmin"
  obs_it <- sort(unique(as.character(ratings$item)), method = "radix")
  Q_cross <- matrix(c(1, 0, 0, 1, 1, 1, 0, 1)[seq_len(2L * length(obs_it))],
                    nrow = length(obs_it), ncol = 2L, byrow = TRUE,
                    dimnames = list(rev(obs_it), c("Accuracy", "Fluency")))
  mg_sm_ho <- tempfile("mg-sm-handoff-", fileext = ".json")
  fit_mg_sm <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, model = "mgmfrm", Q = Q_cross, steps = "global",
    logit_scale = 1.0, rater_slope_scope = "ability_only",
    aggregation = "softmin", chains = 2L, warmup = 15L, draws = 15L, seed = 100L,
    handoff_path = mg_sm_ho
  ))
  ratings_25 <- ratings
  ratings_25$score <- as.integer(1L + 8L * as.integer(ratings$score))
  gm25_ho <- tempfile("gm-1to25-handoff-", fileext = ".json")
  fit_gm25 <- suppressWarnings(fit_mgmfrm(
    ratings_25, 1:25, model = "gmfrm", slope = "rater", steps = "global",
    chains = 2L, warmup = 10L, draws = 10L, seed = 104L, handoff_path = gm25_ho
  ))
  fa_mg_sm <- diagnostics_mgmfrm(
    fit_mg_sm, "fair_average",
    reference_plan = data.frame(item = obs_it[1:2], rater = c("R1", "R2"))
  )
  stopifnot(
    identical(fit_mg_sm$steps, "global"),
    "softmin_kappa" %in% names(coef(fit_mg_sm)),
    identical(fit_mg_sm$ids$dimension, c("Accuracy", "Fluency")),
    all(is.finite(fa_mg_sm$rows$mean))
  )

  # Numeric domain item IDs (e.g., 101, 102, 201, 202) with scale_identification = "anchor_item"
  ratings_num_it <- ratings
  it_map_num <- setNames(c(101L, 102L, 201L, 202L)[seq_along(obs_it)], obs_it)
  ratings_num_it$item <- unname(it_map_num[as.character(ratings$item)])
  fit_mg_num_anc <- suppressWarnings(fit_mgmfrm(
    ratings_num_it, 0:3, model = "mgmfrm", Q = Q_mat,
    scale_identification = "anchor_item", anchor_items = c(101L, 201L),
    chains = 2L, warmup = 12L, draws = 12L, seed = 102L
  ))
  stopifnot(
    identical(fit_mg_num_anc$identification, "anchor_item"),
    identical(as.integer(fit_mg_num_anc$ids$item), unname(it_map_num)),
    inherits(try(fit_mgmfrm(ratings_num_it, 0:3, model = "mgmfrm", Q = Q_mat,
                            scale_identification = "anchor_item", anchor_items = c(101L, 999L)), silent = TRUE), "try-error")
  )

  # Full-draw 1D Bayesian fit + live checks of marginal Fair-M/Z, pair_bias, classification, and ranking
  fit_full_1d <- suppressWarnings(fit_mgmfrm(
    ratings, 0:3, steps = "global", chains = 2L, warmup = 20L, draws = 20L, seed = 103L
  ))
  mfa_live_b <- diagnostics_mgmfrm(fit_full_1d, "fair_average", facet = "rater", baseline = "sample_mean")
  mfa_live_f <- diagnostics_mgmfrm(fit_mmle, "fair_average", facet = "rater", baseline = "sample_mean")
  pb_live_b <- diagnostics_mgmfrm(fit_full_1d, "pair_bias", pair = c("rater", "item"))
  pb_live_f <- diagnostics_mgmfrm(fit_grp_mmle, "pair_bias", pair = c("rater", "cohort"))
  cls_live_1d <- diagnostics_mgmfrm(fit_full_1d, "classification", cutoff = 0.0, pass_probability = 0.6, location = "linked")
  cls_live_2d <- diagnostics_mgmfrm(fit_mg_sm, "classification", cutoff = 0.0, dimension = "Fluency")
  rk_live_2d <- diagnostics_mgmfrm(fit_mg_sm, "ranking", direction = "higher", top_k = 3L, dimension = "Accuracy")
  stopifnot(
    all(c("fair_m", "fair_z") %in% names(diagnostics_mgmfrm(fit_mmle, "fit_statistics", facet = "rater"))),
    identical(mfa_live_b$rows$level, c("R1", "R2", "R3")),
    identical(mfa_live_f$rows$level, c("R1", "R2", "R3")),
    all(is.finite(mfa_live_f$rows$fair_average_se)),
    nrow(pb_live_b$rows) > 0L,
    identical(pb_live_f$analysis_mode, "joint_interaction_model"),
    all(is.finite(pb_live_f$rows$joint_interaction_logit)),
    nrow(cls_live_1d$rows) == length(unique(ratings$person)),
    nrow(cls_live_2d$rows) == length(unique(ratings$person)),
    nrow(rk_live_2d$rows) == length(unique(ratings$person)),
    all(rk_live_2d$rows$top_k_upper >= rk_live_2d$rows$top_k_lower)
  )
  full_1d_ho <- tempfile("full-1d-ho-", fileext = ".json")
  full_1d_rec <- handoff_mgmfrm(fit_full_1d, full_1d_ho, return_receipt = TRUE)

  # 6b. Mixed-category 1D PCM, bounded fixed_calibration (subset means + hard locations), and event IDs
  ratings_mix <- ratings
  ratings_mix$score <- ifelse(ratings_mix$item %in% c("I1", "I2"), pmin(ratings_mix$score, 2L), ratings_mix$score)
  mix_cats_live <- list(I1 = 0:2, I2 = 0:2, I3 = 0:3, I4 = 0:3)
  mix_nat_ho <- tempfile("mix-native-ho-", fileext = ".json")
  fit_mix_b <- suppressWarnings(fit_mgmfrm(
    ratings_mix, mix_cats_live, steps = "auto", method = "nuts",
    chains = 2L, warmup = 25L, draws = 25L, seed = 97L, handoff_path = mix_nat_ho
  ))
  ctr_mix_live <- contrast_mgmfrm(fit_mix_b, facet = "item", a = "I4", b = "I1")
  stopifnot(identical(fit_mix_b$steps, "item"), is.list(fit_mix_b$category_levels))

  # Common-rubric rater-nested-in-task table with subset-mean fixed_calibration and event IDs
  nest_rows <- list()
  for (p in 1:6) {
    for (ti in 1:2) {
      tk <- paste0("T", ti)
      pnl <- if (ti == 1L) c("R1", "R2") else c("R3", "R4")
      rsp <- paste0("Resp_", p, "_", tk)
      for (ri in 1:2) {
        rt <- pnl[[ri]]
        ass <- paste0("Ass_", p, "_", tk, "_", rt)
        for (ci in 1:3) {
          nest_rows[[length(nest_rows) + 1L]] <- data.frame(
            person = paste0("P", p), task = tk, rater = rt, item = paste0("C", ci),
            score = as.integer((p + ti + ri + ci) %% 3L),
            response_id = rsp, assessment_id = ass, stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  nest_df <- do.call(rbind, nest_rows)
  nest_facets <- c(task = "task", rater = "rater", item = "item")
  stopifnot(inherits(try(
    fit_mgmfrm(nest_df, 0:2, facets = nest_facets, steps = "global", method = "mmle"),
    silent = TRUE
  ), "try-error"))
  fc_panel <- list(groups = list(
    list(block = "rater", levels = c("R1", "R2"), mean = 0),
    list(block = "rater", levels = c("R3", "R4"), mean = 0)
  ))
  fit_nest_mmle <- fit_mgmfrm(
    nest_df, 0:2, facets = nest_facets, steps = "global", method = "mmle",
    fixed_calibration = fc_panel, response_id = "response_id", assessment_id = "assessment_id"
  )
  fit_nest_no_ev <- fit_mgmfrm(
    nest_df, 0:2, facets = nest_facets, steps = "global", method = "mmle",
    fixed_calibration = fc_panel
  )
  dep_yes <- diagnostics_mgmfrm(fit_nest_mmle, "validation")$dependence_units
  dep_no <- diagnostics_mgmfrm(fit_nest_no_ev, "validation")$dependence_units
  ctr_nest_within <- contrast_mgmfrm(fit_nest_mmle, facet = "rater", a = "R2", b = "R1")
  ctr_nest_between <- contrast_mgmfrm(fit_nest_mmle, facet = "task", a = "T2", b = "T1")
  stopifnot(
    identical(fit_nest_mmle$identification, "isometric_fixed_calibration"),
    identical(fit_nest_mmle$metadata$fixed_calibration$uncertainty, "conditional_on_fixed_calibration"),
    isTRUE(dep_yes$event_membership_known),
    identical(as.integer(dep_yes$n_events), 24L),
    identical(as.integer(dep_yes$n_responses), 12L),
    isFALSE(dep_no$event_membership_known),
    is.null(dep_no$n_events),
    is.null(dep_no$n_responses)
  )
  nest_r_ho <- tempfile("nest-mmle-ho-", fileext = ".json")
  nest_rec <- handoff_mgmfrm(fit_nest_mmle, nest_r_ho, return_receipt = TRUE)

  # 7. Stop Julia and verify 100% offline RDS + verified JSON handoff round-trips
  JuliaConnectoR::stopJulia()

  mix_nat_re <- read_handoff_mgmfrm(mix_nat_ho)
  nest_re <- read_handoff_mgmfrm(nest_r_ho, expected_sha256 = nest_rec$sha256)
  full_1d_re <- read_handoff_mgmfrm(full_1d_ho, expected_sha256 = full_1d_rec$sha256)
  stopifnot(
    max(abs(diagnostics_mgmfrm(full_1d_re, "fair_average", facet = "rater")$rows$mean - mfa_live_b$rows$mean)) < 1e-12,
    max(abs(diagnostics_mgmfrm(full_1d_re, "pair_bias", pair = c("rater", "item"))$rows$approx_severity_bias_logit_mean -
            pb_live_b$rows$approx_severity_bias_logit_mean)) < 1e-12,
    identical(diagnostics_mgmfrm(full_1d_re, "classification", cutoff = 0.0, pass_probability = 0.6, location = "linked")$rows$decision,
              cls_live_1d$rows$decision),
    max(abs(diagnostics_mgmfrm(nest_re, "fair_average", facet = "rater")$rows$fair_average -
            diagnostics_mgmfrm(fit_nest_mmle, "fair_average", facet = "rater")$rows$fair_average)) < 1e-12,
    is.list(mix_nat_re$category_levels),
    identical(mix_nat_re$category_levels$I1, 0:2),
    identical(mix_nat_re$category_levels$I4, 0:3),
    abs(contrast_mgmfrm(mix_nat_re, facet = "item", a = "I4", b = "I1")$estimate - ctr_mix_live$estimate) < 1e-12,
    identical(nest_re$identification, "isometric_fixed_calibration"),
    abs(contrast_mgmfrm(nest_re, facet = "rater", a = "R2", b = "R1")$estimate - ctr_nest_within$estimate) < 1e-12,
    abs(contrast_mgmfrm(nest_re, facet = "task", a = "T2", b = "T1")$estimate - ctr_nest_between$estimate) < 1e-12
  )

  rds_path <- tempfile(fileext = ".rds")
  saveRDS(fit, rds_path)
  fit_rds <- readRDS(rds_path)
  stopifnot(
    nrow(summary(fit_rds)$estimates) == 5L,
    abs(contrast_mgmfrm(fit_rds, facet = "rater", a = "R2", b = "R1")$estimate - ctr_live$estimate) < 1e-12,
    identical(diagnostics_mgmfrm(fit_rds, "fit_statistics", facet = "rater")$level, c("R1", "R2", "R3"))
  )

  r_ho <- tempfile(fileext = ".json")
  r_rec <- handoff_mgmfrm(fit_rds, r_ho, return_receipt = TRUE)
  fit_ho <- read_handoff_mgmfrm(r_ho, expected_sha256 = r_rec$sha256)
  ctr_ho <- contrast_mgmfrm(fit_ho, facet = "rater", a = "R2", b = "R1")
  stopifnot(
    max(abs(vcov(fit_ho) - vcov(fit_rds))) < 1e-12,
    abs(ctr_ho$estimate - ctr_live$estimate) < 1e-12,
    abs(ctr_ho$lower - ctr_live$lower) < 1e-12,
    abs(ctr_ho$upper - ctr_live$upper) < 1e-12
  )

  native_reloaded <- read_handoff_mgmfrm(native_ho, variables = c("rater[1]", "rater[2]"))
  ctr_nat_live <- contrast_mgmfrm(native_reloaded, facet = "rater", a = "R2", b = "R1")
  stopifnot(
    identical(dim(posterior::as_draws_array(native_reloaded)), c(40L, 2L, 2L)),
    identical(native_reloaded$ids$rater, c("R1", "R2", "R3")),
    isTRUE(native_reloaded$metadata$handoff_verification$embedded_ieee754_sha256_verified),
    abs(ctr_nat_live$estimate - ctr_live$estimate) < 1e-12,
    abs(ctr_nat_live$lower - ctr_live$lower) < 1e-12,
    abs(ctr_nat_live$upper - ctr_live$upper) < 1e-12
  )
  # Tamper a single finite draw in Julia-exported native_ho & r_ho -> pure-R embedded SHA-256 check MUST fail without expected_sha256!
  raw_nat_live <- jsonlite::fromJSON(native_ho, simplifyVector = FALSE)
  raw_nat_live$draws[[1L]][[1L]] <- as.double(raw_nat_live$draws[[1L]][[1L]]) + 0.123456
  p_nat_live_bad <- tempfile(fileext = ".json")
  jsonlite::write_json(raw_nat_live, p_nat_live_bad, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_live_bad), silent = TRUE), "try-error"))

  # Swap rater IDs on live Julia-exported native_ho while keeping draws bit-identical -> handoff_bundle_sha256 MUST fail!
  raw_nat_swap <- jsonlite::fromJSON(native_ho, simplifyVector = FALSE)
  raw_nat_swap$ids$rater <- list("R3", "R2", "R1")
  p_nat_swap_bad <- tempfile(fileext = ".json")
  jsonlite::write_json(raw_nat_swap, p_nat_swap_bad, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  stopifnot(inherits(try(read_handoff_mgmfrm(p_nat_swap_bad), silent = TRUE), "try-error"))

  raw_r_live <- jsonlite::fromJSON(r_ho, simplifyVector = FALSE)
  raw_r_live$draws_flat[[1L]] <- as.double(raw_r_live$draws_flat[[1L]]) + 0.123456
  p_r_live_bad <- tempfile(fileext = ".json")
  jsonlite::write_json(raw_r_live, p_r_live_bad, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  stopifnot(inherits(try(read_handoff_mgmfrm(p_r_live_bad), silent = TRUE), "try-error"))

  # Reload Julia-exported GMFRM native PortableHandoff completely offline with ORIGINAL IDs (R2 - R1)
  gm_nat_reloaded <- read_handoff_mgmfrm(gm_native_ho)
  ctr_gm_reloaded <- contrast_mgmfrm(gm_nat_reloaded, facet = "rater", a = "R2", b = "R1")
  gm_crit_reloaded <- read_handoff_mgmfrm(gm_crit_ho)
  ctr_gm_crit_reloaded <- contrast_mgmfrm(gm_crit_reloaded, facet = "criterion", a = "I2", b = "I1")
  stopifnot(
    identical(gm_crit_reloaded$steps, "criterion"),
    isTRUE(gm_crit_reloaded$metadata$handoff_verification$bundle_sha256_verified),
    abs(ctr_gm_crit_reloaded$estimate - ctr_gm_crit_live$estimate) < 1e-12,
    grepl("item slopes = fixed\\(1\\)", paste(capture.output(print(gm_crit_reloaded)), collapse = "\n"))
  )
  mg_lkj_reloaded <- read_handoff_mgmfrm(mg_lkj_ho)
  mg_sm_reloaded <- read_handoff_mgmfrm(mg_sm_ho)
  gm25_reloaded <- read_handoff_mgmfrm(gm25_ho)
  raw_gm25_bad <- jsonlite::fromJSON(gm25_ho, simplifyVector = FALSE)
  raw_gm25_bad$prior_and_reference$category_levels <- as.list(0L:24L)
  p_gm25_bad <- tempfile(fileext = ".json")
  jsonlite::write_json(raw_gm25_bad, p_gm25_bad, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  stopifnot(
    identical(gm_nat_reloaded$model, "gmfrm"),
    identical(gm_nat_reloaded$steps, "rater"),
    identical(gm_nat_reloaded$identification, "gmfrm_item_sum_to_zero"),
    identical(gm_nat_reloaded$ids$rater, c("R1", "R2", "R3")),
    identical(gm_nat_reloaded$category_levels, 0L:3L),
    identical(gm_crit_reloaded$category_levels, 0L:3L),
    identical(mg_lkj_reloaded$category_levels, 0L:3L),
    identical(mg_sm_reloaded$category_levels, 0L:3L),
    identical(gm25_reloaded$category_levels, 1L:25L),
    isTRUE(gm25_reloaded$metadata$handoff_verification$bundle_sha256_verified),
    inherits(try(read_handoff_mgmfrm(p_gm25_bad), silent = TRUE), "try-error"),
    isTRUE(gm_nat_reloaded$metadata$handoff_verification$embedded_ieee754_sha256_verified),
    abs(ctr_gm_reloaded$estimate - ctr_gm_live$estimate) < 1e-12,
    abs(ctr_gm_reloaded$lower - ctr_gm_live$lower) < 1e-12,
    abs(ctr_gm_reloaded$upper - ctr_gm_live$upper) < 1e-12,
    identical(mg_lkj_reloaded$model, "mgmfrm"),
    identical(mg_lkj_reloaded$identification, "geometric_mean_one"),
    isTRUE(mg_lkj_reloaded$metadata$handoff_verification$embedded_ieee754_sha256_verified),
    isTRUE(mg_lkj_reloaded$metadata$handoff_verification$bundle_sha256_verified),
    abs(coef(mg_lkj_reloaded)[["latent_correlation[dim=1, dim=2]"]] -
        coef(fit_mg_lkj)[["latent_correlation[dim=1, dim=2]"]]) < 1e-12
  )

  # 8. Fresh child R process (never initialized Julia): verify original-ID estimate & interval for BOTH formats + tamper rejection
  fresh_script <- tempfile("fresh-r-verify-", fileext = ".R")
  writeLines(c(
    "args <- commandArgs(trailingOnly = TRUE)",
    "r_ho <- args[[1L]]; nat_ho <- args[[2L]]; gm_ho <- args[[3L]]",
    "bad_r <- args[[4L]]; bad_nat <- args[[5L]]",
    "exp_est <- as.double(args[[6L]]); exp_lo <- as.double(args[[7L]]); exp_hi <- as.double(args[[8L]])",
    "gm_est <- as.double(args[[9L]]); gm_lo <- as.double(args[[10L]]); gm_hi <- as.double(args[[11L]])",
    "library(BayesianMGMFRM)",
    "f_r <- read_handoff_mgmfrm(r_ho)",
    "c_r <- contrast_mgmfrm(f_r, facet = 'rater', a = 'R2', b = 'R1')",
    "stopifnot(isTRUE(f_r$metadata$handoff_verification$payload_sha256_verified),",
    "          abs(c_r$estimate - exp_est) < 1e-12, abs(c_r$lower - exp_lo) < 1e-12, abs(c_r$upper - exp_hi) < 1e-12)",
    "f_n <- read_handoff_mgmfrm(nat_ho)",
    "c_n <- contrast_mgmfrm(f_n, facet = 'rater', a = 'R2', b = 'R1')",
    "stopifnot(isTRUE(f_n$metadata$handoff_verification$embedded_ieee754_sha256_verified),",
    "          isTRUE(f_n$metadata$handoff_verification$bundle_sha256_verified),",
    "          isTRUE(f_n$metadata$handoff_verification$ids_and_audit_verified),",
    "          identical(f_n$ids$rater, c('R1', 'R2', 'R3')),",
    "          abs(c_n$estimate - exp_est) < 1e-12, abs(c_n$lower - exp_lo) < 1e-12, abs(c_n$upper - exp_hi) < 1e-12)",
    "f_g <- read_handoff_mgmfrm(gm_ho)",
    "c_g <- contrast_mgmfrm(f_g, facet = 'rater', a = 'R2', b = 'R1')",
    "stopifnot(identical(f_g$model, 'gmfrm'), identical(f_g$identification, 'gmfrm_item_sum_to_zero'),",
    "          isTRUE(f_g$metadata$handoff_verification$embedded_ieee754_sha256_verified),",
    "          isTRUE(f_g$metadata$handoff_verification$bundle_sha256_verified),",
    "          isTRUE(f_g$metadata$handoff_verification$ids_and_audit_verified),",
    "          abs(c_g$estimate - gm_est) < 1e-12, abs(c_g$lower - gm_lo) < 1e-12, abs(c_g$upper - gm_hi) < 1e-12)",
    "stopifnot(inherits(try(read_handoff_mgmfrm(bad_r), silent = TRUE), 'try-error'))",
    "stopifnot(inherits(try(read_handoff_mgmfrm(bad_nat), silent = TRUE), 'try-error'))",
    "cat('FRESH_R_PROCESS_BOTH_FORMATS_VERIFIED\\n')"
  ), fresh_script)
  rscript_bin <- file.path(R.home("bin"), "Rscript")
  fresh_status <- system2(
    rscript_bin,
    c(
      fresh_script,
      r_ho, native_ho, gm_native_ho, p_r_live_bad, p_nat_live_bad,
      sprintf("%.17g", ctr_live$estimate), sprintf("%.17g", ctr_live$lower), sprintf("%.17g", ctr_live$upper),
      sprintf("%.17g", ctr_gm_live$estimate), sprintf("%.17g", ctr_gm_live$lower), sprintf("%.17g", ctr_gm_live$upper)
    )
  )
  stopifnot(identical(as.integer(fresh_status), 0L))
}

# Shared effects reject unsupported combinations before connecting to Julia.
for (args in list(list(random_effects="missing"),
                  list(random_effects=c("item","item")),
                  list(random_effects="item", method="mmle"),
                  list(random_effects="item", identification="reference"),
                  list(random_effects="item", random_sd_scale=0))) {
  err <- tryCatch(do.call(fit_mgmfrm, c(list(data=ratings, category_levels=0:3), args)), error=identity)
  stopifnot(inherits(err,"error"), grepl("random_", conditionMessage(err)))
}
err <- tryCatch(fit_mgmfrm(ratings, 0:3, random_effects="item", group="rater"), error=identity)
stopifnot(inherits(err,"error"))

# G-theory validation is independent of a live Julia session.
stopifnot(
  inherits(try(fit_mgmfrm(ratings, model="gtheory", method="jmle", score="score", facets=c(rater="rater")), silent=TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, model="gtheory", method="reml", score="score", facets=c(rater="rater"), counts=list(rater=0)), silent=TRUE), "try-error"),
  inherits(try(fit_mgmfrm(ratings, 0:3, method="reml"), silent=TRUE), "try-error")
)
