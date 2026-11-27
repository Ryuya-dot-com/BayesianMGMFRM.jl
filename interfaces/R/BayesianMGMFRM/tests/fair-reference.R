library(BayesianMGMFRM)
ns <- asNamespace("BayesianMGMFRM")
n <- 40L; vars <- c("person[1]", "person[2]", "item[1]", "item[2]", "rater[1]", "rater[2]", "population_mean", "steps[1]", "steps[2]")
x <- array(0, c(20, 2, length(vars)), dimnames = list(NULL, NULL, vars))
for (j in 1:7) x[,,j] <- .6*sin(seq_len(n)*.7+j)
basis <- list(schema = "bayesianmgmfrm.fair_reference_basis.v1", owner = "item", intercept = "population_mean",
  facets = list(list(name="item", levels=1:2, parameters=vars[3:4]), list(name="rater", levels=1:2, parameters=vars[5:6])),
  steps = list(list(level=1L,categories=0:1,parameters="steps[1]"),list(level=2L,categories=0:1,parameters="steps[2]")),
  people = list(list(level=1L,parameter=vars[1],n_observations=4L,observed_average=.5,observed_categories=0:1),
                list(level=2L,parameter=vars[2],n_observations=4L,observed_average=.75,observed_categories=0:1)))
f <- structure(list(draws=posterior::as_draws_array(x),method="nuts",ids=list(person=c("alpha","beta"),item=c("A","B"),rater=c("X","Y")),
  metadata=list(fair_reference_basis=basis,qualification=list(qualified=FALSE),warnings="Retained test warning.")),class="mgmfrm_r_fit")
plan <- data.frame(item=c("A","B"),rater=c("X","Y"),Weight=c(1,3))
comparison <- data.frame(left="alpha",right="beta",margin=.1)
r <- diagnostics_mgmfrm(f,"fair_average",reference_plan=plan,threshold=.5,comparisons=comparison)
mx <- matrix(x,n,length(vars)); colnames(mx) <- vars
expected <- sapply(1:2,function(p) .25*plogis(mx[,p]+mx[,7]-mx[,3]-mx[,5])+.75*plogis(mx[,p]+mx[,7]-mx[,4]-mx[,6]))
stopifnot(max(abs(r$rows$mean-colMeans(expected)))<1e-14,
          max(abs(r$rows$lower-apply(expected,2,quantile,.025)))<1e-14,
          identical(r$rows$person,c("alpha","beta")),
          abs(r$contrasts$sd-sd(expected[,1]-expected[,2]))<1e-14,
          r$contrasts$probability==mean(expected[,1]-expected[,2]>.1),
          all(r$rows$probability==colMeans(expected>=.5)),
          !r$qualification$qualified, "Retained test warning." %in% r$warnings)
path <- tempfile(); saveRDS(f,path); restored <- readRDS(path); unlink(path)
revplan <- plan[2:1, ]; revplan$Weight <- revplan$Weight*1e200
rr <- diagnostics_mgmfrm(restored,"fair_average",reference_plan=revplan,interval=.9)
stopifnot(max(abs(rr$rows$mean-r$rows$mean))<1e-14)
constant <- diagnostics_mgmfrm(f,"fair_average",reference_plan=plan,threshold=-1)
stopifnot(all(constant$rows$probability==1),all(is.na(constant$rows$probability_mcse)))
bad <- f; bad$draws <- posterior::subset_draws(f$draws,variable=vars[-1])
old <- f; old$metadata$fair_reference_basis <- NULL
mix <- f; mix$metadata$fair_reference_basis$steps[[2]]$categories <- 0:2
for (expr in list(
  quote(diagnostics_mgmfrm(f,"fair_average")),
  quote(diagnostics_mgmfrm(old,"fair_average",reference_plan=plan)),
  quote(diagnostics_mgmfrm(bad,"fair_average",reference_plan=plan)),
  quote(diagnostics_mgmfrm(mix,"fair_average",reference_plan=plan)),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=transform(plan,Weight=0))),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=transform(plan,Weight=Inf))),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=transform(plan,item="unknown"))),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=rbind(plan,plan[1,]))),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=plan,comparisons=data.frame(left="alpha",right="alpha",margin=0))),
  quote(diagnostics_mgmfrm(f,"fair_average",reference_plan=plan,threshold=NA_real_)),
  quote(diagnostics_mgmfrm(f,"reliability",reference_plan=plan))))
  stopifnot(inherits(try(eval(expr),silent=TRUE),"try-error"))
