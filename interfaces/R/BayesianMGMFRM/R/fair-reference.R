.fair_reference_condition <- function(object, b, indices, cats, mode) {
  if (!length(b$interactions)) {
    if (!is.null(mode)) stop("This model has no reference interactions.")
    return(list(adjustments = NULL, contexts = list(), warnings = character()))
  }
  if (length(mode) != 1L || !mode %in% c("fitted", "zero"))
    stop("Choose interaction_effects = 'fitted' or 'zero'.")
  roles <- vapply(b$facets, function(f) f$name, character(1))
  contexts <- lapply(b$contexts, function(c) {
    values <- object$ids[[c$name]][unlist(c$values)]
    if (length(values) != length(b$people) || anyNA(values)) stop("Missing saved person context IDs.")
    list(name = c$name, rows = data.frame(
      person = object$ids$person[vapply(b$people, function(p) as.integer(p$level), integer(1))], value = values))
  })
  adjustments <- if (mode == "zero") NULL else lapply(seq_along(b$people), function(p) {
    lapply(seq_along(indices[[1L]]), function(j) {
      location <- character(); steps <- rep(list(character()), length(cats)-1L)
      for (term in b$interactions) {
        ix <- vapply(seq_along(term$roles), function(k) {
          role <- term$roles[[k]]; f <- match(role, roles)
          value <- if (is.na(f)) {
            cs <- Filter(function(c) identical(c$name, role), b$contexts)
            if (length(cs) != 1L) stop("Missing reference interaction context.")
            unlist(cs[[1L]]$values)[p]
          } else unlist(b$facets[[f]]$levels)[indices[[f]][j]]
          i <- match(value, unlist(term$levels[[k]]))
          if (is.na(i)) stop("Unknown reference interaction level.")
          i
        }, integer(1))
        if (identical(term$kind, "location")) {
          n <- term$parameters[[(ix[1L]-1L)*length(term$levels[[2L]])+ix[2L]]]
          if (!is.null(n)) location <- c(location, n)
        } else if (identical(term$kind, "steps")) {
          if (term$n_steps != length(steps)) stop("Reference interaction steps do not match category support.")
          for (h in seq_along(steps)) steps[[h]] <- c(steps[[h]], term$parameters[[(ix[1L]-1L)*term$n_steps+h]])
        } else stop("Unknown reference interaction kind.")
      }
      list(location = location, steps = steps)
    })
  })
  list(adjustments = adjustments, contexts = contexts, warnings = c(
    if (mode == "fitted") "Fitted interactions are retained in expected scores." else
      "Interactions are set to zero only for reporting; ability estimates still come from the fitted interaction model. This is not a refit without interactions or a causal bias correction.",
    if (length(contexts)) "Each person's observed group/context is held fixed; the common reference plan does not standardize group membership."))
}

.fair_reference_summary <- function(v, iterations, chains, interval, threshold = NULL, strict = FALSE) {
  probs <- c((1 - interval)/2, (1 + interval)/2)
  q <- stats::quantile(v, probs, names = FALSE)
  mat <- matrix(v, iterations, chains)
  available <- chains >= 2L && iterations >= 10L && length(unique(v)) > 1L
  finite <- function(x) ifelse(is.finite(x), x, NA_real_)
  qm <- if (available) unname(finite(posterior::mcse_quantile(mat, probs = probs))) else c(NA_real_, NA_real_)
  status <- if (chains < 2L) "insufficient_chains" else if (iterations < 10L) "insufficient_draws" else if (!available) "degenerate_draws" else "available"
  out <- data.frame(mean = mean(v), median = stats::median(v), sd = stats::sd(v), lower = q[1], upper = q[2],
    mcse_mean = if (available) finite(posterior::mcse_mean(mat)) else NA_real_,
    mcse_lower = qm[1], mcse_upper = qm[2], mcse_status = status,
    rhat = if (available) finite(posterior::rhat(mat)) else NA_real_,
    ess_bulk = if (available) finite(posterior::ess_bulk(mat)) else NA_real_,
    ess_tail = if (available) finite(posterior::ess_tail(mat)) else NA_real_)
  if (available && anyNA(out[c("mcse_mean", "mcse_lower", "mcse_upper")])) out$mcse_status <- "mcse_unavailable"
  if (!is.null(threshold)) {
    if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold))
      stop("threshold/margin must be a single finite number.")
    event <- if (strict) v > threshold else v >= threshold
    event_available <- chains >= 2L && iterations >= 10L && length(unique(event)) > 1L
    out$threshold <- threshold
    out$operator <- if (strict) "greater" else "greater_equal"
    out$count <- sum(event); out$probability <- mean(event)
    out$probability_mcse <- if (event_available) finite(posterior::mcse_mean(matrix(as.double(event), iterations, chains))) else NA_real_
    out$probability_status <- if (chains < 2L) "insufficient_chains" else if (iterations < 10L) "insufficient_draws" else
      if (length(unique(event)) == 1L) "degenerate_draws" else if (is.na(out$probability_mcse)) "mcse_unavailable" else "available"
  }
  out
}

