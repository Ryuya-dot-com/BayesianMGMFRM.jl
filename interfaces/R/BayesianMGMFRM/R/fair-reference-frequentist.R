.quadrature_event_probability <- function(weights, selected) {
  event_mass <- sum(weights[selected])
  other_mass <- sum(weights[!selected])
  event_mass / (event_mass + other_mass)
}

.fair_reference_frequentist <- function(object, b, plan, indices, groups, w, cats, interval, threshold, comparisons, interaction_effects, conditioning) {
  d <- b$frequentist; jmle <- identical(d$method, "jmle")
  if (jmle && !is.null(threshold)) stop("JMLE confidence intervals do not define posterior threshold probabilities.")
  number <- function(x) if (is.null(x)) NA_real_ else as.double(x)
  vector <- function(x) vapply(x, number, double(1))
  matrix_rows <- function(x) do.call(rbind, lapply(x, vector))
  x <- vector(d$values); names(x) <- unlist(d$parameters)
  P <- length(b$people)
  point <- function(p, theta = x[p]) {
    g <- numeric(length(x)); names(g) <- names(x); value <- 0
    if (!is.finite(theta)) return(list(value = if (is.infinite(theta)) if (theta > 0) max(cats) else min(cats) else NA_real_, gradient = g*NA_real_))
    for (j in seq_len(nrow(plan))) {
      fs <- vapply(seq_along(b$facets), function(k) unlist(b$facets[[k]]$parameters)[indices[[k]][j]], character(1))
      ts <- unlist(b$steps[[groups[j]]]$parameters)
      signs <- vapply(b$facets, function(fb) if (is.null(fb$sign)) -1 else fb$sign, double(1))
      adjustment <- conditioning$adjustments[[p]][[j]]
      if (!is.null(adjustment)) {
        fs <- c(fs, adjustment$location); signs <- c(signs, rep(-1, length(adjustment$location)))
      }
      tau <- x[ts]
      if (!is.null(adjustment)) for (h in seq_along(ts)) tau[h] <- tau[h] + sum(x[adjustment$steps[[h]]])
      loc <- theta + if (is.null(b$intercept)) 0 else x[b$intercept]
      loc <- loc + sum(signs*x[fs]); z <- c(0, cumsum(loc-tau))
      pr <- exp(z-max(z)); pr <- pr/sum(pr); e <- sum(pr*cats)
      centered <- cats-e; dl <- sum(pr*centered*(seq_along(cats)-1L))*w[j]
      value <- value+w[j]*e; g[p] <- g[p]+dl
      if (!is.null(b$intercept)) g[b$intercept] <- g[b$intercept]+dl
      g[fs] <- g[fs]+signs*dl
      for (h in seq_along(ts)) {
        dt <- -w[j]*sum((pr*centered)[(h+1L):length(cats)])
        g[ts[h]] <- g[ts[h]] + dt
        if (!is.null(adjustment)) g[adjustment$steps[[h]]] <- g[adjustment$steps[[h]]] + dt
      }
    }
    list(value = unname(value), gradient = unname(g))
  }
  v <- lapply(seq_len(P), point)
  if (jmle) {
    fullcov <- !is.null(d$delta$full_covariance)
    if (fullcov) {
      V <- matrix_rows(d$delta$full_covariance)
      gamma <- lapply(v, function(x) x$gradient)
      variance <- vapply(gamma, function(g) sum(g*(V %*% g)), double(1))
    } else {
    V <- matrix_rows(d$delta$structural_covariance)
    if (is.null(V)) V <- matrix(numeric(), 0L, 0L)
    J <- matrix_rows(d$delta$model_map); H <- matrix_rows(d$delta$projection)
    invD <- vector(d$delta$inverse_information)
    gamma <- lapply(seq_len(P), function(p) drop(crossprod(J, v[[p]]$gradient[-seq_len(P)]))-H[p, ]*v[[p]]$gradient[p])
    variance <- vapply(seq_len(P), function(p) v[[p]]$gradient[p]^2*invD[p]+sum(gamma[[p]]*(V %*% gamma[[p]])), double(1))
    }
  } else scores <- lapply(seq_len(P), function(p) vapply(vector(d$posterior[[p]]$nodes), function(theta) point(p, theta)$value, double(1)))
  wald <- function(m, variance) {
    se <- if (is.finite(variance) && variance >= 0) sqrt(variance) else NA_real_
    z <- stats::qnorm((1+interval)/2)
    data.frame(mean = m, median = m, sd = se, lower = m-z*se, upper = m+z*se)
  }
  weighted <- function(values, weights, threshold = NULL, strict = FALSE) {
    ix <- order(values); cdf <- cumsum(weights[ix]); cdf[length(cdf)] <- 1
    quantile <- function(a) values[ix[which(cdf >= a)[1L]]]
    m <- sum(values*weights)
    out <- data.frame(mean = m, median = quantile(.5), sd = sqrt(max(0, sum(weights*(values-m)^2))),
      lower = quantile((1-interval)/2), upper = quantile((1+interval)/2))
    if (!is.null(threshold)) {
      if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold)) stop("threshold/margin must be finite.")
      out$threshold <- threshold; out$operator <- if (strict) "greater" else "greater_equal"
      selected <- if (strict) values > threshold else values >= threshold
      out$probability <- .quadrature_event_probability(weights, selected)
      out$probability_mcse <- NA_real_; out$probability_status <- "deterministic_quadrature"
    }
    out
  }
  persons <- object$ids$person[vapply(b$people, function(x) as.integer(x$level), integer(1))]
  rows <- do.call(rbind, lapply(seq_len(P), function(p) {
    pb <- b$people[[p]]
    observed <- if (identical(as.double(unlist(pb$observed_categories)), cats)) number(pb$observed_average) else NA_real_
    s <- if (jmle) wald(v[[p]]$value, variance[p]) else weighted(scores[[p]], vector(d$posterior[[p]]$weights), threshold)
    cbind(data.frame(person = persons[p], n_observations = pb$n_observations, observed_average = observed,
      adjustment_mean = s$mean-observed, plugin_mean = v[[p]]$value), s)
  }))
  contrasts <- data.frame()
  if (!is.null(comparisons)) {
    if (!is.data.frame(comparisons) || !nrow(comparisons) || anyDuplicated(names(comparisons)) ||
        !setequal(names(comparisons), c("left", "right", "margin"))) stop("comparisons needs left, right and margin.")
    contrasts <- do.call(rbind, lapply(seq_len(nrow(comparisons)), function(i) {
      c <- comparisons[i, ]; ids <- match(c(c$left, c$right), persons)
      if (anyNA(ids) || ids[1] == ids[2] || !is.numeric(c$margin) || !is.finite(c$margin)) stop("Invalid person comparison.")
      l <- ids[1]; r <- ids[2]
      s <- if (jmle) wald(v[[l]]$value-v[[r]]$value, variance[l]+variance[r]-2*sum(gamma[[l]]*(V %*% gamma[[r]]))) else {
        vv <- as.vector(outer(scores[[l]], scores[[r]], "-"))
        ww <- as.vector(outer(vector(d$posterior[[l]]$weights), vector(d$posterior[[r]]$weights)))
        weighted(vv, ww, c$margin, TRUE)
      }
      cbind(c, s)
    }))
  }
  structure(list(schema = "bayesianmgmfrm.r_fair_reference.v1", target = "common_plan_expected_average",
    interaction_effects = interaction_effects, held_contexts = conditioning$contexts,
    method = d$method, rows = rows, contrasts = contrasts, reference_plan = plan, category_levels = cats,
    interval = interval, interval_target = if (jmle) "wald_expected_score" else "conditional_posterior_expected_score",
    quadrature = d$quadrature, n_draws = 0L, qualification = object$metadata$qualification, source_handoff_hash = object$metadata$handoff_hash,
    warnings = c(unlist(object$metadata$warnings), conditioning$warnings, if (jmle)
      "Wald intervals use joint person/calibration covariance, can exceed the score scale and are unavailable for extreme persons. Fixed anchors are treated as known." else
      "Conditional empirical-Bayes intervals/probabilities hold calibration and population parameters fixed; their estimation uncertainty is omitted.",
      "Intervals describe expected scores, not future realized ratings; whole-fit warnings remain applicable.")), class = "mgmfrm_fair_average")
}
