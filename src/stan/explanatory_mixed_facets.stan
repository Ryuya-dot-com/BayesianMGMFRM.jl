// Independent dense-map PCM reference with locally normalized category supports.
data {
  int<lower=1> N;
  int<lower=2> K;
  int<lower=1> G;
  int<lower=1> R;
  int<lower=0> T;
  int<lower=0> V;
  int<lower=1> D;
  int<lower=1> H;
  int<lower=0> Qstep;
  array[N] int<lower=1,upper=K> y;
  array[N] int<lower=1,upper=G> group;
  array[G] int<lower=1,upper=K> category_begin;
  array[G] int<lower=2,upper=K> support_size;
  array[G] int<lower=1,upper=H> step_begin;
  matrix[N,R] A;
  matrix[N,T] X;
  matrix[H,Qstep] Astep;
  vector<lower=0>[R] residual_scale;
  array[R] int<lower=0,upper=V> hyper_index;
  vector[V] logmean;
  vector<lower=0>[V] logsd;
  vector[T] coefficient_mean;
  vector<lower=0>[T] coefficient_sd;
}
transformed data {
  if (D != R+Qstep+T+V) reject("coordinate dimension mismatch");
  for (g in 1:G) {
    if (category_begin[g]+support_size[g]-1 > K) reject("category support outside union");
    if (step_begin[g]+support_size[g]-2 > H) reject("step support outside map");
  }
}
parameters { vector[D] q; }
model {
  vector[R] effect;
  vector[T] beta = coefficient_mean + coefficient_sd .* segment(q,R+Qstep+1,T);
  vector[H] tau = Astep*segment(q,R+1,Qstep);
  vector[N] eta;
  for (j in 1:R) {
    real scale = residual_scale[j];
    if (hyper_index[j] > 0)
      scale = exp(logmean[hyper_index[j]] + logsd[hyper_index[j]] * q[R+Qstep+T+hyper_index[j]]);
    effect[j] = scale*q[j];
  }
  eta = A*effect + X*beta;
  target += std_normal_lpdf(q);
  for (n in 1:N) {
    int g = group[n];
    vector[support_size[g]] w;
    w[1] = 0;
    for (k in 2:support_size[g]) w[k] = w[k-1] + eta[n] - tau[step_begin[g]+k-2];
    target += categorical_logit_lpmf(y[n]-category_begin[g]+1 | w);
  }
}