.fair_reference <- function(object, reference_plan, interval = .95, threshold = NULL, comparisons = NULL,
                            shared_effects = NULL, quadrature_orders = c(61L, 121L), quadrature_tolerance = 1e-7, interaction_effects = NULL) {
  b <- object$metadata$fair_reference_basis
  if (is.null(b) || !b$schema %in% c("bayesianmgmfrm.fair_reference_basis.v1", "bayesianmgmfrm.fair_reference_basis.v2")) {
    reason <- if (!is.null(b$reason)) b$reason else if (identical(object$identification, "handoff"))
      "Retain the native fit_mgmfrm() object (e.g., via saveRDS/readRDS) rather than a draw-only handoff." else "Basis metadata unavailable."
    stop("This saved fit has no common-reference basis. ", reason)
  }
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must be in (0, 1).")
  roles <- vapply(b$facets, function(x) x$name, character(1))
  if (!length(roles)) stop("A common reference plan requires at least one non-shared facet.")
  if ("Weight" %in% roles || !is.data.frame(reference_plan) || !nrow(reference_plan) ||
      anyDuplicated(names(reference_plan)) || !setequal(setdiff(names(reference_plan), "Weight"), roles))
    stop("reference_plan must contain each fitted facet role and optional Weight only.")
  plan <- reference_plan[roles]
  indices <- lapply(roles, function(role) {
    x <- plan[[role]]
    if (!(is.character(x) || is.factor(x) || is.numeric(x)) || anyNA(x)) stop("Invalid reference IDs.")
    ix <- match(x, object$ids[[role]])
    if (anyNA(ix)) stop("Unknown reference level in facet ", role, ".")
    fb <- b$facets[[match(role, roles)]]
    j <- match(ix, unlist(fb$levels, use.names = FALSE))
    if (anyNA(j)) stop("Reference IDs do not match the stored basis.")
    j
  })
  if (anyDuplicated(as.data.frame(indices))) stop("Duplicate reference cells: combine their weights.")
  w <- reference_plan$Weight
  if (is.null(w)) w <- rep(1, nrow(plan))
  if (!is.numeric(w) || any(!is.finite(w) | w <= 0)) stop("Reference weights must be finite and positive.")
  plan$Weight <- w
  w <- w/max(w); w <- w/sum(w)
  if (any(w <= 0)) stop("Reference weight ratios are too extreme.")
  plan$NormalizedWeight <- w
  groups <- if (identical(b$owner, "global")) rep(1L, nrow(plan)) else {
    owner <- match(b$owner, roles)
    if (is.na(owner)) stop("Unsupported reference step owner.")
    codes <- unlist(b$facets[[owner]]$levels)[indices[[owner]]]
    match(codes, vapply(b$steps, function(x) as.integer(x$level), integer(1)))
  }
  if (anyNA(groups)) stop("Unknown reference step group.")
  cats <- as.double(unlist(b$steps[[groups[1L]]]$categories))
  if (!all(vapply(groups, function(g) identical(as.double(unlist(b$steps[[g]]$categories)), cats), logical(1))))
    stop("Reference cells must share a category score scale; choose a common-support subset.")
  conditioning <- .fair_reference_condition(object, b, indices, cats, interaction_effects)
  if (!is.null(b$frequentist)) {
    if (!is.null(shared_effects)) stop("This frequentist model has no shared effects.")
    return(.fair_reference_frequentist(object, b, plan, indices, groups, w, cats, interval, threshold, comparisons, interaction_effects, conditioning))
  }
  if (is.null(object$draws) || !identical(object$method, "nuts")) stop("Joint Bayesian draws are missing.")
  generalized <- identical(b$kernel, "mgmfrm")
  shared <- length(b$shared) > 0L
  if (shared && (length(shared_effects) != 1L || !shared_effects %in% c("zero", "marginal_new")))
    stop("Choose shared_effects = 'zero' or 'marginal_new'.")
  if (!shared && !is.null(shared_effects)) stop("This model has no shared effects.")
  arr <- as.array(object$draws); dims <- dim(arr)
  values <- matrix(arr, nrow = dims[1L]*dims[2L], ncol = dims[3L])
  colnames(values) <- dimnames(arr)[[3L]]
  required <- unique(c(unlist(lapply(b$people, function(x) if (generalized) x$parameters else x$parameter)),
    unlist(lapply(b$facets, function(x) x$parameters)), unlist(lapply(b$steps, function(x) x$parameters)), b$intercept,
    if (identical(interaction_effects, "fitted")) unlist(lapply(b$interactions, function(t) t$parameters)),
    if (generalized) c(unlist(b$loadings), unlist(b$consistency), b$softmin_kappa),
    if (identical(shared_effects, "marginal_new")) unlist(lapply(b$shared, function(x) x$sd_parameter))))
  if (!all(required %in% colnames(values)) || any(!is.finite(values)))
    stop("Common-plan scores require all finite person, facet and step draws; refit without a variables subset or restore a complete handoff.")
  eval_plan <- function(x, nodes = 0, weights = 1) {
    out <- matrix(0, nrow(x), length(b$people))
    for (j in seq_len(nrow(plan))) {
      shift <- if (is.null(b$intercept)) rep(0, nrow(x)) else x[, b$intercept]
      for (k in seq_along(roles)) shift <- shift - x[, unlist(b$facets[[k]]$parameters)[indices[[k]][j]]]
      tau <- x[, unlist(b$steps[[groups[j]]]$parameters), drop = FALSE]
      tau_cum <- matrix(0, nrow(x), length(cats))
      for (k in 2:length(cats)) tau_cum[, k] <- tau_cum[, k-1L] + tau[, k-1L]
      for (p in seq_along(b$people)) {
        adjustment <- conditioning$adjustments[[p]][[j]]
        person_shift <- shift; person_tau <- tau_cum
        if (!is.null(adjustment)) {
          if (length(adjustment$location)) person_shift <- person_shift - rowSums(x[, adjustment$location, drop = FALSE])
          for (h in seq_along(adjustment$steps)) if (length(adjustment$steps[[h]])) {
            delta <- rowSums(x[, adjustment$steps[[h]], drop = FALSE])
            for (k in (h+1L):length(cats)) person_tau[, k] <- person_tau[, k] + delta
          }
        }
        alpha <- rep(1, nrow(x))
        if (generalized) {
          i <- indices[[1L]][j]; r <- indices[[2L]][j]
          a <- x[, unlist(b$loadings[[i]]), drop = FALSE]
          theta <- x[, unlist(b$people[[p]]$parameters)[unlist(b$active_dims[[i]])], drop = FALSE]
          c_r <- x[, unlist(b$consistency)[r]]
          if (identical(b$item_slope_scope, "entire_linear_predictor")) {
            alpha <- b$logit_scale * c_r * a[, 1L]; eta <- theta[, 1L] + person_shift
          } else {
            m_act <- ncol(a)
            if (m_act == 1L) {
              u_pi <- a[, 1L] * theta[, 1L]
            } else if (identical(b$aggregation, "softmin")) {
              kap <- x[, b$softmin_kappa]
              neg_sc <- -(a * theta) * kap
              mx_sc <- apply(neg_sc, 1L, max)
              u_pi <- -(mx_sc + log(rowSums(exp(neg_sc - mx_sc))) - log(m_act)) / kap
            } else {
              u_pi <- rowSums(a * theta)
              if (isTRUE(b$cross_loading_average)) u_pi <- u_pi / m_act
            }
            if (identical(b$rater_slope_scope, "ability_only")) {
              alpha <- rep(b$logit_scale, nrow(x)); eta <- c_r * u_pi + person_shift
            } else {
              alpha <- b$logit_scale * c_r; eta <- u_pi + person_shift
            }
          }
        } else eta <- x[, b$people[[p]]$parameter] + person_shift
        sigma <- if (identical(shared_effects, "marginal_new"))
          sqrt(Reduce(`+`, lapply(b$shared, function(sb) if (is.null(sb$sd_parameter)) sb$sd^2 else x[, sb$sd_parameter]^2))) else 0
        for (q in seq_along(nodes)) {
          z <- (outer(eta + sigma*nodes[q], seq_along(cats)-1L) - person_tau) * alpha
          z <- exp(z - apply(z, 1L, max))
          out[, p] <- out[, p] + w[j]*weights[q]*drop(z %*% cats)/rowSums(z)
        }
      }
    }
    out
  }
  x <- rbind(values, colMeans(values)); integration <- NULL
  if (identical(shared_effects, "marginal_new")) {
    if (!is.numeric(quadrature_orders) || length(quadrature_orders) != 2L || any(!is.finite(quadrature_orders)) ||
        any(quadrature_orders != as.integer(quadrature_orders)) || any(quadrature_orders < 3) || diff(quadrature_orders) <= 0)
      stop("quadrature_orders must contain two increasing integers >= 3.")
    if (!is.numeric(quadrature_tolerance) || length(quadrature_tolerance) != 1L ||
        !is.finite(quadrature_tolerance) || quadrature_tolerance <= 0) stop("quadrature_tolerance must be positive.")
    rules <- lapply(quadrature_orders, function(n) {
      jac <- matrix(0, n, n); jac[cbind(1:(n-1L), 2:n)] <- sqrt(1:(n-1L)); jac <- jac + t(jac)
      e <- eigen(jac, symmetric = TRUE)
      eval_plan(x, e$values, e$vectors[1L, ]^2)
    })
    err <- max(abs(rules[[2L]]-rules[[1L]]))
    if (err > quadrature_tolerance) stop("Shared-effect quadrature difference exceeds tolerance; increase quadrature_orders.")
    integration <- list(orders = quadrature_orders, tolerance = quadrature_tolerance, max_score_difference = err)
    evaluated <- rules[[2L]]
  } else evaluated <- eval_plan(x)
  fair <- evaluated[-nrow(evaluated), , drop = FALSE]; plugin <- evaluated[nrow(evaluated), ]
  persons <- object$ids$person[vapply(b$people, function(x) as.integer(x$level), integer(1))]
  rows <- do.call(rbind, lapply(seq_along(b$people), function(p) {
    pb <- b$people[[p]]
    observed <- if (identical(as.double(unlist(pb$observed_categories)), cats)) as.double(pb$observed_average) else NA_real_
    s <- .fair_reference_summary(fair[, p], dims[1L], dims[2L], interval, threshold)
    cbind(data.frame(person = persons[p], n_observations = pb$n_observations, observed_average = observed,
      adjustment_mean = s$mean-observed, plugin_mean = plugin[p]), s)
  }))
  contrasts <- data.frame()
  if (!is.null(comparisons)) {
    if (!is.data.frame(comparisons) || !nrow(comparisons) || anyDuplicated(names(comparisons)) ||
        !setequal(names(comparisons), c("left", "right", "margin")))
      stop("comparisons must be a data frame with left, right and margin.")
    contrasts <- do.call(rbind, lapply(seq_len(nrow(comparisons)), function(i) {
      c <- comparisons[i, ]; ids <- match(c(c$left, c$right), persons)
      if (anyNA(ids) || ids[1] == ids[2]) stop("Comparisons require two distinct known person IDs.")
      cbind(c, .fair_reference_summary(fair[,ids[1]]-fair[,ids[2]], dims[1L], dims[2L], interval, c$margin, TRUE))
    }))
  }
  structure(list(schema = "bayesianmgmfrm.r_fair_reference.v1", target = "common_plan_expected_average",
    rows = rows, contrasts = contrasts, reference_plan = plan, category_levels = cats,
    interaction_effects = interaction_effects, held_contexts = conditioning$contexts,
    interval_target = "posterior_expected_score", conditioning = if (is.null(shared_effects)) "known_facet_levels" else shared_effects, integration = integration,
    interval = interval, n_draws = nrow(fair), chains = dims[2L], draws_per_chain = dims[1L],
    qualification = object$metadata$qualification, source_handoff_hash = object$metadata$handoff_hash,
    warnings = c(unlist(object$metadata$warnings), conditioning$warnings, "Intervals describe expected scores, not future realized ratings; whole-fit warnings remain applicable.")),
    class = "mgmfrm_fair_average")
}

print.mgmfrm_fair_average <- function(x, ...) {
  cat("Common-plan Fair Average\n")
  print(x$rows, row.names = FALSE, ...)
  if (nrow(x$contrasts)) { cat("\nExpected-score contrasts\n"); print(x$contrasts, row.names = FALSE, ...) }
  invisible(x)
}

