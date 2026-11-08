// Concurrent full-interaction reference; explicit numerical priors and normalized densities.
// Only parameters are emitted by sampling; derived quantities are evaluated after sampling.
functions {
  matrix contrast(int n) {
    matrix[n,n-1] H = rep_matrix(0,n,n-1);
    for (j in 1:(n-1)) {
      for (i in 1:j) H[i,j] = inv_sqrt(j*(j+1.0));
      H[j+1,j] = -j*inv_sqrt(j*(j+1.0));
    }
    return H;
  }
  matrix grouped(array[] int group, int G) {
    int n = size(group);
    matrix[n,n-G] H = rep_matrix(0,n,n-G);
    int col = 1;
    for (g in 1:G) {
      int m = 0;
      array[n] int ix;
      for (i in 1:n) if (group[i]==g) { m+=1; ix[m]=i; }
      if (m<2) reject("At least two members per group required");
      for (j in 1:(m-1)) {
        for (i in 1:j) H[ix[i],col]=inv_sqrt(j*(j+1.0));
        H[ix[j+1],col]=-j*inv_sqrt(j*(j+1.0)); col+=1;
      }
    }
    return H;
  }
  vector location(int r, int s, int w, int j, int g, row_vector xb,
                  real within, row_vector h, matrix means,
                  matrix speaker, matrix word, matrix rater, matrix token,
                  matrix time_effect, array[] matrix l1_effect, matrix pair_effect) {
    vector[3] eta = (means[g,]+xb+speaker[s,]+word[w,]+rater[r,]
                    +token[j,]+within*time_effect[r,]+pair_effect[r+(w-1)*rows(rater),])';
    for (c in 1:2) eta += h[c]*l1_effect[c][r,]';
    return eta;
  }
  vector measure(vector eta, vector slopes, matrix steps) {
    vector[23] out;
    for (a in 1:3) {
      int K = a<3 ? 9 : 2;
      int first = a==1 ? 0 : (a==2 ? 9 : 18);
      vector[K] logits;
      logits[1]=0;
      for (k in 2:K) logits[k]=logits[k-1]+slopes[a]*(eta[a]-(a<3 ? steps[k-1,a] : 0));
      out[(first+1):(first+K)]=softmax(logits);
    }
    out[21]=dot_product(linspaced_vector(9,1,9),out[1:9]);
    out[22]=dot_product(linspaced_vector(9,1,9),out[10:18]);
    out[23]=out[19];
    return out;
  }
}
data {
  int<lower=1> N;
  int<lower=6> R;
  int<lower=10> S;
  int<lower=2> W;
  int<lower=1> J;
  int<lower=1> P;
  int<lower=4,upper=R-2> RM;
  array[3] int<lower=2> group_count;
  array[3] int K;
  array[N] int<lower=1,upper=R> rater;
  array[N] int<lower=1,upper=S> speaker;
  array[N] int<lower=1,upper=W> word;
  array[N] int<lower=1,upper=J> token;
  array[R] int<lower=1,upper=3> rater_group;
  array[S] int<lower=1,upper=5> speaker_cell;
  array[N] int<lower=1,upper=3> l1;
  matrix[N,P] X;
  array[N,3] int y;
  array[S,W] int<lower=1,upper=J> token_lookup;
  matrix[3,2] l1_contrast;
  vector[N] within_time;
  vector<lower=0>[6] sd_scale;
  real<lower=0> step_sd_scale;
  real<lower=0> slope_log_sd;
  vector<lower=0>[3] intercept_sd;
  real<lower=0> cohort_sd;
  vector<lower=0>[3] beta_sd;
  real<lower=0> lkj_eta;
  vector[7] step_mean;
  real<lower=0> step_coordinate_sd;
  real<lower=0> pair_sd_scale;
  real<lower=0> pair_lkj_eta;

}
transformed data {
  vector[9] category_index = linspaced_vector(9,0,8);
  vector[N] binary_sign;
  matrix[S,S-5] HS=grouped(speaker_cell,5);
  matrix[W,W-1] HW=contrast(W);
  matrix[R,R-3] HR=grouped(rater_group,3);
  matrix[R,RM-2] HL=rep_matrix(0,R,RM-2);
  matrix[S,S-1] HSA=contrast(S);
  matrix[R,R-1] HRA=contrast(R);
  matrix[8,7] HK=contrast(8);
  if (J!=S*W || P!=24 || K[1]!=9 || K[2]!=9 || K[3]!=2)
    reject("Only the concurrent 9/9/2, 24-predictor layout is admitted");
  if (sum(group_count)!=R || group_count[1]+group_count[2]!=RM)
    reject("Cohort dimensions differ");
  for (r in 1:R) {
    int g=r<=group_count[1] ? 1 : (r<=RM ? 2 : 3);
    if (rater_group[r]!=g) reject("Raters must be in cohort order");
  }
  HL[1:RM,]=grouped(rater_group[1:RM],2);
  for (n in 1:N) binary_sign[n] = 2*y[n,3]-3;
  for (n in 1:N) for (a in 1:3) if (y[n,a]<1 || y[n,a]>K[a]) reject("Response support differs");
}
parameters {
  // This order also matches the Julia unconstrained coordinate vector.
  matrix[S-5,3] speaker_q;
  matrix[W-1,3] word_q;
  matrix[R-3,3] rater_q;
  matrix[(S-1)*(W-1),3] token_q;
  matrix[R-3,3] time_q;
  matrix[RM-2,3] l1_q1;
  matrix[RM-2,3] l1_q2;
  matrix[W-1,3] word_slope_q;
  matrix[R-1,3] rater_slope_q;
  matrix[7,2] step_q;
  matrix[R-1,7] rater_step_q1;
  matrix[R-1,7] rater_step_q2;
  vector[9] mean_q;
  matrix[24,3] beta;
  matrix[(R-1)*(W-1),3] pair_q;
  array[6] vector<lower=0>[3] sd;
  array[6] cholesky_factor_corr[3] L_cov;
  vector<lower=0>[2] step_sd;
  vector<lower=0>[3] pair_sd;
  cholesky_factor_corr[3] L_pair;
}
model {
 profile("density_body") {
  matrix[S,3] speaker_effect;
  matrix[W,3] word_effect;
  matrix[R,3] rater_effect;
  matrix[J,3] token_effect;
  matrix[R,3] time_effect;
  array[2] matrix[R,3] l1_effect;
  matrix[R*W,3] pair_effect;
  matrix[3,3] mean_effect;
  matrix[N,3] regression = X*beta;
  matrix[W,3] word_slope=exp(slope_log_sd*HW*word_slope_q);
  matrix[R,3] rater_slope=exp(slope_log_sd*HRA*rater_slope_q);
  matrix[8,2] step=HK*step_q;
  array[2] matrix[R,8] rater_step;
  array[2] matrix[R,9] threshold_sum;
  vector[N] binary_logit;
  vector[4] parts=rep_vector(0,4);
  {
    array[6] matrix[3,3] F;
    array[6] matrix[3,3] Sigma;
    matrix[3,3] FB=diag_pre_multiply(pair_sd,L_pair);
    matrix[3,3] SB=FB*FB';
    matrix[9,9] mean_cov=rep_matrix(0,9,9);
    matrix[R,3] urater=HR*rater_q;
    for (b in 1:6) { F[b]=diag_pre_multiply(sd[b],L_cov[b]); Sigma[b]=F[b]*F[b]'; }
    speaker_effect=HS*speaker_q*F[1]';
    word_effect=HW*word_q*cholesky_decompose(Sigma[2]+SB/R)';
    for (g in 1:3) {
      matrix[3,3] cov=Sigma[3]+SB/W;
      matrix[3,3] factor;
      if (g==3) cov+=(2.0/3)*Sigma[6];
      factor=cholesky_decompose(cov);
      for (r in 1:R) if (rater_group[r]==g) rater_effect[r,]=urater[r,]*factor';
      for (h in 1:3) for (a in 1:3) mean_cov[3*(g-1)+a,3*(h-1)+a]=square(intercept_sd[a]);
      if (g>1) for (a in 1:3) mean_cov[3*(g-1)+a,3*(g-1)+a]+=square(cohort_sd);
      mean_cov[(3*g-2):(3*g),(3*g-2):(3*g)]+=SB/(group_count[g]*W);
    }
    mean_effect=to_matrix(cholesky_decompose(mean_cov)*mean_q,3,3)';
    time_effect=HR*time_q*F[5]';
    l1_effect[1]=HL*l1_q1*F[6]'; l1_effect[2]=HL*l1_q2*F[6]';
    {
      matrix[(S-1)*(W-1),3] tq=token_q*F[4]';
      matrix[(R-1)*(W-1),3] pq=pair_q*FB';
      for (a in 1:3) {
        matrix[S,W] tt=HSA*to_matrix(tq[,a],S-1,W-1)*HW';
        matrix[R,W] pp=HRA*to_matrix(pq[,a],R-1,W-1)*HW';
        for (s in 1:S) for (w in 1:W) token_effect[token_lookup[s,w],a]=tt[s,w];
        pair_effect[,a]=to_vector(pp);
      }
    }
    rater_step[1]=step_sd[1]*HRA*rater_step_q1*HK';
    rater_step[2]=step_sd[2]*HRA*rater_step_q2*HK';
    for (a in 1:2) for (r in 1:R) {
      threshold_sum[a][r,1]=0;
      threshold_sum[a][r,2:9]=cumulative_sum(step[,a]+rater_step[a][r,]')';
    }
    profile("likelihood") {
    for (n in 1:N) {
      int r=rater[n]; int s=speaker[n]; int w=word[n];
      vector[3] eta=location(r,s,w,token[n],rater_group[r],regression[n,],within_time[n],l1_contrast[l1[n],],
          mean_effect,speaker_effect,word_effect,rater_effect,token_effect,time_effect,l1_effect,pair_effect);
      for (a in 1:2) {
        real slope=word_slope[w,a]*rater_slope[r,a];
        vector[9] logits=slope*(category_index*eta[a]-threshold_sum[a][r,]');
        parts[1]+=categorical_logit_lpmf(y[n,a] | logits);
      }
      binary_logit[n]=word_slope[w,3]*rater_slope[r,3]*eta[3];
    }
    parts[1]-=sum(log1p_exp(-binary_sign .* binary_logit));
    }
    parts[2]=std_normal_lpdf(to_vector(speaker_q))+std_normal_lpdf(to_vector(word_q))
        +std_normal_lpdf(to_vector(rater_q))+std_normal_lpdf(to_vector(token_q))+std_normal_lpdf(to_vector(time_q))
        +std_normal_lpdf(to_vector(l1_q1))+std_normal_lpdf(to_vector(l1_q2))
        +std_normal_lpdf(to_vector(word_slope_q))+std_normal_lpdf(to_vector(rater_slope_q))
        +std_normal_lpdf(to_vector(rater_step_q1))+std_normal_lpdf(to_vector(rater_step_q2))
        +std_normal_lpdf(mean_q)+std_normal_lpdf(to_vector(pair_q));
    for (a in 1:2) parts[2]+=normal_lpdf(step_q[,a] | step_mean,step_coordinate_sd);
    for (a in 1:3) parts[2]+=normal_lpdf(beta[,a] | 0,beta_sd[a]);
    parts[3]=normal_lpdf(step_sd | 0,step_sd_scale)+2*log(2)+normal_lpdf(pair_sd | 0,pair_sd_scale)+3*log(2);
    parts[4]=lkj_corr_cholesky_lpdf(L_pair | pair_lkj_eta);
    for (b in 1:6) {
      parts[3]+=normal_lpdf(sd[b] | 0,sd_scale[b])+3*log(2);
      parts[4]+=lkj_corr_cholesky_lpdf(L_cov[b] | lkj_eta);
    }
  }
  // Explicit normalized lpdfs retain constants; native constraints supply Jacobians.
  target+=sum(parts);
 }
}