path <- tempfile(fileext=".pdf"); grDevices::pdf(path); plot(r); grDevices::dev.off(); unlink(path)
stopifnot(is.null(get(".mgmfrm_session",ns)$runtime))

# A fixed-SD shared event: independent adaptive integration, not the implementation's GH rule.
shared <- f; shared$metadata$fair_reference_basis$shared <- list(list(name="event",sd_parameter=NULL,sd=.7))
zero <- diagnostics_mgmfrm(shared,"fair_average",reference_plan=plan,shared_effects="zero")
marg <- diagnostics_mgmfrm(shared,"fair_average",reference_plan=plan,shared_effects="marginal_new")
oracle <- sapply(1:2,function(p) vapply(seq_len(n),function(s) {
  eta1 <- mx[s,p]+mx[s,7]-mx[s,3]-mx[s,5]
  eta2 <- mx[s,p]+mx[s,7]-mx[s,4]-mx[s,6]
  integrate(function(z) (.25*plogis(eta1+.7*z)+.75*plogis(eta2+.7*z))*dnorm(z),-Inf,Inf,rel.tol=1e-11)$value
},double(1)))
stopifnot(max(abs(zero$rows$mean-r$rows$mean))<1e-14,
          max(abs(marg$rows$mean-colMeans(oracle)))<1e-10,
          marg$integration$max_score_difference<1e-7,
          inherits(try(diagnostics_mgmfrm(shared,"fair_average",reference_plan=plan),silent=TRUE),"try-error"))

# Two independent ability dimensions, criterion loadings and rater consistency.
generalized <- f; gb <- basis; gb$kernel <- "mgmfrm"; gb$intercept <- NULL
gb$people[[1L]]$parameters <- vars[1:2]; gb$people[[2L]]$parameters <- vars[2:1]
gb$active_dims <- list(1L,2L); gb$loadings <- list("loading[1]","loading[2]")
gb$consistency <- c("consistency[1]","consistency[2]");gb$logit_scale <- 1.7;gb$item_slope_scope <- "ability_only"
extra <- array(0,c(20L,2L,4L));extra[,,1L] <- .8;extra[,,2L] <- 1.25;extra[,,3L] <- .9;extra[,,4L] <- 1.1
z <- array(c(x,extra),c(20L,2L,13L),dimnames=list(NULL,NULL,c(vars,unlist(gb$loadings),gb$consistency)))
generalized$draws <- posterior::as_draws_array(z);generalized$metadata$fair_reference_basis <- gb
gr <- diagnostics_mgmfrm(generalized,"fair_average",reference_plan=plan)
gexpected <- sapply(1:2,function(p) .25*plogis(1.7*.9*(.8*mx[,p]-mx[,3]-mx[,5]))+.75*plogis(1.7*1.1*(1.25*mx[,3-p]-mx[,4]-mx[,6])))
stopifnot(max(abs(gr$rows$mean-colMeans(gexpected)))<1e-14)
gb$item_slope_scope <- "entire_linear_predictor";gb$active_dims <- list(1L,1L)
generalized$metadata$fair_reference_basis <- gb
gm <- diagnostics_mgmfrm(generalized,"fair_average",reference_plan=plan)
gexpected <- sapply(1:2,function(p) .25*plogis(1.7*.9*.8*(mx[,p]-mx[,3]-mx[,5]))+.75*plogis(1.7*1.1*1.25*(mx[,p]-mx[,4]-mx[,6])))
stopifnot(max(abs(gm$rows$mean-colMeans(gexpected)))<1e-14)
# Ability-only rater slope and smooth bottleneck softmin cross-loading aggregation
gb$item_slope_scope <- "ability_only";gb$rater_slope_scope <- "ability_only"
gb$aggregation <- "softmin";gb$cross_loading_average <- TRUE;gb$softmin_kappa <- "softmin_kappa"
gb$active_dims <- list(1L,c(1L,2L));gb$loadings <- list("loading[1]",c("loading[1]","loading[2]"))
z_sm <- array(c(z,rep(2.5,n)),c(20L,2L,14L),dimnames=list(NULL,NULL,c(dimnames(z)[[3L]],"softmin_kappa")))
generalized$draws <- posterior::as_draws_array(z_sm);generalized$metadata$fair_reference_basis <- gb
gsm <- diagnostics_mgmfrm(generalized,"fair_average",reference_plan=plan)
u2_fn <- function(th1,th2) -(log(.5*(exp(-2.5*.8*th1)+exp(-2.5*1.25*th2))))/2.5
gexpected_sm <- sapply(1:2,function(p) {
  th1 <- if (p==1L) mx[,1] else mx[,2]; th2 <- if (p==1L) mx[,2] else mx[,1]
  .25*plogis(1.7*(.9*(.8*th1)-mx[,3]-mx[,5]))+.75*plogis(1.7*(1.1*u2_fn(th1,th2)-mx[,4]-mx[,6]))
})
stopifnot(max(abs(gsm$rows$mean-colMeans(gexpected_sm)))<1e-14)