plot.mgmfrm_fair_average <- function(x, ...) {
  old <- graphics::par(mar = c(7, 5, 3, 1))
  on.exit(graphics::par(old))
  r <- x$rows; y <- seq_len(nrow(r))
  title <- paste0("Common-plan Fair Average", if (identical(x$conditioning, "marginal_new")) ": New events" else
    if (identical(x$conditioning, "zero")) ": Zero shared effects" else "")
  if (!is.null(x$interaction_effects)) title <- paste0(title, "\n", if (x$interaction_effects == "fitted") "Fitted interactions" else "Zero interaction reference")
  graphics::plot(r$mean, y, xlim = range(c(x$category_levels, r$observed_average, r$lower, r$upper), na.rm = TRUE),
    ylim = c(nrow(r)+.5, .5), yaxt = "n", xlab = "Score", ylab = "Person",
    main = title, pch = 19, col = "steelblue4", ...)
  graphics::axis(2, at = y, labels = r$person, las = 1)
  graphics::segments(r$lower, y, r$upper, y, col = "steelblue4", lwd = 2)
  graphics::points(r$observed_average, y, pch = 5)
  label <- if (identical(x$interval_target, "wald_expected_score")) "Estimate / Wald CI" else
    if (identical(x$interval_target, "conditional_posterior_expected_score")) "Conditional mean / CrI" else "Posterior mean / CrI"
  graphics::legend(mean(graphics::par("usr")[1:2]), graphics::grconvertY(.04, from = "nfc", to = "user"),
    c(sprintf("%s (%.1f%%)", label, 100*x$interval), "Observed average"),
    col = c("steelblue4", "black"), pch = c(19, 5), bty = "n", horiz = TRUE, xjust = .5, yjust = 0, xpd = NA)
  cat("Expected-score uncertainty, conditional on the saved reference plan. Whole-fit numerical qualification: ",
      isTRUE(x$qualification$qualified), ".\n", paste(x$warnings, collapse = " "), "\n", sep = "")
  invisible(x)
}

.adj_expected_and_slope_scalar <- function(eta, tau_vec, cats) {
  cats <- as.double(cats)
  K <- length(cats)
  if (is.na(eta)) return(c(NA_real_, NA_real_))
  if (!is.finite(eta)) {
    return(c(if (eta > 0) cats[[K]] else cats[[1L]], 0.0))
  }
  tau_cum <- c(0.0, cumsum(as.double(tau_vec)))
  z <- (seq_len(K) - 1.0) * eta - tau_cum
  zm <- max(z)
  w <- exp(z - zm)
  pr <- w / sum(w)
  ev <- sum(pr * cats)
  slp <- sum(pr * (cats - ev) * (seq_len(K) - 1.0))
  c(ev, slp)
}

.adj_expected_draws <- function(eta_vec, tau_mat, cats) {
  cats <- as.double(cats)
  K <- length(cats)
  S <- length(eta_vec)
  tau_cum <- matrix(0.0, nrow = S, ncol = K)
  if (K >= 2L) {
    for (k in 2:K) tau_cum[, k] <- tau_cum[, k - 1L] + tau_mat[, k - 1L]
  }
  z <- outer(as.double(eta_vec), seq_len(K) - 1.0) - tau_cum
  zm <- apply(z, 1L, max)
  w <- exp(z - zm)
  drop((w %*% cats) / rowSums(w))
}

.decode_freq_basis_num <- function(vals_list, par_names) {
  nums <- vapply(vals_list, function(v) {
    if (is.null(v) || length(v) != 1L || is.na(v)) return(NA_real_)
    if (identical(v, "Inf")) return(Inf)
    if (identical(v, "-Inf")) return(-Inf)
    suppressWarnings(as.double(v))
  }, double(1L))
  setNames(nums, as.character(unlist(par_names, use.names = FALSE)))
}

