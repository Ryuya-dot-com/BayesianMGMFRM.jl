data {
  int<lower=1> J;
  int<lower=2> I;
  int<lower=1> R;
  int<lower=3> K;
  int<lower=1> N;
  array[N] int<lower=1, upper=J> PersonID;
  array[N] int<lower=1, upper=R> RaterID;
  array[N] int<lower=1, upper=I> ItemID;
  array[N] int<lower=1, upper=K> X;
  real<lower=0> person_sd;
  real<lower=0> rater_sd;
  real<lower=0> item_sd;
  real<lower=0> log_discrimination_sd;
  real<lower=0> log_consistency_sd;
  real<lower=0> step_sd;
}
parameters {
  vector[J] person;
  vector[R] rater;
  vector[I - 1] item_free;
  vector[I - 1] log_item_discrimination_free;
  vector[R] log_rater_consistency;
  vector[R * (K - 2)] rater_steps;
}
transformed parameters {
  vector[I] item;
  vector[I] item_discrimination;
  vector[R] rater_consistency;

  item[1:(I - 1)] = item_free;
  item[I] = -sum(item_free);
  item_discrimination[1:(I - 1)] = exp(log_item_discrimination_free);
  item_discrimination[I] = exp(-sum(log_item_discrimination_free));
  rater_consistency = exp(log_rater_consistency);
}
model {
  person ~ normal(0, person_sd);
  rater ~ normal(0, rater_sd);
  item_free ~ normal(0, item_sd);
  log_item_discrimination_free ~ normal(0, log_discrimination_sd);
  log_rater_consistency ~ normal(0, log_consistency_sd);
  rater_steps ~ normal(0, step_sd);

  for (n in 1:N) {
    int p = PersonID[n];
    int r = RaterID[n];
    int i = ItemID[n];
    vector[K] eta;
    real location = person[p] - item[i] - rater[r];
    real scale = item_discrimination[i] * rater_consistency[r];
    real cumulative = 0;

    eta[1] = 0;
    for (k in 2:K) {
      real step;
      if (k <= K - 1) {
        step = rater_steps[(r - 1) * (K - 2) + (k - 1)];
      } else {
        step = -sum(rater_steps[((r - 1) * (K - 2) + 1):(r * (K - 2))]);
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
    real location = person[p] - item[i] - rater[r];
    real scale = item_discrimination[i] * rater_consistency[r];
    real cumulative = 0;

    eta[1] = 0;
    for (k in 2:K) {
      real step;
      if (k <= K - 1) {
        step = rater_steps[(r - 1) * (K - 2) + (k - 1)];
      } else {
        step = -sum(rater_steps[((r - 1) * (K - 2) + 1):(r * (K - 2))]);
      }
      cumulative += scale * (location - step);
      eta[k] = cumulative;
    }
    log_lik[n] = categorical_logit_lpmf(X[n] | eta);
  }
}