# Joint-Wald arithmetic with a known covariance, then conditional quadrature.
frequentist <- f; frequentist$draws <- NULL; frequentist$method <- "jmle"
fb <- basis; point_values <- c(.3,.7,.1,-.1,.2,-.2,0,0,0)
V <- diag(c(.25,.36,rep(0,7L)));V[1,2] <- V[2,1] <- .1
fb$frequentist <- list(method="jmle",parameters=vars,values=as.list(point_values),
  delta=list(full_covariance=lapply(seq_len(nrow(V)),function(j) as.list(V[j,]))))
frequentist$metadata$fair_reference_basis <- fb
fr <- diagnostics_mgmfrm(frequentist,"fair_average",reference_plan=plan,comparisons=comparison)
prob1 <- plogis(point_values[1:2]-.3);prob2 <- plogis(point_values[1:2]+.3)
grad <- .25*prob1*(1-prob1)+.75*prob2*(1-prob2)
stopifnot(max(abs(fr$rows$mean-(.25*prob1+.75*prob2)))<1e-14,
  max(abs(fr$rows$sd-grad*sqrt(diag(V)[1:2])))<1e-14,
  abs(fr$contrasts$sd^2-(grad[1]^2*.25+grad[2]^2*.36-2*prod(grad)*.1))<1e-14,
  identical(fr$interval_target,"wald_expected_score"),is.null(fr$rows$probability),
  inherits(try(diagnostics_mgmfrm(frequentist,"fair_average",reference_plan=plan,threshold=.5),silent=TRUE),"try-error"))
fb$frequentist$method <- "mmle";fb$frequentist$delta <- NULL
fb$frequentist$posterior <- list(list(nodes=as.list(c(-1,0,1)),weights=as.list(c(.2,.3,.5))),
  list(nodes=as.list(c(-.5,.5,1.5)),weights=as.list(c(.4,.4,.2))))
frequentist$method <- "mmle";frequentist$metadata$fair_reference_basis <- fb
mr <- diagnostics_mgmfrm(frequentist,"fair_average",reference_plan=plan,threshold=.5,comparisons=comparison)
expected <- lapply(fb$frequentist$posterior,function(p) .25*plogis(unlist(p$nodes)-.3)+.75*plogis(unlist(p$nodes)+.3))
stopifnot(identical(mr$interval_target,"conditional_posterior_expected_score"),mr$n_draws==0L,
  max(abs(mr$rows$mean-vapply(1:2,function(p)sum(expected[[p]]*unlist(fb$frequentist$posterior[[p]]$weights)),double(1))))<1e-14,
  max(abs(mr$rows$probability-c(.8,.6)))<1e-14)

# Focal DFF, held group membership, and zero-interaction reporting.
dff <- f; db <- basis; db$schema <- "bayesianmgmfrm.fair_reference_basis.v2"
db$contexts <- list(list(name="group",values=1:2))
db$interactions <- list(list(kind="location",roles=c("rater","group"),levels=list(1:2,1:2),
  parameters=list(NULL,"dff",NULL,NULL)))