.marginal_fair_average <- function(object, facet, baseline = "sample_mean", step_group = NULL, interval = 0.95) {
  if (!is.character(facet) || length(facet) != 1L || !nzchar(facet))
    stop("Supply a single facet name such as 'rater', 'item', or 'person'.")
  if (identical(facet, "entity")) facet <- "person"
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must be in (0, 1).")
  b <- object$metadata$fair_reference_basis
  if (is.null(b) || !b$schema %in% c("bayesianmgmfrm.fair_reference_basis.v1", "bayesianmgmfrm.fair_reference_basis.v2"))
    stop("This saved fit has no Fair Average basis metadata.")
  if (identical(b$kernel, "mgmfrm"))
    stop("Marginal Fair-M / Fair-Z applies to additive 1D MFRM fits; supply reference_plan = ... on GMFRM or MGMFRM fits.")

  f_roles <- vapply(b$facets, function(x) as.character(x$name), character(1L))
  is_person <- identical(facet, "person")
  if (!is_person && !(facet %in% f_roles))
    stop("Unknown facet '", facet, "'; available: ", paste(c("person", f_roles), collapse = ", "), ".")

  step_cats <- lapply(b$steps, function(s) as.double(unlist(s$categories)))
  G_s <- length(step_cats)
  same_sup <- G_s <= 1L || all(vapply(step_cats[-1L], function(cc) identical(cc, step_cats[[1L]]), logical(1L)))
  owner_role <- as.character(b$owner)
  owner_labels <- if (!identical(owner_role, "global") && !is.null(object$ids[[owner_role]])) {
    idx_lv <- vapply(b$steps, function(s) as.integer(s$level), integer(1L))
    as.character(object$ids[[owner_role]][idx_lv])
  } else {
    vapply(b$steps, function(s) as.character(s$level), character(1L))
  }

  chosen_g <- NULL
  if (!is.null(step_group)) {
    if (length(step_group) != 1L || is.na(step_group))
      stop("step_group must be a single step-owner level.")
    sg_chr <- as.character(step_group)
    gi <- match(sg_chr, owner_labels)
    if (is.na(gi)) gi <- match(sg_chr, vapply(b$steps, function(s) as.character(s$level), character(1L)))
    if (is.na(gi))
      stop("Unknown step_group '", sg_chr, "'; available: ", paste(owner_labels, collapse = ", "), ".")
    chosen_g <- gi
  } else if (!same_sup && !identical(facet, owner_role)) {
    stop("Marginal Fair Average for facet = '", facet,
         "' under mixed category supports requires step_group (available: ",
         paste(owner_labels, collapse = ", "), ") or facet = '", owner_role, "'.")
  }

  step_int_term <- NULL
  if (length(b$interactions) && !is_person) {
    for (tm in b$interactions) {
      if (identical(tm$kind, "steps") && length(tm$roles) == 1L && identical(as.character(tm$roles[[1L]]), facet)) {
        step_int_term <- tm
        break
      }
    }
  }

  if (!is.null(b$frequentist)) {
    vals_map <- .decode_freq_basis_num(b$frequentist$values, b$frequentist$parameters)
    mu_int <- if (is.null(b$intercept)) 0.0 else vals_map[[as.character(b$intercept)]]
    p_pars <- vapply(b$people, function(p) as.character(p$parameter), character(1L))
    th_vec <- unname(vals_map[p_pars])
    fin_th <- th_vec[is.finite(th_vec)]
    th_bar <- (if (length(fin_th)) mean(fin_th) else 0.0) + mu_int

    f_signed_means <- setNames(numeric(length(b$facets)), f_roles)
    for (k in seq_along(b$facets)) {
      fb <- b$facets[[k]]
      sgn <- if (!is.null(fb$sign)) as.double(fb$sign) else -1.0
      f_signed_means[[k]] <- sgn * mean(vals_map[unlist(fb$parameters)])
    }
    tot_f_shift <- sum(f_signed_means)
    tau_groups <- lapply(b$steps, function(s) unname(vals_map[unlist(s$parameters)]))
    tau_mean <- if (same_sup) rowMeans(do.call(cbind, tau_groups)) else numeric(0L)

    z_crit <- stats::qnorm(0.5 * (1.0 + interval))
    fs_tbl <- if (!is.null(object$fit_statistics) && !is.null(object$fit_statistics[[facet]])) object$fit_statistics[[facet]] else NULL
    L <- if (is_person) length(b$people) else length(b$facets[[match(facet, f_roles)]]$levels)
    lvl_labels <- if (!is.null(object$ids[[facet]])) {
      raw_codes <- if (is_person) vapply(b$people, function(p) as.integer(p$level), integer(1L)) else
        as.integer(unlist(b$facets[[match(facet, f_roles)]]$levels))
      as.character(object$ids[[facet]][raw_codes])
    } else as.character(seq_len(L))

    rows_list <- lapply(seq_len(L), function(j) {
      g_ref <- if (!is.null(chosen_g)) chosen_g else if (!is_person && identical(facet, owner_role)) j else 1L
      cats <- step_cats[[g_ref]]
      base_tau <- if (!is.null(chosen_g) || (!is_person && identical(facet, owner_role))) tau_groups[[g_ref]] else tau_mean
      tau_j <- if (!is.null(step_int_term)) {
        H_i <- as.integer(step_int_term$n_steps)
        s_pars <- unlist(step_int_term$parameters)[((j - 1L) * H_i + 1L):(j * H_i)]
        base_tau + unname(vals_map[s_pars])
      } else base_tau

      if (is_person) {
        par_nm <- p_pars[[j]]
        est_v <- th_vec[[j]]
        eta_m <- if (is.finite(est_v)) (est_v + mu_int + tot_f_shift) else est_v
        eta_z <- if (is.finite(est_v)) (est_v + mu_int) else est_v
        n_obs_j <- as.integer(b$people[[j]]$n_observations)
        obs_avg <- if (identical(as.double(unlist(b$people[[j]]$observed_categories)), cats)) as.double(b$people[[j]]$observed_average) else NA_real_
      } else {
        fb <- b$facets[[match(facet, f_roles)]]
        sgn <- if (!is.null(fb$sign)) as.double(fb$sign) else -1.0
        par_nm <- unlist(fb$parameters)[[j]]
        est_v <- vals_map[[par_nm]]
        eta_m <- th_bar + sgn * est_v + (tot_f_shift - f_signed_means[[facet]])
        eta_z <- mu_int + sgn * est_v
        n_obs_j <- if (!is.null(fs_tbl) && "n_ratings" %in% names(fs_tbl) && nrow(fs_tbl) >= j) as.integer(fs_tbl$n_ratings[[j]]) else NA_integer_
        obs_avg <- if ((!is.null(chosen_g) || same_sup || identical(facet, owner_role)) &&
                       !is.null(fs_tbl) && "observed_average" %in% names(fs_tbl) && nrow(fs_tbl) >= j) as.double(fs_tbl$observed_average[[j]]) else NA_real_
      }

      ms_m <- .adj_expected_and_slope_scalar(eta_m, tau_j, cats)
      ms_z <- .adj_expected_and_slope_scalar(eta_z, tau_j, cats)
      fa_val <- if (identical(baseline, "sample_mean")) ms_m[[1L]] else ms_z[[1L]]
      fa_slp <- if (identical(baseline, "sample_mean")) ms_m[[2L]] else ms_z[[2L]]

      se_l <- NA_real_
      is_fix <- FALSE
      if (!is.null(fs_tbl) && nrow(fs_tbl) >= j) {
        if ("fixed" %in% names(fs_tbl)) is_fix <- isTRUE(fs_tbl$fixed[[j]])
        if ("se" %in% names(fs_tbl) && !is.na(fs_tbl$se[[j]])) se_l <- as.double(fs_tbl$se[[j]])
      } else if (!is.null(object$estimates) && nrow(object$estimates)) {
        m_ix <- match(par_nm, object$estimates$variable)
        if (!is.na(m_ix)) se_l <- as.double(object$estimates$se[[m_ix]])
      }
      se_ok <- !is_fix && is.finite(se_l) && se_l > 0 && is.finite(est_v)
      fa_se <- if (se_ok && is.finite(fa_slp)) abs(fa_slp) * se_l else NA_real_

      data.frame(
        level = lvl_labels[[j]],
        n_observations = n_obs_j,
        observed_average = obs_avg,
        logit_estimate = if (is.finite(est_v)) est_v else NA_real_,
        logit_se = if (se_ok) se_l else NA_real_,
        fair_average = fa_val,
        fair_average_se = fa_se,
        fair_average_lower = if (is.finite(fa_se)) fa_val - z_crit * fa_se else NA_real_,
        fair_average_upper = if (is.finite(fa_se)) fa_val + z_crit * fa_se else NA_real_,
        fair_m = ms_m[[1L]],
        fair_z = ms_z[[1L]],
        min_category = as.integer(cats[[1L]]),
        max_category = as.integer(cats[[length(cats)]]),
        stringsAsFactors = FALSE
      )
    })
    return(list(
      schema = "bayesianmgmfrm.r_marginal_fair_average.v1",
      inference_paradigm = "frequentist",
      method = as.character(b$frequentist$method),
      by = facet,
      baseline = baseline,
      step_group = if (is.null(chosen_g)) (if (!is_person && identical(facet, owner_role)) "own_step_group" else "mean_step_profile") else owner_labels[[chosen_g]],
      interval = interval,
      rows = do.call(rbind, rows_list),
      qualification = object$metadata$qualification
    ))
  }

  if (is.null(object$draws) || !identical(object$method, "nuts"))
    stop("Joint Bayesian draws are missing.")
  arr <- as.array(object$draws); dims <- dim(arr)
  values <- matrix(arr, nrow = dims[[1L]] * dims[[2L]], ncol = dims[[3L]])
  colnames(values) <- dimnames(arr)[[3L]]

  p_pars <- vapply(b$people, function(p) as.character(p$parameter), character(1L))
  req <- unique(c(p_pars, unlist(lapply(b$facets, function(x) x$parameters)),
                  unlist(lapply(b$steps, function(x) x$parameters)), b$intercept,
                  if (!is.null(step_int_term)) unlist(step_int_term$parameters)))
  if (!all(req %in% colnames(values)) || any(!is.finite(values[, req, drop = FALSE])))
    stop("Marginal Fair Average requires all person, facet, and step draws; refit without a variables subset or restore a complete handoff.")

  S <- nrow(values)
  mu_int <- if (is.null(b$intercept)) rep(0.0, S) else values[, as.character(b$intercept)]
  th_mat <- values[, p_pars, drop = FALSE]
  p_base_m <- mu_int + rowMeans(th_mat)
  p_base_z <- mu_int

  f_row_means <- lapply(b$facets, function(fb) rowMeans(values[, unlist(fb$parameters), drop = FALSE]))
  names(f_row_means) <- f_roles
  tot_f_m <- Reduce(`+`, f_row_means, init = rep(0.0, S))

  tau_mats <- lapply(b$steps, function(s) values[, unlist(s$parameters), drop = FALSE])
  tau_mean_mat <- if (same_sup) Reduce(`+`, tau_mats) / G_s else NULL
  x_mean <- colMeans(values)

  L <- if (is_person) length(b$people) else length(b$facets[[match(facet, f_roles)]]$levels)
  lvl_labels <- if (!is.null(object$ids[[facet]])) {
    raw_codes <- if (is_person) vapply(b$people, function(p) as.integer(p$level), integer(1L)) else
      as.integer(unlist(b$facets[[match(facet, f_roles)]]$levels))
    as.character(object$ids[[facet]][raw_codes])
  } else as.character(seq_len(L))
  fs_tbl <- if (!is.null(object$fit_statistics) && !is.null(object$fit_statistics[[facet]])) object$fit_statistics[[facet]] else NULL

  rows_list <- lapply(seq_len(L), function(j) {
    g_ref <- if (!is.null(chosen_g)) chosen_g else if (!is_person && identical(facet, owner_role)) j else 1L
    cats <- step_cats[[g_ref]]
    base_tau <- if (!is.null(chosen_g) || (!is_person && identical(facet, owner_role))) tau_mats[[g_ref]] else tau_mean_mat
    tau_j <- if (!is.null(step_int_term)) {
      H_i <- as.integer(step_int_term$n_steps)
      s_pars <- unlist(step_int_term$parameters)[((j - 1L) * H_i + 1L):(j * H_i)]
      base_tau + values[, s_pars, drop = FALSE]
    } else base_tau

    if (is_person) {
      lv <- th_mat[, j]
      eta_m <- lv + mu_int - tot_f_m
      eta_z <- lv + mu_int
      n_obs_j <- as.integer(b$people[[j]]$n_observations)
      obs_avg <- if (identical(as.double(unlist(b$people[[j]]$observed_categories)), cats)) as.double(b$people[[j]]$observed_average) else NA_real_
    } else {
      fb <- b$facets[[match(facet, f_roles)]]
      lv <- values[, unlist(fb$parameters)[[j]]]
      oth_m <- tot_f_m - f_row_means[[facet]]
      eta_m <- p_base_m - lv - oth_m
      eta_z <- p_base_z - lv
      n_obs_j <- if (!is.null(fs_tbl) && "n_ratings" %in% names(fs_tbl) && nrow(fs_tbl) >= j) as.integer(fs_tbl$n_ratings[[j]]) else NA_integer_
      obs_avg <- if ((!is.null(chosen_g) || same_sup || identical(facet, owner_role)) &&
                     !is.null(fs_tbl) && "observed_average" %in% names(fs_tbl) && nrow(fs_tbl) >= j) as.double(fs_tbl$observed_average[[j]]) else NA_real_
    }

    fm_draws <- .adj_expected_draws(eta_m, tau_j, cats)
    fz_draws <- .adj_expected_draws(eta_z, tau_j, cats)
    sel_draws <- if (identical(baseline, "sample_mean")) fm_draws else fz_draws
    sel_eta_mean <- if (identical(baseline, "sample_mean")) mean(eta_m) else mean(eta_z)
    plug_fa <- .adj_expected_and_slope_scalar(sel_eta_mean, colMeans(tau_j), cats)[[1L]]
    sm <- .fair_reference_summary(sel_draws, dims[[1L]], dims[[2L]], interval)
    l_probs <- c((1.0 - interval) / 2.0, (1.0 + interval) / 2.0)
    lq <- stats::quantile(lv, l_probs, names = FALSE)

    cbind(
      data.frame(
        level = lvl_labels[[j]],
        n_observations = n_obs_j,
        observed_average = obs_avg,
        logit_mean = mean(lv),
        logit_sd = stats::sd(lv),
        logit_lower = lq[[1L]],
        logit_upper = lq[[2L]],
        plugin_fair_average = plug_fa,
        fair_m_mean = mean(fm_draws),
        fair_z_mean = mean(fz_draws),
        stringsAsFactors = FALSE
      ),
      sm,
      data.frame(min_category = as.integer(cats[[1L]]), max_category = as.integer(cats[[length(cats)]]), stringsAsFactors = FALSE)
    )
  })

  list(
    schema = "bayesianmgmfrm.r_marginal_fair_average.v1",
    inference_paradigm = "bayesian",
    method = "nuts",
    by = facet,
    baseline = baseline,
    step_group = if (is.null(chosen_g)) (if (!is_person && identical(facet, owner_role)) "own_step_group" else "mean_step_profile") else owner_labels[[chosen_g]],
    interval = interval,
    n_draws = S,
    rows = do.call(rbind, rows_list),
    qualification = object$metadata$qualification
  )
}

