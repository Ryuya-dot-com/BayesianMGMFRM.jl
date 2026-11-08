// Independent equations in white coordinates; no sampler-specific heuristics.
data {
  int<lower=1> N;
  int<lower=1> P;
  int<lower=0> F;
  int<lower=1> G;
  int<lower=2> K;
  int<lower=0> M;
  int<lower=0> Q;
  int<lower=1> D;
  array[N] int<lower=1,upper=P> person;
  array[N,F] int<lower=1,upper=M> facet_index;
  array[N] int<lower=1,upper=G> group;
  array[N] int<lower=1,upper=K> y;
  real<lower=0> person_sd;
  matrix[M,Q] A;
  matrix[K-1,K-2] Hstep;
}
parameters { vector[D] q; }
model {
  vector[P] theta=person_sd*head(q,P);
  vector[M] effects=rep_vector(0,M);
  matrix[K-1,G] steps=rep_matrix(0,K-1,G);
  if (Q>0) effects=A*segment(q,P+1,Q);
  if (K>2) steps=Hstep*to_matrix(tail(q,G*(K-2)),K-2,G);
  target += std_normal_lpdf(q);
  for (n in 1:N) {
    real eta=theta[person[n]];
    vector[K] logits=rep_vector(0,K);
    if (F>0) for (f in 1:F) eta-=effects[facet_index[n,f]];
    for (k in 2:K) logits[k]=(k-1)*eta-sum(steps[1:(k-1),group[n]]);
    target += categorical_logit_lpmf(y[n] | logits);
  }
}
