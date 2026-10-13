data {
  int<lower=1> J;
  int<lower=1> R;
  int<lower=1> I;
  int<lower=2> K;
  int<lower=1> N;
  array[N] int<lower=1,upper=J> person;
  array[N] int<lower=1,upper=R> rater;
  array[N] int<lower=1,upper=I> item;
  array[N] int<lower=1,upper=K> score;
  vector[I] item_mean;
  matrix[I,K-1] step_mean;
  real<lower=0> person_sd;
  real<lower=0> rater_sd;
  real<lower=0> item_sd;
  real<lower=0> step_sd;
}
parameters {
  vector[J+R-1+I+I*(K-2)] x;
}
transformed parameters {
  vector[J] ability = head(x,J);
  vector[R] severity;
  vector[I] difficulty = segment(x,J+R,I);
  matrix[I,K-1] steps;
  if (R>1) severity[1:(R-1)] = segment(x,J+1,R-1);
  severity[R] = -sum(head(severity,R-1));
  for (i in 1:I) {
    if (K>2) steps[i,1:(K-2)] = to_row_vector(segment(x,J+R+I+(i-1)*(K-2),K-2));
    steps[i,K-1] = -sum(head(to_vector(steps[i]),K-2));
  }
}
model {
  target += normal_lpdf(ability | 0, person_sd);
  target += normal_lpdf(difficulty | item_mean, item_sd);
  // Full constrained-vector density plus the free-chart normalization.
  target += normal_lpdf(severity | 0, rater_sd) + log(rater_sd) + 0.5*log(2*pi()) + 0.5*log(R);
  for (i in 1:I)
    target += normal_lpdf(to_vector(steps[i]) | to_vector(step_mean[i]), step_sd)
              + log(step_sd) + 0.5*log(2*pi()) + 0.5*log(K-1);
  for (n in 1:N) {
    vector[K] logits;
    logits[1] = 0;
    for (k in 2:K)
      logits[k] = logits[k-1] + 1.7*(ability[person[n]]-severity[rater[n]]-difficulty[item[n]]-steps[item[n],k-1]);
    target += categorical_logit_lpmf(score[n] | logits);
  }
}