.pair_bias_mgmfrm <- function(object, pair = NULL, min_obs = 1L, interval = 0.95) {
  if (!is.numeric(min_obs) || length(min_obs) != 1L || !is.finite(min_obs) || min_obs < 1 || min_obs != trunc(min_obs))
    stop("min_obs must be a positive integer.")
  min_obs <- as.integer(min_obs)
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must be in (0, 1).")

  pb <- object$metadata$pair_bias_basis
  b <- object$metadata$fair_reference_basis
  if (is.null(pb) || !identical(pb$schema, "bayesianmgmfrm.pair_bias_basis.v1") || is.null(b))
    stop("This saved fit has no pair_bias_basis metadata; fit a 1D isometric MFRM model with fit_mgmfrm().")

  pb_facets <- lapply(pb$facets, function(v) as.integer(unlist(v, use.names = FALSE)))
  f_names <- names(pb_facets)
  grp_col_alias <- if (!is.null(object$columns) && "group" %in% names(object$columns)) as.character(object$columns[["group"]]) else NULL
  norm_role <- function(r) {
    rc <- as.character(r)
    if (identical(rc, "entity")) return("person")
    if (!is.null(grp_col_alias) && identical(rc, grp_col_alias) && ("group" %in% f_names)) return("group")
    rc
  }
  raw_pair <- if (is.null(pair)) {
    if (all(c("rater", "item") %in% f_names)) c("rater", "item") else
      if (length(f_names) >= 2L) f_names[1:2] else c("person", f_names[[1L]])
  } else {
    if (!is.character(pair) || length(pair) != 2L || anyNA(pair) || any(!nzchar(pair)))
      stop("pair must be a character vector of length 2, such as c('rater', 'item').")
    c(norm_role(pair[[1L]]), norm_role(pair[[2L]]))
  }
  r1 <- raw_pair[[1L]]; r2 <- raw_pair[[2L]]
  avail_roles <- c("person", f_names)
  if (!(r1 %in% avail_roles) || !(r2 %in% avail_roles) || identical(r1, r2))
    stop("pair roles must be two distinct roles from: ", paste(avail_roles, collapse = ", "), ".")

  p_idx <- as.integer(unlist(pb$person, use.names = FALSE))
  sg_idx <- as.integer(unlist(pb$step_group, use.names = FALSE))
  y_obs <- as.double(unlist(pb$score, use.names = FALSE))
  N <- length(y_obs)
  idx1 <- if (identical(r1, "person")) p_idx else pb_facets[[r1]]
  idx2 <- if (identical(r2, "person")) p_idx else pb_facets[[r2]]
  levs1 <- if (!is.null(object$ids[[r1]])) as.character(object$ids[[r1]]) else as.character(seq_len(max(idx1)))
  levs2 <- if (!is.null(object$ids[[r2]])) as.character(object$ids[[r2]]) else as.character(seq_len(max(idx2)))

  # Match optional fitted location interaction block
  loc_int_term <- NULL
  loc_flipped <- FALSE
  if (length(b$interactions)) {
    for (tm in b$interactions) {
      if (identical(tm$kind, "location") && length(tm$roles) == 2L) {
        tr1 <- as.character(tm$roles[[1L]]); tr2 <- as.character(tm$roles[[2L]])
        if (identical(tr1, r1) && identical(tr2, r2)) { loc_int_term <- tm; loc_flipped <- FALSE; break }
        if (identical(tr1, r2) && identical(tr2, r1)) { loc_int_term <- tm; loc_flipped <- TRUE; break }
      }
    }
  }
  analysis_mode <- if (is.null(loc_int_term)) "secondary_residual_screen" else "joint_interaction_model"

  # Group row indices by observed (i1, i2) cell
  max2 <- max(idx2)
  cell_code <- (idx1 - 1L) * max2 + idx2
  u_codes <- sort(unique(cell_code))
  cell_rows <- lapply(u_codes, function(cd) which(cell_code == cd))
  keep_c <- which(vapply(cell_rows, length, integer(1L)) >= min_obs)
  cell_rows <- cell_rows[keep_c]
  u_codes <- u_codes[keep_c]
  C_cells <- length(u_codes)

  b_f_roles <- vapply(b$facets, function(x) as.character(x$name), character(1L))
  step_cats <- lapply(b$steps, function(s) as.double(unlist(s$categories)))
  step_level_codes <- vapply(b$steps, function(s) as.integer(s$level), integer(1L))
  sg_pos <- if (identical(as.character(b$owner), "global")) rep(1L, N) else match(sg_idx, step_level_codes)

  if (!is.null(b$frequentist)) {
    vals_map <- .decode_freq_basis_num(b$frequentist$values, b$frequentist$parameters)
    mu_int <- if (is.null(b$intercept)) 0.0 else vals_map[[as.character(b$intercept)]]
    p_pars <- vapply(b$people, function(p) as.character(p$parameter), character(1L))
    th_vec <- unname(vals_map[p_pars])

    exp_row <- numeric(N); var_row <- numeric(N)
    for (n in seq_len(N)) {
      th <- th_vec[[p_idx[[n]]]]
      cats <- step_cats[[sg_pos[[n]]]]
      K <- length(cats)
      if (!is.finite(th)) {
        exp_row[[n]] <- if (th > 0) cats[[K]] else cats[[1L]]
        var_row[[n]] <- 0.0
      } else {
        eta <- th + mu_int
        for (k in seq_along(b$facets)) {
          fb <- b$facets[[k]]
          fn <- b_f_roles[[k]]
          lv_pos <- match(pb_facets[[fn]][[n]], as.integer(unlist(fb$levels)))
          sgn <- if (!is.null(fb$sign)) as.double(fb$sign) else -1.0
          eta <- eta + sgn * vals_map[[unlist(fb$parameters)[[lv_pos]]]]
        }
        tau <- unname(vals_map[unlist(b$steps[[sg_pos[[n]]]]$parameters)])
        if (length(b$interactions)) {
          for (tm in b$interactions) {
            if (identical(tm$kind, "location")) {
              tr1 <- as.character(tm$roles[[1L]]); tr2 <- as.character(tm$roles[[2L]])
              v1 <- pb_facets[[tr1]][[n]]; v2 <- pb_facets[[tr2]][[n]]
              p1 <- match(v1, as.integer(unlist(tm$levels[[1L]])))
              p2 <- match(v2, as.integer(unlist(tm$levels[[2L]])))
              pn <- tm$parameters[[(p1 - 1L) * length(tm$levels[[2L]]) + p2]]
              if (!is.null(pn)) eta <- eta - vals_map[[as.character(pn)]]
            } else if (identical(tm$kind, "steps")) {
              tr1 <- as.character(tm$roles[[1L]])
              p1 <- match(pb_facets[[tr1]][[n]], as.integer(unlist(tm$levels[[1L]])))
              H_i <- as.integer(tm$n_steps)
              sp <- unlist(tm$parameters)[((p1 - 1L) * H_i + 1L):(p1 * H_i)]
              tau <- tau + unname(vals_map[sp])
            }
          }
        }
        z <- (seq_len(K) - 1.0) * eta - c(0.0, cumsum(tau))
        w <- exp(z - max(z)); pr <- w / sum(w)
        er <- sum(pr * cats)
        exp_row[[n]] <- er
        var_row[[n]] <- sum(pr * (cats - er)^2)
      }
    }

    z_crit <- stats::qnorm(0.5 * (1.0 + interval))
    rows_df <- if (!C_cells) data.frame() else do.call(rbind, lapply(seq_len(C_cells), function(ci) {
      ns <- cell_rows[[ci]]
      i1 <- idx1[[ns[[1L]]]]; i2 <- idx2[[ns[[1L]]]]
      same_s <- length(unique(sg_pos[ns])) == 1L
      o_sum <- sum(y_obs[ns]); e_sum <- sum(exp_row[ns]); v_sum <- sum(var_row[ns])
      d_sum <- o_sum - e_sum
      has_v <- is.finite(v_sum) && v_sum > 1e-14
      b_est <- if (has_v) -d_sum / v_sum else NA_real_
      b_se <- if (has_v) 1.0 / sqrt(v_sum) else NA_real_
      z_res <- if (has_v) d_sum / sqrt(v_sum) else NA_real_

      j_val <- NA_real_; j_se <- NA_real_
      if (!is.null(loc_int_term)) {
        bi1 <- if (loc_flipped) i2 else i1; bi2 <- if (loc_flipped) i1 else i2
        p1 <- match(bi1, as.integer(unlist(loc_int_term$levels[[1L]])))
        p2 <- match(bi2, as.integer(unlist(loc_int_term$levels[[2L]])))
        pn <- loc_int_term$parameters[[(p1 - 1L) * length(loc_int_term$levels[[2L]]) + p2]]
        if (is.null(pn)) {
          j_val <- 0.0
        } else {
          j_val <- vals_map[[as.character(pn)]]
          if (!is.null(object$estimates) && nrow(object$estimates)) {
            mix <- match(as.character(pn), object$estimates$variable)
            if (!is.na(mix)) j_se <- as.double(object$estimates$se[[mix]])
          }
        }
      }

      data.frame(
        role_1 = r1, level_1 = levs1[[i1]],
        role_2 = r2, level_2 = levs2[[i2]],
        n_observations = length(ns),
        observed_score_mean = if (same_s) o_sum / length(ns) else NA_real_,
        expected_score_mean = if (same_s) e_sum / length(ns) else NA_real_,
        score_residual = if (same_s) d_sum / length(ns) else NA_real_,
        approx_severity_bias_logit = b_est,
        approx_severity_bias_se = b_se,
        approx_severity_bias_lower = if (has_v) b_est - z_crit * b_se else NA_real_,
        approx_severity_bias_upper = if (has_v) b_est + z_crit * b_se else NA_real_,
        z_residual = z_res,
        p_value = if (has_v) 2.0 * stats::pnorm(-abs(z_res)) else NA_real_,
        joint_interaction_logit = j_val,
        joint_interaction_se = j_se,
        stringsAsFactors = FALSE
      )
    }))
    return(list(
      schema = "bayesianmgmfrm.r_pair_bias.v1",
      inference_paradigm = "frequentist",
      method = as.character(b$frequentist$method),
      analysis_mode = analysis_mode,
      pair = c(r1, r2),
      min_obs = min_obs,
      interval = interval,
      rows = rows_df,
      qualification = object$metadata$qualification
    ))
  }

  if (is.null(object$draws) || !identical(object$method, "nuts"))
    stop("Joint Bayesian draws are missing.")
  arr <- as.array(object$draws); dims <- dim(arr)
  values <- matrix(arr, nrow = dims[[1L]] * dims[[2L]], ncol = dims[[3L]])
  colnames(values) <- dimnames(arr)[[3L]]
  S <- nrow(values)

  p_pars <- vapply(b$people, function(p) as.character(p$parameter), character(1L))
  int_pars <- if (length(b$interactions)) unlist(lapply(b$interactions, function(t) unlist(t$parameters))) else character(0L)
  req <- unique(c(p_pars, unlist(lapply(b$facets, function(x) x$parameters)),
                  unlist(lapply(b$steps, function(x) x$parameters)), b$intercept, int_pars))
  if (!all(req %in% colnames(values)))
    stop("pair_bias requires all person, facet, step, and interaction draws; refit without a variables subset.")

  mu_int <- if (is.null(b$intercept)) rep(0.0, S) else values[, as.character(b$intercept)]
  eta_mat <- values[, p_pars[p_idx], drop = FALSE] + mu_int
  for (k in seq_along(b$facets)) {
    fb <- b$facets[[k]]
    fn <- b_f_roles[[k]]
    lv_pos <- match(pb_facets[[fn]], as.integer(unlist(fb$levels)))
    eta_mat <- eta_mat - values[, unlist(fb$parameters)[lv_pos], drop = FALSE]
  }
  if (length(b$interactions)) {
    for (tm in b$interactions) {
      if (identical(tm$kind, "location")) {
        tr1 <- as.character(tm$roles[[1L]]); tr2 <- as.character(tm$roles[[2L]])
        p1 <- match(pb_facets[[tr1]], as.integer(unlist(tm$levels[[1L]])))
        p2 <- match(pb_facets[[tr2]], as.integer(unlist(tm$levels[[2L]])))
        L2 <- length(tm$levels[[2L]])
        for (n in seq_len(N)) {
          pn <- tm$parameters[[(p1[[n]] - 1L) * L2 + p2[[n]]]]
          if (!is.null(pn)) eta_mat[, n] <- eta_mat[, n] - values[, as.character(pn)]
        }
      }
    }
  }

  exp_mat <- matrix(0.0, nrow = S, ncol = N)
  var_mat <- matrix(0.0, nrow = S, ncol = N)
  for (g in seq_along(b$steps)) {
    ns_g <- which(sg_pos == g)
    if (!length(ns_g)) next
    cats <- step_cats[[g]]
    K <- length(cats)
    tau_g <- values[, unlist(b$steps[[g]]$parameters), drop = FALSE]
    tau_cum_base <- matrix(0.0, nrow = S, ncol = K)
    for (k in 2:K) tau_cum_base[, k] <- tau_cum_base[, k - 1L] + tau_g[, k - 1L]
    for (n in ns_g) {
      tau_cum_n <- tau_cum_base
      if (length(b$interactions)) {
        for (tm in b$interactions) {
          if (identical(tm$kind, "steps")) {
            tr1 <- as.character(tm$roles[[1L]])
            p1 <- match(pb_facets[[tr1]][[n]], as.integer(unlist(tm$levels[[1L]])))
            H_i <- as.integer(tm$n_steps)
            sp <- unlist(tm$parameters)[((p1 - 1L) * H_i + 1L):(p1 * H_i)]
            for (h in seq_len(H_i)) {
              for (k in (h + 1L):K) tau_cum_n[, k] <- tau_cum_n[, k] + values[, sp[[h]]]
            }
          }
        }
      }
      z <- outer(eta_mat[, n], seq_len(K) - 1.0) - tau_cum_n
      w <- exp(z - apply(z, 1L, max))
      pr <- w / rowSums(w)
      er <- drop(pr %*% cats)
      exp_mat[, n] <- er
      var_mat[, n] <- rowSums(pr * outer(er, cats, function(a, cc) (cc - a)^2))
    }
  }

  probs <- c((1.0 - interval) / 2.0, (1.0 + interval) / 2.0)
  mcse_ok <- dims[[2L]] >= 2L && dims[[1L]] >= 10L
  rows_df <- if (!C_cells) data.frame() else do.call(rbind, lapply(seq_len(C_cells), function(ci) {
    ns <- cell_rows[[ci]]
    i1 <- idx1[[ns[[1L]]]]; i2 <- idx2[[ns[[1L]]]]
    same_s <- length(unique(sg_pos[ns])) == 1L
    o_sum <- sum(y_obs[ns])
    e_sum_s <- rowSums(exp_mat[, ns, drop = FALSE])
    v_sum_s <- rowSums(var_mat[, ns, drop = FALSE])
    d_sum_s <- o_sum - e_sum_s
    valid_b <- all(is.finite(v_sum_s) & v_sum_s > 1e-14)
    bv <- if (valid_b) -d_sum_s / v_sum_s else rep(NA_real_, S)
    zv <- if (valid_b) d_sum_s / sqrt(v_sum_s) else rep(NA_real_, S)
    rv <- if (same_s) (o_sum / length(ns)) - (e_sum_s / length(ns)) else rep(NA_real_, S)
    bq <- if (valid_b) stats::quantile(bv, probs, names = FALSE) else c(NA_real_, NA_real_)
    b_mcse <- if (valid_b && mcse_ok && length(unique(bv)) > 1L) posterior::mcse_mean(matrix(bv, dims[[1L]], dims[[2L]])) else NA_real_

    j_mean <- NA_real_; j_lo <- NA_real_; j_hi <- NA_real_
    if (!is.null(loc_int_term)) {
      bi1 <- if (loc_flipped) i2 else i1; bi2 <- if (loc_flipped) i1 else i2
      p1 <- match(bi1, as.integer(unlist(loc_int_term$levels[[1L]])))
      p2 <- match(bi2, as.integer(unlist(loc_int_term$levels[[2L]])))
      pn <- loc_int_term$parameters[[(p1 - 1L) * length(loc_int_term$levels[[2L]]) + p2]]
      if (is.null(pn)) {
        j_mean <- 0.0; j_lo <- 0.0; j_hi <- 0.0
      } else {
        jv <- values[, as.character(pn)]
        jq <- stats::quantile(jv, probs, names = FALSE)
        j_mean <- mean(jv); j_lo <- jq[[1L]]; j_hi <- jq[[2L]]
      }
    }

    data.frame(
      role_1 = r1, level_1 = levs1[[i1]],
      role_2 = r2, level_2 = levs2[[i2]],
      n_observations = length(ns),
      observed_score_mean = if (same_s) o_sum / length(ns) else NA_real_,
      expected_score_mean = if (same_s) mean(e_sum_s) / length(ns) else NA_real_,
      score_residual_mean = if (same_s) mean(rv) else NA_real_,
      approx_severity_bias_logit_mean = if (valid_b) mean(bv) else NA_real_,
      approx_severity_bias_logit_sd = if (valid_b) stats::sd(bv) else NA_real_,
      approx_severity_bias_logit_lower = bq[[1L]],
      approx_severity_bias_logit_upper = bq[[2L]],
      approx_severity_bias_logit_mcse = b_mcse,
      z_residual_mean = if (valid_b) mean(zv) else NA_real_,
      prob_score_residual_gt_0 = if (same_s) mean(rv > 0) else if (valid_b) mean(zv > 0) else NA_real_,
      prob_score_residual_lt_0 = if (same_s) mean(rv < 0) else if (valid_b) mean(zv < 0) else NA_real_,
      joint_interaction_logit_mean = j_mean,
      joint_interaction_logit_lower = j_lo,
      joint_interaction_logit_upper = j_hi,
      stringsAsFactors = FALSE
    )
  }))

  list(
    schema = "bayesianmgmfrm.r_pair_bias.v1",
    inference_paradigm = "bayesian",
    method = "nuts",
    analysis_mode = analysis_mode,
    pair = c(r1, r2),
    min_obs = min_obs,
    interval = interval,
    n_draws = S,
    rows = rows_df,
    qualification = object$metadata$qualification
  )
}

