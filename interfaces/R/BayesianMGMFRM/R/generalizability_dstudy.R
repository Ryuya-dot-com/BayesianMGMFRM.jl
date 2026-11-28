.gtheory_plan <- function(facets, scores, counts, weights, interval) {
  if (!length(counts) || is.null(names(counts)) || anyDuplicated(names(counts)) ||
      !setequal(names(counts), facets)) stop("counts must name every measurement facet.")
  counts <- counts[facets]
  if (!all(vapply(counts, function(x) is.numeric(x) && length(x) > 0L &&
      all(is.finite(x) & x > 0 & x == floor(x) & x <= .Machine$integer.max) && !anyDuplicated(x), logical(1))))
    stop("Each counts grid must contain distinct positive integers.")
  if (!is.numeric(weights) || length(weights) != length(scores) || any(!is.finite(weights)) || !any(weights != 0))
    stop("weights must be a finite nonzero vector in score-column order.")
  if (!is.numeric(interval) || length(interval) != 1L || !is.finite(interval) || interval <= 0 || interval >= 1)
    stop("interval must be between zero and one.")
  do.call(expand.grid, c(counts, KEEP.OUT.ATTRS = FALSE))
}

.gtheory_exact <- function(object, weights, count, interval) {
  m <- object$report$balanced_moments
  if (is.null(m) || length(object$facets) != 1L)
    stop("Exact intervals require stored mean squares from a complete balanced one-facet design.")
  C <- length(weights)
  p <- drop(crossprod(weights, matrix(unlist(m$person_ms), C, C) %*% weights))
  e <- drop(crossprod(weights, matrix(unlist(m$residual_ms), C, C) %*% weights))
  out <- data.frame(lower = rep(NA_real_, 4), upper = NA_real_, status = "not_supported_by_exact")
  if (!is.finite(p) || !is.finite(e) || p < 0 || e <= 0) {
    out$status[c(1L, 3L)] <- "degenerate_mean_squares"
    return(out)
  }
  probs <- c((1 + interval)/2, (1 - interval)/2)
  bounds <- p/e/stats::qf(probs, m$person_df, m$residual_df)
  if (all(is.finite(bounds)) && bounds[2L] >= 1) {
    bounds[1L] <- max(1, bounds[1L])
    limits <- 1/(1 + m$replications/(count*(bounds - 1)))
    out[1L, ] <- list(limits[1L], limits[2L], "exact_f")
  } else out$status[1L] <- if (all(is.finite(bounds))) "empty_confidence_set" else "numeric_range"
  limits <- sqrt(m$residual_df*e/count/stats::qchisq(probs, m$residual_df))
  if (all(is.finite(limits))) out[3L, ] <- list(limits[1L], limits[2L], "exact_chisq")
  else out$status[3L] <- "numeric_range"
  out
}

# Linear component weights carry the full joint sampling covariance into each
# ratio/SEM, including signed cross-score covariance and cross-component terms.
.gtheory_dstudy <- function(object, counts = object$counts, weights = object$weights,
                            interval = object$interval, interval_method = "delta") {
  interval_method <- match.arg(interval_method, c("delta", "exact", "mean_square_region"))
  plan <- .gtheory_plan(names(object$facets), object$scores, counts, weights, interval)
  if (interval_method == "exact" && (length(object$facets) != 1L || is.null(object$report$balanced_moments)))
    stop("Exact intervals require stored mean squares from a complete balanced one-facet design.")
  d <- object$components
  ia <- match(d$score1, object$scores); ib <- match(d$score2, object$scores)
  if (anyNA(ia) || anyNA(ib) || any(!is.finite(d$estimate))) stop("Invalid stored covariance components.")
  terms <- object$report$components
  comp <- vapply(terms, `[[`, character(1), "name")
  index <- match(d$component, comp)
  if (anyNA(index)) stop("Unknown stored covariance component.")
  factors <- lapply(terms, function(x) unlist(x$factors, use.names = FALSE))
  is_person <- vapply(factors, identical, logical(1), "person")
  has_person <- vapply(factors, function(x) "person" %in% x, logical(1))
  V <- vcov(object)
  available <- isTRUE(object$report$diagnostics$qualified) && all(is.finite(V))
  all_weights <- c(list(composite = weights), setNames(lapply(seq_along(object$scores), function(i) as.numeric(seq_along(object$scores) == i)), object$scores))
  regions <- if (interval_method == "mean_square_region") lapply(all_weights, function(w) .gtheory_region(object, w, interval)) else NULL
  rows <- list()
  for (p in seq_len(nrow(plan))) {
    denom <- vapply(factors, function(x) prod(as.numeric(plan[p, setdiff(x, "person"), drop = TRUE])), numeric(1))
    for (label in names(all_weights)) {
      w <- all_weights[[label]]
      coefficient <- w[ia]*w[ib]*ifelse(ia == ib, 1, 2)
      u <- coefficient*is_person[index]
      rel <- coefficient*(has_person & !is_person)[index]/denom[index]
      abs <- coefficient*(!is_person)[index]/denom[index]
      signal <- sum(u*d$estimate); relative <- sum(rel*d$estimate); absolute <- sum(abs*d$estimate)
      if (!all(is.finite(c(signal, relative, absolute))) || min(signal, relative, absolute) < 0 ||
          signal + relative <= 0 || signal + absolute <= 0) stop("Undefined D-study coefficients or invalid stored covariances.")
      values <- c(signal/(signal + relative), signal/(signal + absolute), sqrt(relative), sqrt(absolute))
      J <- rbind((relative*u - signal*rel)/(signal + relative)^2,
                 (absolute*u - signal*abs)/(signal + absolute)^2,
                 rel/(2*sqrt(relative)), abs/(2*sqrt(absolute)))
      uncertainty <- data.frame(se = rep(NA_real_, 4), lower = NA_real_, upper = NA_real_, status = "unavailable")
      if (interval_method == "exact") {
        uncertainty[, c("lower", "upper", "status")] <- .gtheory_exact(object, w, plan[p, 1L], interval)
      } else if (interval_method == "mean_square_region") {
        uncertainty[, c("lower", "upper", "status")] <- .gtheory_region_intervals(regions[[label]],
          (has_person & !is_person)/denom, (!is_person)/denom)
      } else if (available) {
        for (j in 1:4) if (all(is.finite(J[j, ]))) {
          variance <- drop(J[j, , drop = FALSE] %*% V %*% J[j, ])
          if (is.finite(variance) && variance >= 0) {
            se <- sqrt(variance); half <- stats::qnorm((1 + interval)/2)*se
            uncertainty[j, ] <- list(se, values[j] - half, values[j] + half, "asymptotic_delta")
          }
        }
      }
      row <- data.frame(score = label, metric = c("G", "Phi", "relative_sem", "absolute_sem"), stringsAsFactors = FALSE)
      for (facet in names(plan)) row[[paste0("count_", facet)]] <- plan[p, facet]
      rows[[length(rows) + 1L]] <- cbind(row, estimate = values, uncertainty)
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  attr(out, "interval") <- interval
  attr(out, "interval_method") <- interval_method
  attr(out, "qualification") <- object$report$diagnostics
  if (interval_method == "mean_square_region") attr(out, "scope") <- "Simultaneous across future plans and metrics for one fixed score/composite; not across scores or data-selected weights. Complete balanced independent-normal model required."
  out
}