dff$ids$group <- c("control","focal");dff$metadata$fair_reference_basis <- db
z <- array(c(x,rep(.8,n)),c(20L,2L,length(vars)+1L),dimnames=list(NULL,NULL,c(vars,"dff")))
dff$draws <- posterior::as_draws_array(z)
for (mode in c("fitted","zero")) {
  dr <- diagnostics_mgmfrm(dff,"fair_average",reference_plan=plan,interaction_effects=mode)
  oracle <- sapply(1:2,function(p) .25*plogis(mx[,p]+mx[,7]-mx[,3]-mx[,5]-if(mode=="fitted" && p==2L) .8 else 0)+
    .75*plogis(mx[,p]+mx[,7]-mx[,4]-mx[,6]))
  stopifnot(max(abs(dr$rows$mean-colMeans(oracle)))<1e-14,
    identical(dr$held_contexts[[1L]]$rows$value,c("control","focal")),identical(dr$interaction_effects,mode))
}
stopifnot(inherits(try(diagnostics_mgmfrm(dff,"fair_average",reference_plan=plan),silent=TRUE),"try-error"),
  inherits(try(diagnostics_mgmfrm(f,"fair_average",reference_plan=plan,interaction_effects="zero"),silent=TRUE),"try-error"))
# Add a rater-step interaction independently of the focal location effect.
db$interactions[[2L]] <- list(kind="steps",roles="rater",levels=list(1:2),n_steps=1L,parameters=c("dff","dff"))
dff$metadata$fair_reference_basis <- db
dr <- diagnostics_mgmfrm(dff,"fair_average",reference_plan=plan,interaction_effects="fitted")
oracle <- sapply(1:2,function(p) .25*plogis(mx[,p]+mx[,7]-mx[,3]-mx[,5]-.8-if(p==2L) .8 else 0)+
  .75*plogis(mx[,p]+mx[,7]-mx[,4]-mx[,6]-.8))
stopifnot(max(abs(dr$rows$mean-colMeans(oracle)))<1e-14)

# Offline marginal Fair-M / Fair-Z (`facet` without `reference_plan`), pair_bias, classification, and ranking
mfa_b <- diagnostics_mgmfrm(f, "fair_average", facet = "rater", baseline = "sample_mean")
mfa_z <- diagnostics_mgmfrm(f, "fair_average", facet = "rater", baseline = "zero_origin")
p_bar <- rowMeans(mx[, 1:2]) + mx[, 7]
it_bar <- rowMeans(mx[, 3:4])
tau_bar <- rowMeans(mx[, 8:9])
exp_r1_m <- mean(plogis(p_bar - mx[, 5] - it_bar - tau_bar))
exp_r1_z <- mean(plogis(mx[, 7] - mx[, 5] - tau_bar))
stopifnot(
  identical(mfa_b$rows$level, c("X", "Y")),
  abs(mfa_b$rows$mean[[1L]] - exp_r1_m) < 1e-14,
  abs(mfa_z$rows$mean[[1L]] - exp_r1_z) < 1e-14,
  inherits(try(diagnostics_mgmfrm(generalized, "fair_average", facet = "rater"), silent = TRUE), "try-error"),
  inherits(try(diagnostics_mgmfrm(mix, "fair_average", facet = "rater"), silent = TRUE), "try-error"),
  nrow(diagnostics_mgmfrm(mix, "fair_average", facet = "rater", step_group = "A")$rows) == 2L
)

frequentist$fit_statistics <- list(
  rater = data.frame(level = c("X", "Y"), n_ratings = c(4L, 4L), observed_average = c(0.5, 0.75),
                     fixed = c(FALSE, FALSE), se = c(0.2, 0.25), stringsAsFactors = FALSE)
)
mfa_freq <- diagnostics_mgmfrm(frequentist, "fair_average", facet = "rater", baseline = "sample_mean")
stopifnot(
  identical(mfa_freq$method, "mmle"),
  all(is.finite(mfa_freq$rows$fair_average)),
  all(is.finite(mfa_freq$rows$fair_average_se) & mfa_freq$rows$fair_average_se > 0)
)

