// Complete density in one explicit white/log-SD/Fisher-z coordinate vector.
functions {
  vector zero_sum(vector z) {
    int q = num_elements(z);
    vector[q+1] out = rep_vector(0, q+1);
    if (q > 0) {
      for (j in 1:q) {
        real a = z[j] / sqrt(j * (j+1.0));
        for (i in 1:j) out[i] += a;
        out[j+1] -= j*a;
      }
    }
    return out;
  }
  real log_corr_complement(real z) {
    if (z >= 0) return 2*(log(2)-z-log1p_exp(-2*z));
    return 2*(log(2)+z-log1p_exp(2*z));
  }
  real stable_tanh(real z) {
    if (z >= 0) return -expm1(-2*z)/(1+exp(-2*z));
    return expm1(2*z)/(1+exp(2*z));
  }
  matrix corr_L(real z) {
    real rho = stable_tanh(z);
    matrix[2,2] L = rep_matrix(0,2,2);
    L[1,1] = 1;
    L[2,1] = rho;
    L[2,2] = exp(log_corr_complement(z)/2);
    return L;
  }
  vector logits(real location, vector steps) {
    int K = num_elements(steps)+1;
    vector[K] a;
    a[1]=0;
    for (k in 2:K) a[k]=a[k-1]+location-steps[k-1];
    return a;
  }
  real full_prior(vector q, vector mu, vector sd, int corr_start,
                  vector lkj_eta) {
    real lp = normal_lpdf(head(q,corr_start-1) | mu,sd);
    for (j in 1:2) {
      // D=2 normalized LKJ density plus the explicit Fisher-z Jacobian.
      lp += lkj_eta[j]*log_corr_complement(q[corr_start+j-1])-lbeta(0.5,lkj_eta[j]);
    }
    return lp;
  }
}
data {
  int<lower=2> P;
  int<lower=2> T;
  int<lower=2> R;
  int<lower=1> O;
  int<lower=2> K;
  int<lower=1,upper=2> G;
  int<lower=0> F;
  int<lower=1> N;
  array[N] int<lower=1,upper=P> person;
  array[N] int<lower=1,upper=T> task;
  array[N] int<lower=1,upper=R> rater;
  array[N] int<lower=1,upper=O> response;
  array[N] int<lower=1,upper=2> criterion;
  array[N] int<lower=1,upper=K> y;
  array[2] int<lower=1,upper=G> threshold_group;
  matrix[N,F] X;
  real<lower=0> task_sd;
  vector<lower=0>[2] rater_sd;
  vector<lower=0>[G] step_sd;
  vector[2] response_log_sd_mean;
  vector<lower=0>[2] response_log_sd_sd;
  vector<lower=0>[F] beta_sd;
  vector<lower=0>[2] lkj_eta;
}
transformed data {
  int task_start = 2*P+1;
  int rater_start = task_start+2*T;
  int step_start = rater_start+2*(R-1);
  int response_start = step_start+G*(K-2);
  int beta_start = response_start+2*O;
  int log_sd_start = beta_start+F;
  int corr_start = log_sd_start+2;
  int D = corr_start+1;
  vector[D-2] mu = rep_vector(0,D-2);
  vector[D-2] sd = rep_vector(1,D-2);
  array[O] int owner_person = rep_array(0,O);
  array[O] int owner_task = rep_array(0,O);
  if (task_sd <= 0 || min(rater_sd) <= 0 || min(step_sd) <= 0
      || min(response_log_sd_sd) <= 0 || min(lkj_eta) <= 0)
    reject("positive scales and LKJ shapes required");
  if (F > 0 && min(beta_sd) <= 0) reject("positive beta scales required");
  if (G == 2 && threshold_group[1] == threshold_group[2]) reject("unused threshold group");
  for (n in 1:N) {
    int o=response[n];
    if (owner_person[o] != 0 && (owner_person[o] != person[n] || owner_task[o] != task[n]))
      reject("response ownership conflict");
    owner_person[o]=person[n]; owner_task[o]=task[n];
  }
  sd[task_start:(rater_start-1)] = rep_vector(task_sd,2*T);
  if (F > 0) sd[beta_start:(log_sd_start-1)] = beta_sd;
  mu[log_sd_start:(corr_start-1)] = response_log_sd_mean;
  sd[log_sd_start:(corr_start-1)] = response_log_sd_sd;
}
parameters { vector[D] q; }
transformed parameters {
  matrix[2,2] L_person = corr_L(q[corr_start]);
  matrix[2,2] L_response = corr_L(q[corr_start+1]);
  matrix[2,P] theta = L_person*to_matrix(head(q,2*P),2,P);
  matrix[2,T] task_effect = to_matrix(segment(q,task_start,2*T),2,T);
  matrix[R,2] rater_effect;
  matrix[K-1,G] steps;
  matrix[2,O] response_effect = diag_pre_multiply(exp(segment(q,log_sd_start,2)),L_response)
       * to_matrix(segment(q,response_start,2*O),2,O);
  vector[F] beta = segment(q,beta_start,F);
  for (c in 1:2)
    rater_effect[,c] = rater_sd[c]*zero_sum(segment(q,rater_start+(c-1)*(R-1),R-1));
  for (g in 1:G)
    steps[,g] = step_sd[g]*zero_sum(segment(q,step_start+(g-1)*(K-2),K-2));
}
model {
  target += full_prior(q,mu,sd,corr_start,lkj_eta);
  for (n in 1:N) {
    int c=criterion[n];
    real location=theta[c,person[n]]-task_effect[c,task[n]]-rater_effect[rater[n],c]
       + response_effect[c,response[n]]+X[n]*beta;
    target += categorical_logit_lpmf(y[n] | logits(location,steps[,threshold_group[c]]));
  }
}
generated quantities {
  real prior_lp=full_prior(q,mu,sd,corr_start,lkj_eta);
  vector[N] log_lik;
  matrix[N,K] log_probs;
  for (n in 1:N) {
    int c=criterion[n];
    real location=theta[c,person[n]]-task_effect[c,task[n]]-rater_effect[rater[n],c]
       + response_effect[c,response[n]]+X[n]*beta;
    vector[K] lp=log_softmax(logits(location,steps[,threshold_group[c]]));
    log_probs[n]=lp';
    log_lik[n]=lp[y[n]];
  }
}