.resolve_cohort_draws_mgmfrm <- function(object, facet = "person", dimension = NULL, parameters = NULL, location = "parameter") {
  if (is.null(object$draws))
    stop("Joint Bayesian draws are missing.")
  arr <- as.array(object$draws); dims <- dim(arr)
  all_vars <- dimnames(arr)[[3L]]
  step_own <- if (!is.null(object$steps) && nzchar(as.character(object$steps))) as.character(object$steps) else "item"
  lbls <- if (!is.null(object$parameter_labels) && length(object$parameter_labels)) {
    out_lbl <- object$parameter_labels
    miss_vars <- setdiff(all_vars, names(out_lbl))
    if (length(miss_vars) && is.list(object$ids) && length(object$ids)) {
      out_lbl <- c(out_lbl, .label_mgmfrm_parameters(miss_vars, object$ids, step_owner = step_own))
    }
    out_lbl
  } else if (is.list(object$ids) && length(object$ids)) {
    .label_mgmfrm_parameters(all_vars, object$ids, step_owner = step_own)
  } else setNames(all_vars, all_vars)
  fixed_names <- names(.mgmfrm_fixed_param_lookup(object))

  if (!is.null(parameters)) {
    if (!is.character(parameters) || !length(parameters) || anyNA(parameters) || any(!nzchar(parameters)) || anyDuplicated(parameters))
      stop("parameters must be a character vector of distinct nonempty coordinate names.")
    sel_vars <- character(length(parameters))
    for (k in seq_along(parameters)) {
      pk <- parameters[[k]]
      if (pk %in% all_vars) sel_vars[[k]] <- pk
      else {
        m_lbl <- which(unname(lbls) == pk)
        if (length(m_lbl) == 1L && names(lbls)[[m_lbl]] %in% all_vars) sel_vars[[k]] <- names(lbls)[[m_lbl]]
        else stop("Unknown coordinate '", pk, "' in saved draws.")
      }
    }
  } else {
    if (!is.character(facet) || length(facet) != 1L || !nzchar(facet))
      stop("facet must be a single facet name.")
    if (identical(facet, "entity")) facet <- "person"
    esc_f <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", facet)
    cand <- grep(paste0("^", esc_f, "\\["), all_vars, value = TRUE, perl = TRUE)
    if (!length(cand) && identical(facet, "criterion"))
      cand <- grep("^item\\[", all_vars, value = TRUE, perl = TRUE)
    if (!length(cand))
      stop("No saved draw coordinates found for facet '", facet, "'.")

    # Distinguish multi-dimensional coordinates such as person[p, dim=1]
    has_dim_tag <- any(grepl(",[[:space:]]*dim=[0-9]+\\]$", cand, perl = TRUE))
    if (has_dim_tag) {
      dim_ids <- if (!is.null(object$ids$dimension)) as.character(object$ids$dimension) else character(0L)
      d_idx <- if (is.null(dimension)) {
        1L
      } else if (is.numeric(dimension) && length(dimension) == 1L && is.finite(dimension) && dimension == trunc(dimension)) {
        as.integer(dimension)
      } else if (is.character(dimension) && length(dimension) == 1L && length(dim_ids)) {
        m_d <- match(dimension, dim_ids)
        if (is.na(m_d)) stop("Unknown dimension '", dimension, "'; available: ", paste(dim_ids, collapse = ", "), ".")
        m_d
      } else stop("dimension must be a single integer index or dimension label.")
      cand <- grep(paste0(",[[:space:]]*dim=", d_idx, "\\]$"), cand, value = TRUE, perl = TRUE)
      if (!length(cand))
        stop("No saved coordinates found for facet '", facet, "' on dimension ", d_idx, ".")
    } else if (!is.null(dimension) && !identical(as.integer(dimension), 1L)) {
      stop("Facet '", facet, "' is one-dimensional; omit dimension or pass dimension = 1L.")
    }
    sel_vars <- cand
  }

  if (any(sel_vars %in% fixed_names))
    stop("Fixed anchor parameters have zero uncertainty and cannot be included in posterior classification or ranking.")

  mat <- matrix(arr[, , sel_vars, drop = FALSE], nrow = dims[[1L]] * dims[[2L]], ncol = length(sel_vars))
  colnames(mat) <- sel_vars
  if (any(!is.finite(mat)))
    stop("Non-finite posterior draws encountered.")

  if (identical(location, "linked")) {
    if (!is.null(parameters) || !identical(facet, "person"))
      stop("location = 'linked' applies to facet = 'person' without custom parameters.")
    if (!("population_mean" %in% all_vars))
      stop("location = 'linked' requires 'population_mean' in saved draws.")
    pm <- as.double(arr[, , "population_mean"])
    mat <- mat + pm
  }

  disp_labels <- unname(lbls[sel_vars])
  bad_na <- is.na(disp_labels)
  if (any(bad_na)) disp_labels[bad_na] <- sel_vars[bad_na]
  levels_clean <- sub("^[^\\[]+\\[(.*)\\]$", "\\1", disp_labels, perl = TRUE)
  if (is.null(parameters)) {
    levels_clean <- sub(",[[:space:]]*dim=[0-9]+$", "", levels_clean, perl = TRUE)
  }
  levels_clean <- sub('^"(.*)"$', "\\1", levels_clean, perl = TRUE)

  list(
    variables = sel_vars,
    labels = disp_labels,
    levels = levels_clean,
    values = mat,
    iterations = dims[[1L]],
    chains = dims[[2L]]
  )
}