# Offline pair_bias (Bayesian & frequentist)
pb_mock <- list(
  schema = "bayesianmgmfrm.pair_bias_basis.v1",
  person = c(1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L),
  facets = list(item = c(1L, 1L, 2L, 2L, 1L, 1L, 2L, 2L), rater = c(1L, 2L, 1L, 2L, 1L, 2L, 1L, 2L)),
  step_group = c(1L, 1L, 2L, 2L, 1L, 1L, 2L, 2L),
  score = c(0L, 1L, 1L, 0L, 1L, 1L, 0L, 1L)
)
f_pb <- f; f_pb$metadata$pair_bias_basis <- pb_mock
freq_pb <- frequentist; freq_pb$metadata$pair_bias_basis <- pb_mock
pb_b <- diagnostics_mgmfrm(f_pb, "pair_bias", pair = c("rater", "item"))
pb_f <- diagnostics_mgmfrm(freq_pb, "pair_bias", pair = c("rater", "item"))
stopifnot(
  identical(pb_b$analysis_mode, "secondary_residual_screen"),
  nrow(pb_b$rows) == 4L,
  all(is.finite(pb_b$rows$approx_severity_bias_logit_mean)),
  nrow(pb_f$rows) == 4L,
  all(is.finite(pb_f$rows$approx_severity_bias_logit) & pb_f$rows$approx_severity_bias_se > 0)
)

# Offline classification (joint posterior, linked location, MMLE conditional quadrature, and correlated any_error_probability)
cls_b <- diagnostics_mgmfrm(f, "classification", cutoff = 0.0, pass_probability = 0.5)
cls_lnk <- diagnostics_mgmfrm(f, "classification", cutoff = 0.0, pass_probability = 0.5, location = "linked")
cls_mmle <- diagnostics_mgmfrm(frequentist, "classification", cutoff = 0.0, pass_probability = 0.5)
jmle_only <- frequentist; jmle_only$metadata$fair_reference_basis$frequentist$method <- "jmle"
stopifnot(
  identical(cls_b$rows$level, c("alpha", "beta")),
  all(cls_b$rows$decision %in% c("pass", "fail")),
  cls_b$cohort$any_error_probability >= 0 && cls_b$cohort$any_error_probability <= 1,
  !identical(cls_b$rows$mean, cls_lnk$rows$mean),
  identical(cls_mmle$method, "conditional_empirical_bayes_quadrature"),
  nrow(cls_mmle$rows) == 2L,
  inherits(try(diagnostics_mgmfrm(jmle_only, "classification", cutoff = 0.0), silent = TRUE), "try-error")
)

# Exact tie-handling and midranks in ranking (positions 1..2 tied -> midrank 1.5, top_k=1 -> lower=0, upper=1)
tie_arr <- array(c(
  10, 10, 10, 10,
  10, 10, 10, 10,
   2,  2,  2,  2
), dim = c(2L, 2L, 3L), dimnames = list(NULL, NULL, c("person[1]", "person[2]", "person[3]")))
tie_fit <- structure(list(
  draws = posterior::as_draws_array(tie_arr),
  method = "nuts",
  ids = list(person = c("P1", "P2", "P3")),
  parameter_labels = c("person[1]" = "person[P1]", "person[2]" = "person[P2]", "person[3]" = "person[P3]"),
  metadata = list(qualification = list(qualified = TRUE))
), class = "mgmfrm_r_fit")
rk_tie <- diagnostics_mgmfrm(tie_fit, "ranking", direction = "higher", top_k = 1L)
stopifnot(
  identical(rk_tie$rows$mean, c(1.5, 1.5, 3.0)),
  identical(rk_tie$rows$tie_probability, c(1.0, 1.0, 0.0)),
  identical(rk_tie$rows$top_k_lower, c(0.0, 0.0, 0.0)),
  identical(rk_tie$rows$top_k_upper, c(1.0, 1.0, 0.0)),
  identical(rk_tie$rows$boundary_tie_probability, c(1.0, 1.0, 0.0))
)
