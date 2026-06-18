data {
  int<lower=1> J;
  int<lower=1> I;
  int<lower=1> R;
  int<lower=2> K;
  int<lower=1> D;
  int<lower=1> N;
  array[N] int<lower=1, upper=J> ExamineeID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=K> X;
}
transformed data {
  vector[K] c = cumulative_sum(rep_vector(1, K)) - 1;
}
parameters {
  matrix[D, J] theta;
  matrix<lower=0>[D, I] alpha_i;
  vector[I] beta_i;
  vector[R - 1] log_alpha_r;
  vector[R - 1] beta_r;
  matrix[K - 2, I] beta_ik;
}
transformed parameters {
  vector[R] trans_alpha_r;
  vector[R] trans_beta_r;
  array[I] vector[K - 1] category_est;
  array[I] vector[K] category_prm;

  trans_alpha_r[1] = exp(-sum(log_alpha_r));
  trans_alpha_r[2:R] = exp(log_alpha_r);
  trans_beta_r[1] = -sum(beta_r);
  trans_beta_r[2:R] = beta_r;

  for (i in 1:I) {
    category_est[i][1:(K - 2)] = beta_ik[, i];
    category_est[i][K - 1] = -sum(beta_ik[, i]);
    category_prm[i] = cumulative_sum(append_row(0, category_est[i]));
  }
}
model {
  for (d in 1:D) {
    theta[d, ] ~ normal(0, 1);
    alpha_i[d, ] ~ lognormal(0, 1);
  }

  // Match the Julia fast path: log_alpha_r is the sampled coordinate, while
  // the Uto-Ueno transform prior is evaluated on trans_alpha_r without adding
  // a change-of-variables correction.
  trans_alpha_r ~ lognormal(0, 1);
  trans_beta_r ~ normal(0, 1);
  beta_i ~ normal(0, 1);
  for (i in 1:I) {
    category_est[i] ~ normal(0, 1);
  }

  for (n in 1:N) {
    int i = ItemID[n];
    int r = RaterID[n];
    int j = ExamineeID[n];
    real score = dot_product(alpha_i[, i], theta[, j]) - beta_i[i] - trans_beta_r[r];
    X[n] ~ categorical_logit(1.7 * trans_alpha_r[r] * (c * score - category_prm[i]));
  }
}
