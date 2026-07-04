data {
  int<lower=1> J;
  int<lower=1> I;
  int<lower=2> R;
  int<lower=3> K;
  int<lower=1> D;
  int<lower=1> N;
  int<lower=1> NLoadings;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  array[NLoadings] int<lower=1, upper=I> LoadingItem;
  array[NLoadings] int<lower=1, upper=D> LoadingDim;
  real<lower=0> person_sd;
  real<lower=0> rater_sd;
  real<lower=0> item_sd;
  real<lower=0> log_discrimination_sd;
  real<lower=0> log_consistency_sd;
  real<lower=0> step_sd;
}
parameters {
  vector[J * D] person;
  vector[R - 1] rater_free;
  vector[I] item;
  vector[NLoadings] log_item_dimension_discrimination;
  vector[R - 1] log_rater_consistency_free;
  vector[I * (K - 2)] item_steps;
}
transformed parameters {
  vector[R] rater;
  vector[R] rater_consistency;
  vector[NLoadings] item_dimension_discrimination;

  rater[1:(R - 1)] = rater_free;
  rater[R] = -sum(rater_free);
  rater_consistency[1:(R - 1)] = exp(log_rater_consistency_free);
  rater_consistency[R] = exp(-sum(log_rater_consistency_free));
  item_dimension_discrimination = exp(log_item_dimension_discrimination);
}
model {
  person ~ normal(0, person_sd);
  rater_free ~ normal(0, rater_sd);
  item ~ normal(0, item_sd);
  log_item_dimension_discrimination ~ normal(0, log_discrimination_sd);
  log_rater_consistency_free ~ normal(0, log_consistency_sd);
  item_steps ~ normal(0, step_sd);

  for (n in 1:N) {
    int p = PersonID[n];
    int r = RaterID[n];
    int i = ItemID[n];
    vector[K] eta;
    real ability_score = 0;
    real location;
    real scale = 1.7 * rater_consistency[r];
    real cumulative = 0;

    for (loading in 1:NLoadings) {
      if (LoadingItem[loading] == i) {
        int d = LoadingDim[loading];
        ability_score += item_dimension_discrimination[loading] *
          person[(p - 1) * D + d];
      }
    }
    location = ability_score - item[i] - rater[r];
    eta[1] = 0;
    for (k in 2:K) {
      real step;
      if (k <= K - 1) {
        step = item_steps[(i - 1) * (K - 2) + (k - 1)];
      } else {
        step = -sum(item_steps[((i - 1) * (K - 2) + 1):(i * (K - 2))]);
      }
      cumulative += scale * (location - step);
      eta[k] = cumulative;
    }
    X[n] ~ categorical_logit(eta);
  }
}
generated quantities {
  vector[N] log_lik;

  for (n in 1:N) {
    int p = PersonID[n];
    int r = RaterID[n];
    int i = ItemID[n];
    vector[K] eta;
    real ability_score = 0;
    real location;
    real scale = 1.7 * rater_consistency[r];
    real cumulative = 0;

    for (loading in 1:NLoadings) {
      if (LoadingItem[loading] == i) {
        int d = LoadingDim[loading];
        ability_score += item_dimension_discrimination[loading] *
          person[(p - 1) * D + d];
      }
    }
    location = ability_score - item[i] - rater[r];
    eta[1] = 0;
    for (k in 2:K) {
      real step;
      if (k <= K - 1) {
        step = item_steps[(i - 1) * (K - 2) + (k - 1)];
      } else {
        step = -sum(item_steps[((i - 1) * (K - 2) + 1):(i * (K - 2))]);
      }
      cumulative += scale * (location - step);
      eta[k] = cumulative;
    }
    log_lik[n] = categorical_logit_lpmf(X[n] | eta);
  }
}