.event_mean_mcse <- function(ind_vec, iterations, chains, structural_fixed = FALSE) {
  m <- mean(ind_vec)
  if (isTRUE(structural_fixed)) {
    return(list(mean = m, mcse = 0.0, status = "structural_zero"))
  }
  if (chains < 2L) return(list(mean = m, mcse = NA_real_, status = "insufficient_chains"))
  if (iterations < 10L) return(list(mean = m, mcse = NA_real_, status = "insufficient_draws"))
  if (length(unique(ind_vec)) <= 1L) return(list(mean = m, mcse = NA_real_, status = "degenerate_draws"))
  mc <- suppressWarnings(posterior::mcse_mean(matrix(as.double(ind_vec), nrow = iterations, ncol = chains)))
  if (!is.finite(mc)) return(list(mean = m, mcse = NA_real_, status = "mcse_unavailable"))
  list(mean = m, mcse = as.double(mc), status = "available")
}

.classification_mgmfrm <- function(object, cutoff, pass_probability = 0.5, facet = "person",
                                   dimension = NULL, parameters = NULL, interval = 0.90, location = "parameter") {
  if (!is.numeric(cutoff) || length(cutoff) != 1L || !is.finite(cutoff))
    stop("cutoff must be a single finite number.")
  if (!is.numeric(pass_probability) || length(pass_probability) != 1L || !is.finite(pass_probability) ||
      pass_probability <= 0 || pass_probability >= 1)
    stop("pass_probability must lie strictly in (0, 1).")
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must lie strictly in (0, 1).")

  # Conditional empirical-Bayes quadrature classification for MMLE person abilities
  b <- object$metadata$fair_reference_basis
  if (is.null(object$draws) && !is.null(b$frequentist) && identical(as.character(b$frequentist$method), "mmle")) {
    if (!is.null(parameters) || !identical(facet, "person") || !identical(location, "parameter") || !is.null(dimension))
      stop("Frequentist MMLE classification supports person conditional quadrature on location = 'parameter' only.")
    post_list <- b$frequentist$posterior
    if (is.null(post_list) || !length(post_list))
      stop("Saved MMLE quadrature posterior is unavailable.")
    P <- length(post_list)
    p_labels <- if (!is.null(object$ids$person)) {
      as.character(object$ids$person[vapply(b$people, function(p) as.integer(p$level), integer(1L))])
    } else as.character(seq_len(P))
    probs <- c((1.0 - interval) / 2.0, (1.0 + interval) / 2.0)

    rows_list <- lapply(seq_len(P), function(i) {
      nd <- as.double(unlist(post_list[[i]]$nodes))
      wt <- as.double(unlist(post_list[[i]]$weights))
      wt <- wt / sum(wt)
      ord_nd <- order(nd)
      cdf_w <- cumsum(wt[ord_nd]); cdf_w[[length(cdf_w)]] <- 1.0
      w_mean <- sum(nd * wt)
      w_sd <- sqrt(max(0.0, sum(wt * (nd - w_mean)^2)))
      w_lo <- nd[[ord_nd[[which(cdf_w >= probs[[1L]])[[1L]]]]]]
      w_hi <- nd[[ord_nd[[which(cdf_w >= probs[[2L]])[[1L]]]]]]
      q_i <- .quadrature_event_probability(wt, nd >= cutoff)
      pass_i <- q_i >= pass_probability
      err_i <- if (pass_i) (1.0 - q_i) else q_i
      data.frame(
        parameter = as.character(b$people[[i]]$parameter),
        level = p_labels[[i]],
        mean = w_mean,
        sd = w_sd,
        lower = w_lo,
        upper = w_hi,
        qualifying_probability = q_i,
        qualifying_mcse = NA_real_,
        decision = if (pass_i) "pass" else "fail",
        error_probability = err_i,
        error_mcse = NA_real_,
        stringsAsFactors = FALSE
      )
    })
    rows_df <- do.call(rbind, rows_list)
    is_pass <- rows_df$decision == "pass"
    cohort <- list(
      n_people = P,
      n_pass = sum(is_pass),
      n_fail = sum(!is_pass),
      expected_false_pass = sum(rows_df$error_probability[is_pass]),
      expected_false_fail = sum(rows_df$error_probability[!is_pass]),
      expected_total_errors = sum(rows_df$error_probability),
      any_error_probability = 1.0 - prod(pmax(0.0, 1.0 - rows_df$error_probability))
    )
    return(list(
      schema = "bayesianmgmfrm.r_classification.v1",
      method = "conditional_empirical_bayes_quadrature",
      cutoff = as.double(cutoff),
      pass_probability = as.double(pass_probability),
      interval = as.double(interval),
      rows = rows_df,
      cohort = cohort,
      qualification = object$metadata$qualification,
      warnings = c(
        unlist(object$metadata$warnings),
        "Conditional empirical-Bayes classification holds fitted calibration and population parameters fixed; it omits calibration-estimation uncertainty."
      )
    ))
  }
  if (is.null(object$draws))
    stop("Classification requires Bayesian joint posterior draws or a grouped/unconstrained MMLE quadrature fit (JMLE point estimates do not define posterior qualification probabilities).")

  sel <- .resolve_cohort_draws_mgmfrm(object, facet = facet, dimension = dimension, parameters = parameters, location = location)
  mat <- sel$values
  N <- ncol(mat)
  probs <- c((1.0 - interval) / 2.0, (1.0 + interval) / 2.0)

  qualifies <- mat >= cutoff
  q_means <- colMeans(qualifies)
  pass_vec <- q_means >= pass_probability

  rows_list <- lapply(seq_len(N), function(i) {
    v <- mat[, i]
    qi_ind <- as.double(qualifies[, i])
    q_st <- .event_mean_mcse(qi_ind, sel$iterations, sel$chains)
    err_ind <- if (pass_vec[[i]]) (1.0 - qi_ind) else qi_ind
    e_st <- .event_mean_mcse(err_ind, sel$iterations, sel$chains)
    vq <- stats::quantile(v, probs, names = FALSE)
    data.frame(
      parameter = sel$variables[[i]],
      level = sel$levels[[i]],
      mean = mean(v),
      sd = stats::sd(v),
      lower = vq[[1L]],
      upper = vq[[2L]],
      qualifying_probability = q_st$mean,
      qualifying_mcse = q_st$mcse,
      decision = if (pass_vec[[i]]) "pass" else "fail",
      error_probability = e_st$mean,
      error_mcse = e_st$mcse,
      stringsAsFactors = FALSE
    )
  })
  rows_df <- do.call(rbind, rows_list)

  fp_draws <- if (any(pass_vec)) rowSums(!qualifies[, pass_vec, drop = FALSE]) else rep(0.0, nrow(mat))
  ff_draws <- if (any(!pass_vec)) rowSums(qualifies[, !pass_vec, drop = FALSE]) else rep(0.0, nrow(mat))
  tot_err_draws <- fp_draws + ff_draws
  any_err_draws <- as.double(tot_err_draws > 0)

  fp_st <- .event_mean_mcse(fp_draws, sel$iterations, sel$chains, structural_fixed = !any(pass_vec))
  ff_st <- .event_mean_mcse(ff_draws, sel$iterations, sel$chains, structural_fixed = !any(!pass_vec))
  tot_st <- .event_mean_mcse(tot_err_draws, sel$iterations, sel$chains, structural_fixed = N == 0L)
  any_st <- .event_mean_mcse(any_err_draws, sel$iterations, sel$chains, structural_fixed = N == 0L)

  list(
    schema = "bayesianmgmfrm.r_classification.v1",
    method = "joint_posterior",
    location = location,
    cutoff = as.double(cutoff),
    pass_probability = as.double(pass_probability),
    interval = as.double(interval),
    n_draws = nrow(mat),
    rows = rows_df,
    cohort = list(
      n_people = N,
      n_pass = sum(pass_vec),
      n_fail = sum(!pass_vec),
      expected_false_pass = fp_st$mean,
      expected_false_pass_mcse = fp_st$mcse,
      expected_false_fail = ff_st$mean,
      expected_false_fail_mcse = ff_st$mcse,
      expected_total_errors = tot_st$mean,
      expected_total_errors_mcse = tot_st$mcse,
      any_error_probability = any_st$mean,
      any_error_mcse = any_st$mcse
    ),
    qualification = object$metadata$qualification
  )
}

