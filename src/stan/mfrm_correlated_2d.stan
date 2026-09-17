// Private correlated 2D fixed-coefficient MFRM.
functions {
  // Rotated bivariate-normal quadratic avoids subtracting rho rounded to +/-1.
  real scaled_square(real x, real log_scale) {
    return x == 0 ? 0 : exp(2 * log(abs(x)) + log_scale);
  }
  real person_2d_logpdf(real x, real y, real sd, real z) {
    real log_plus = log(2.0) - log1p_exp(-2 * z);
    real log_minus = log(2.0) - log1p_exp(2 * z);
    return -log(2 * pi()) - 2 * log(sd) - (log_plus + log_minus) / 2
      - scaled_square(x / sd + y / sd, -log_plus - log(4.0))
      - scaled_square(x / sd - y / sd, -log_minus - log(4.0));
  }
#include mgmfrm_functions.stan
  vector fixed_q_raw(vector beta, int locations, int n_steps, int step_offset) {
    vector[step_offset + n_steps] raw = rep_vector(0, step_offset + n_steps);
    raw[1:locations] = beta[1:locations] / 1.7;
    raw[(step_offset + 1):(step_offset + n_steps)] =
      beta[(locations + 1):(locations + n_steps)] / 1.7;
    return raw;
  }
}
data {
  int<lower=1> J;
  int<lower=2> R;
  int<lower=2> I;
  int<lower=2> K;
  int<lower=2, upper=2> D;
  int<lower=1, upper=10000> lkj_eta;
  int<lower=1> N;
  int<lower=1> NLoadings;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  array[NLoadings] int<lower=1, upper=I> LoadingItem;
  array[NLoadings] int<lower=1, upper=D> LoadingDim;
  vector<lower=0>[J * D + R - 1 + I + I * (K - 2)] reference_sd;
}
transformed data {
  int locations = J * D + R - 1 + I;
  int free_steps = K - 2;
  int n_steps = I * free_steps;
  int step_offset = locations + NLoadings + R - 1;
  if (min(reference_sd) <= 0)
    reject("reference_sd must be strictly positive");
  for (p in 1:(J * D))
    if (reference_sd[p] != reference_sd[1])
      reject("ability scales must be identical");
}
parameters {
  vector[locations + n_steps] beta;
  real zrho;
}
model {
  vector[step_offset + n_steps] raw = fixed_q_raw(beta, locations, n_steps, step_offset);
  // Explicit normalized densities; zrho is unconstrained so Stan adds no Jacobian.
  // LKJ(rho) plus the manual tanh Jacobian gives eta * log(1-rho^2).
  real logdelta = 2 * (log(2.0) - abs(zrho) - log1p_exp(-2 * abs(zrho)));
  target += -lbeta(0.5, lkj_eta) + lkj_eta * logdelta;
  for (j in 1:J)
    target += person_2d_logpdf(beta[2*j-1], beta[2*j], reference_sd[1], zrho);
  for (p in (J*D+1):num_elements(beta))
    target += -0.5 * square(beta[p] / reference_sd[p])
      - log(reference_sd[p]) - 0.5 * log(2 * pi());
  for (n in 1:N) {
    target += categorical_logit_lpmf(X[n] | mgmfrm_eta(
      PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
      NLoadings, free_steps, LoadingItem, LoadingDim, raw));
  }
}
generated quantities {
  vector[N] log_lik;
  {
    vector[step_offset + n_steps] raw = fixed_q_raw(beta, locations, n_steps, step_offset);
    for (n in 1:N) {
      log_lik[n] = categorical_logit_lpmf(X[n] | mgmfrm_eta(
        PersonID[n], RaterID[n], ItemID[n], J, R, I, K, D,
        NLoadings, free_steps, LoadingItem, LoadingDim, raw));
    }
  }
}
