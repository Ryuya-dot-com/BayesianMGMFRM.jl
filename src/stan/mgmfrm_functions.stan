  vector mgmfrm_eta(
      int person_id,
      int rater_id,
      int item_id,
      int J,
      int R,
      int I,
      int K,
      int D,
      int NLoadings,
      int free_steps,
      array[] int LoadingItem,
      array[] int LoadingDim,
      vector beta) {
    vector[K] eta;
    int rater_offset = J * D;
    int item_offset = rater_offset + R - 1;
    int loading_offset = item_offset + I;
    int consistency_offset = loading_offset + NLoadings;
    int step_offset = consistency_offset + R - 1;
    real rater = rater_id < R
      ? beta[rater_offset + rater_id]
      : -sum(segment(beta, rater_offset + 1, R - 1));
    real log_consistency = rater_id < R
      ? beta[consistency_offset + rater_id]
      : -sum(segment(beta, consistency_offset + 1, R - 1));
    real item = beta[item_offset + item_id];
    real ability_score = 0;
    real cumulative = 0;
    real scale = 1.7 * exp(log_consistency);

    for (loading in 1:NLoadings) {
      if (LoadingItem[loading] == item_id) {
        int dimension = LoadingDim[loading];
        real discrimination = exp(beta[loading_offset + loading]);
        ability_score += discrimination *
          beta[(person_id - 1) * D + dimension];
      }
    }

    eta[1] = 0;
    for (k in 2:K) {
      int step_number = k - 1;
      int first_step = step_offset + (item_id - 1) * free_steps + 1;
      real step = 0;
      if (free_steps > 0)
        step = step_number <= free_steps
          ? beta[first_step + step_number - 1]
          : -sum(segment(beta, first_step, free_steps));
      cumulative += scale * (ability_score - item - rater - step);
      eta[k] = cumulative;
    }
    return eta;
  }