.ranking_mgmfrm <- function(object, direction = "higher", top_k = NULL, facet = "person",
                            dimension = NULL, parameters = NULL, interval = 0.90) {
  if (is.null(object$draws))
    stop("Posterior ranking requires joint posterior draws (fit with method = 'nuts' or load a Bayesian handoff).")
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must lie strictly in (0, 1).")

  sel <- .resolve_cohort_draws_mgmfrm(object, facet = facet, dimension = dimension, parameters = parameters, location = "parameter")
  mat <- sel$values
  S <- nrow(mat); N <- ncol(mat)
  if (N < 2L)
    stop("Posterior ranking requires at least two cohort members.")
  if (!is.null(top_k)) {
    if (!is.numeric(top_k) || length(top_k) != 1L || !is.finite(top_k) || top_k != trunc(top_k) || top_k < 1 || top_k > N)
      stop("top_k must be an integer between 1 and ", N, ".")
    top_k <- as.integer(top_k)
  }

  ranks <- matrix(0.0, nrow = S, ncol = N)
  tied <- matrix(FALSE, nrow = S, ncol = N)
  certain <- if (!is.null(top_k)) matrix(FALSE, nrow = S, ncol = N) else NULL
  possible <- if (!is.null(top_k)) matrix(FALSE, nrow = S, ncol = N) else NULL
  dec <- identical(direction, "higher")

  for (s in seq_len(S)) {
    v_s <- mat[s, ]
    ord <- order(v_s, decreasing = dec)
    first_pos <- 1L
    while (first_pos <= N) {
      last_pos <- first_pos
      while (last_pos < N && v_s[[ord[[last_pos + 1L]]]] == v_s[[ord[[first_pos]]]]) {
        last_pos <- last_pos + 1L
      }
      mid_r <- 0.5 * (first_pos + last_pos)
      is_t <- last_pos > first_pos
      idx_grp <- ord[first_pos:last_pos]
      ranks[s, idx_grp] <- mid_r
      tied[s, idx_grp] <- is_t
      if (!is.null(top_k)) {
        certain[s, idx_grp] <- (last_pos <= top_k)
        possible[s, idx_grp] <- (first_pos <= top_k)
      }
      first_pos <- last_pos + 1L
    }
  }

  lo_p <- 0.5 * (1.0 - interval)
  hi_p <- 0.5 * (1.0 + interval)
  emp_q <- function(sorted_v, p) {
    idx <- max(1L, min(length(sorted_v), as.integer(ceiling(p * length(sorted_v)))))
    sorted_v[[idx]]
  }

  rows_list <- lapply(seq_len(N), function(i) {
    rv <- ranks[, i]
    sv <- sort(rv)
    m_st <- .event_mean_mcse(rv, sel$iterations, sel$chains)
    base_df <- data.frame(
      parameter = sel$variables[[i]],
      level = sel$levels[[i]],
      mean = m_st$mean,
      mcse_mean = m_st$mcse,
      sd = if (S > 1L) stats::sd(rv) else NA_real_,
      median = emp_q(sv, 0.5),
      lower = emp_q(sv, lo_p),
      upper = emp_q(sv, hi_p),
      tie_probability = mean(tied[, i]),
      stringsAsFactors = FALSE
    )
    if (is.null(top_k)) return(base_df)
    if (top_k == N) {
      tk_df <- data.frame(
        top_k_lower = 1.0, top_k_lower_mcse = 0.0,
        top_k_upper = 1.0, top_k_upper_mcse = 0.0,
        boundary_tie_probability = 0.0, boundary_tie_mcse = 0.0,
        stringsAsFactors = FALSE
      )
    } else {
      c_v <- as.double(certain[, i])
      p_v <- as.double(possible[, i])
      c_st <- .event_mean_mcse(c_v, sel$iterations, sel$chains)
      p_st <- .event_mean_mcse(p_v, sel$iterations, sel$chains)
      b_st <- .event_mean_mcse(p_v - c_v, sel$iterations, sel$chains)
      tk_df <- data.frame(
        top_k_lower = c_st$mean, top_k_lower_mcse = c_st$mcse,
        top_k_upper = p_st$mean, top_k_upper_mcse = p_st$mcse,
        boundary_tie_probability = b_st$mean, boundary_tie_mcse = b_st$mcse,
        stringsAsFactors = FALSE
      )
    }
    cbind(base_df, tk_df)
  })

  list(
    schema = "bayesianmgmfrm.r_ranking.v1",
    direction = direction,
    top_k = top_k,
    interval = as.double(interval),
    n_levels = N,
    n_draws = S,
    interval_method = "equal_tailed_empirical_inverse_cdf",
    rows = do.call(rbind, rows_list),
    qualification = object$metadata$qualification
  )
}
