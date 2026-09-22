// A0 application reference. beta uses exactly the Julia noncentered coordinates.
functions {
  real log_residual_variance(real z) {
    return 2 * (log(2.0) - abs(z) - log1p_exp(-2 * abs(z)));
  }
  vector pcm_logits(real location, vector steps) {
    int K = num_elements(steps);
    vector[K] eta;
    eta[1] = 0;
    for (k in 2:K) eta[k] = eta[k-1] + location - steps[k];
    return eta;
  }
}
data {
  int<lower=1> P;
  int<lower=1> W;
  int<lower=2> R;
  int<lower=1> O;
  int<lower=2,upper=20> K;
  int<lower=1> N;
  array[N] int<lower=1,upper=P> person;
  array[N] int<lower=1,upper=W> word;
  array[N] int<lower=1,upper=R> rater;
  array[N] int<lower=1,upper=O> recording;
  array[N] int<lower=1,upper=2> criterion;
  array[N] int<lower=1,upper=K> y;
  real<lower=0> word_sd;
  vector<lower=0>[2] rater_sd;
  vector<lower=0>[2] step_sd;
  vector[2] recording_log_sd_mean;
  vector<lower=0>[2] recording_log_sd_sd;
  int<lower=1,upper=10000> person_lkj_eta;
  int<lower=1,upper=10000> recording_lkj_eta;
}
transformed data {
  int u_offset = 2*P;
  int w_offset = u_offset + 2*O;
  int r_offset = w_offset + 2*W;
  int s_offset = r_offset + 2*(R-1);
  int sd_offset = s_offset + 2*(K-2);
  int rho_offset = sd_offset + 2;
  int D = rho_offset + 2;
  if (word_sd <= 0 || min(rater_sd) <= 0 || min(step_sd) <= 0 || min(recording_log_sd_sd) <= 0)
    reject("all prior scales must be strictly positive");
}
parameters {
  vector[D] beta;
}
transformed parameters {
  vector[2] rho = tanh(segment(beta, rho_offset+1, 2));
  vector[2] recording_sd = exp(segment(beta, sd_offset+1, 2));
  matrix[2,P] theta;
  matrix[2,O] u;
  matrix[2,W] difficulty = to_matrix(segment(beta, w_offset+1, 2*W), 2, W);
  matrix[R,2] severity;
  matrix[K,2] steps = rep_matrix(0, K, 2);
  for (p in 1:P) {
    theta[1,p] = beta[2*p-1];
    theta[2,p] = rho[1]*beta[2*p-1]
      + exp(log_residual_variance(beta[rho_offset+1])/2)*beta[2*p];
  }
  for (o in 1:O) {
    u[1,o] = recording_sd[1]*beta[u_offset+2*o-1];
    u[2,o] = recording_sd[2]*(rho[2]*beta[u_offset+2*o-1]
      + exp(log_residual_variance(beta[rho_offset+2])/2)*beta[u_offset+2*o]);
  }
  for (c in 1:2) {
    severity[1:(R-1),c] = segment(beta, r_offset+(c-1)*(R-1)+1, R-1);
    severity[R,c] = -sum(severity[1:(R-1),c]);
    if (K > 2) steps[2:(K-1),c] = segment(beta, s_offset+(c-1)*(K-2)+1, K-2);
    steps[K,c] = -sum(steps[1:(K-1),c]);
  }
}
model {
  // Complete normalizers in the declared free-coordinate measure.
  target += -0.5*dot_self(head(beta,w_offset)) - 0.5*w_offset*log(2*pi());
  target += -0.5*dot_self(segment(beta,w_offset+1,2*W)/word_sd)
    - 2*W*(log(word_sd)+0.5*log(2*pi()));
  for (c in 1:2) {
    target += 0.5*log(R) - (R-1)*(log(rater_sd[c])+0.5*log(2*pi()))
      - 0.5*dot_self(severity[,c]/rater_sd[c]);
    target += 0.5*log(K-1) - (K-2)*(log(step_sd[c])+0.5*log(2*pi()))
      - 0.5*dot_self(steps[,c]/step_sd[c]);
    target += -0.5*square((beta[sd_offset+c]-recording_log_sd_mean[c])/recording_log_sd_sd[c])
      - log(recording_log_sd_sd[c])-0.5*log(2*pi());
  }
  target += -lbeta(0.5,person_lkj_eta)
    + person_lkj_eta*log_residual_variance(beta[rho_offset+1]);
  target += -lbeta(0.5,recording_lkj_eta)
    + recording_lkj_eta*log_residual_variance(beta[rho_offset+2]);
  for (n in 1:N) {
    int c = criterion[n];
    real location = theta[c,person[n]] - difficulty[c,word[n]]
      - severity[rater[n],c] + u[c,recording[n]];
    target += categorical_logit_lpmf(y[n] | pcm_logits(location,steps[,c]));
  }
}
generated quantities {
  vector[N] log_lik;
  for (n in 1:N) {
    int c = criterion[n];
    real location = theta[c,person[n]] - difficulty[c,word[n]]
      - severity[rater[n],c] + u[c,recording[n]];
    log_lik[n] = categorical_logit_lpmf(y[n] | pcm_logits(location,steps[,c]));
  }
}
