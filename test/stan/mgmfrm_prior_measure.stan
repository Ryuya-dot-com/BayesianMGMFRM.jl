// Prior-only reference, not an executable MGMFRM response model.
// Positive free consistencies and FIRST-rater reconstruction follow the
// previously checked printed Appendix 1; its fixed unit SD is generalized here.
data {
  int<lower=2> R;
  int<lower=3> K;
  int<lower=0, upper=1> exchangeable;
  real<lower=0> severity_sd;
  real<lower=0> consistency_sd;
  real<lower=0> step_sd;
}
parameters {
  vector[R - 1] severity_free;
  vector<lower=0>[R - 1] consistency_free;
  vector[K - 2] step_free;
}
transformed parameters {
  vector[R] severity = append_row(-sum(severity_free), severity_free);
  vector[R] consistency = append_row(inv(prod(consistency_free)), consistency_free);
  vector[K - 1] steps = append_row(step_free, -sum(step_free));
}
model {
  // Explicit lpdf calls retain constants even in CmdStan's propto=true evaluation.
  target += normal_lpdf(severity | 0, severity_sd)
    + log(severity_sd) + 0.5 * log(2 * pi() * R);
  target += normal_lpdf(steps | 0, step_sd)
    + log(step_sd) + 0.5 * log(2 * pi() * (K - 1));
  if (exchangeable) {
    // Density in positive free coordinates for a centered log-space normal.
    target += normal_lpdf(log(consistency) | 0, consistency_sd)
      - sum(log(consistency_free));
  } else {
    target += lognormal_lpdf(consistency | 0, consistency_sd)
      - square(consistency_sd) * (R - 1.0) / (2 * R);
  }
  target += log(consistency_sd) + 0.5 * log(2 * pi() * R);
}
