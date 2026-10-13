# ショパン2025・第1段階の分析入力と一次元基準モデル

2026-10-09：**氏名・ID・原資料位置付きの入力を受け入れ、既存MFRMへの接続を確認する段階。実データ推定と科学的な事前分布の採用はまだ行っていない。**
[応用候補の全体方針](application-portfolio.md)と、固定Q基盤のpilot→効率比較→fresh mainという優先順位を維持する。

**同日のユーザー訂正により、本書はモデルAPI確定後の応用計画として保存する。** 入力と接続の受入は完了したが、応用固有の事前選択・追加推定・分析レポートへは進まない。先に選択したモデルと共通の推定・診断・予測・保存／復元APIを合成データで検証し、支持範囲と版を確定する。以下の式と既存事前の記述は現状の接続候補を記録したもので、最終APIの採用仕様ではない。

## 1. 入力の受入範囲

[公式得点表](https://storage.nifc.pl/web_files/_plik/file_manager_pmp/files/475810_Chopin_Competition_2025_scores.pdf)の1〜3ページを対象とする。
[審査規則](https://storage.nifc.pl/web_files/_plik/file_manager/files/813353_Rules_Jury_last_02.10.ENG.pdf)のXII、XIIIに従い、1〜25の生得点、辞退 `s`、補正得点、補正平均を区別する。保存した両PDFのSHA-256を固定し、改訂版は再確認なしに取り込まない。

| 保存物 | 内容と確認条件 |
| --- | --- |
| `performances.json` | 84演奏。原表の番号から `C001`〜`C084`、段階付き演奏IDから `2025-S1-C001` 等を生成。番号は順位ではない。名前・姓は原表の別列を維持し、アクセント、複合名、略記を勝手に変更しない |
| `judges.json` | 原表の左から17列を `J01`〜`J17` へ対応。見出しの氏名、列番号、テキスト位置を保持。`J01` は Garrick Ohlsson、`J15` は原表どおり `K. Popowa-Zydroń` |
| `cells.json` | 全1,428セル。生のトークン、数値得点または `null`、辞退理由、補正トークン、PDFページ・ページ内テキスト行・審査員列を保持。辞退の補正 `0,00` はトークンのみ残し、得点は `null` |
| `ratings.json` | 1,395個の補正前整数得点だけ。演奏→`person`、審査員→`rater`、総合評価→単一 `item`。演奏×審査員の観測IDは原資料のセルへ戻れる |
| `stage1-layout.txt`, `manifest.json` | 抽出テキストと、元PDF／生成ファイルのハッシュ、Poppler版、カテゴリー別件数、審査員別件数。1〜25を宣言し、未観測1〜7も残す |

1人1行の補正前17セルと補正後17セルを照合する。第1段階の補正は、辞退を除いた**全生得点の平均（当該審査員の得点も含む）±3**への切り詰めである。セルは表示丸めの0.005以内、補正平均はセルと平均の表示丸めを合わせた0.01以内で検査する。小数表示は有理数として検査し、浮動小数点誤差で許容幅を広げない。

Popplerのレイアウト抽出に加え、別ライブラリ `pdfplumber` の文字座標から、84人の名前・姓、17審査員見出し、1,428生セルと1,428補正セルを照合した。3ページを画像でも確認した。これは原表に記載された名前との一致であり、外部の人物台帳による同定ではない。辞退理由の個別の人間関係も推測しない。

入力、座標照合、接続検査の記録はローカルの
[`20261009-chopin-stage1-input-01`](../../results/workflows/20261009-chopin-stage1-input-01/) に保存する。大きな生成物をGitへ追加せず、再生成するコードを追跡する。

## 2. 既存モデルで何を表すか

同じ第1段階の演奏 `p` と審査員 `r` に対する生得点 `Y` について、一次元の部分採点モデルを使う候補を準備した。

\[
\log\frac{P(Y_{pr}=k)}{P(Y_{pr}=k-1)}
=\theta_p-s_r-\tau_{k-1},\qquad k=2,\ldots,25.
\]

`θ` はこの段階の演奏位置、`s` は正なら厳しい審査員位置、`τ` は24個のカテゴリー遷移である。識別力は1、単一項目の位置は0、既存APIの基準審査員 `s[J01]=0`、`sum(τ)=0` とする。自由パラメータは84演奏＋16審査員＋23ステップ＝**123**。得点カテゴリーは順序を持つが、このPCMのステップ値には大小順の制約を課していない。単一項目なのでrating-scale／partial-creditの内容上の違いは生じない。

技術・表現等の別次元、審査員ごとの識別力、演奏×審査員の追加効果はこの基準モデルに含めない。観測は既存の84演奏・17審査員に限定する。後段階の選抜や演奏内容の変更を混ぜず、生涯の能力や新しい審査員集団への一般化を主張しない。条件付き独立性は検討する仮定であり、連結性や数値的識別だけから適合を結論しない。

### 事前分布は接続用候補であり、分析用の採用前

[`chopin_stage1_spec.jl`](../../scripts/chopin_stage1_spec.jl) は、既存の `MFRMPrior(person_sd=1.5, rater_sd=1, item_sd=1, step_sd=1)` を明示してコンパイルする。項目は固定されているので `item_sd` に対応する自由係数はない。この分布は**自由座標上**に独立な正規分布を置く。

- 演奏は `N(0,1.5²)`、基準以外の16審査員は `N(0,1)`。基準審査員には事前分布を置かない。審査員の順番を変えて同じ数値の事前を再設定すると、別の事前モデルになる。
- 最初の23ステップは `N(0,1)`、最後はその負の和。その最後の周辺標準偏差は `sqrt(23)`、各自由ステップとの共分散は `-1`。24ステップが対称な周辺分布になる設定ではない。
- 未観測の1〜7点も尤度の分母に含む。観測ゼロも情報だが、低得点側のステップを十分精密に推定できることは保証しない。

これらの基準依存と分散の性質は、まず制御された合成例を用いる基盤・APIの検討事項として扱う。API確定後にショパン分析を再開する際、事前予測の得点分布・極端カテゴリーの質量・審査員差とステップの尺度を確認し、確定したAPIの支持範囲から採用分布と感度比較を記録してから推定する。対称な制約空間上の事前を採用する場合、それは単なる座標変更と混同しない。報告用に `s-mean(s)`、`θ-mean(s)` へ事後変換することはできるが、それだけで事前の非対称性は消えない。

## 3. API確定後に再開する際の完了条件

| 段階 | 成果物と出口 |
| --- | --- |
| 入力・接続 | 原表の氏名・生得点・辞退・補正値を追跡でき、25カテゴリーを維持して123変数のターゲットを作れる。カテゴリー支持の警告を保存し、ゼロ係数時の対数尤度が `-1395 log(25)` と一致する |
| 再開の前提：モデルAPI確定 | [ROADMAPのMS6](../../ROADMAP.md#completion-milestones)で、支持範囲の判断・共通API検証・独立レビューを経たAPI確定を受け入れていること。必要な一次元モデルと予測がその対応範囲に含まれること。今回の個別アダプタの検査通過だけではこの条件を満たさない |
| 推定前の仕様確定 | 上記の事前予測と尺度・基準依存を点検し、採用する事前、感度候補、焦点量、MCMC診断とMCSEの判定条件を保存する。計算を走らせる前に決め、結果に合わせて緩めない |
| 最初の実分析 | 演奏位置と審査員差の区間、事前感度、カテゴリ支持、事後予測による適合を提示。診断・MCSEが未達の量を明示し、保存したdrawから再生成できる |
| 比較の解釈 | 生の平均・公式補正平均・モデルの条件付き予測を同じ対象の表へ対応づける。公式補正は他審査員に依存する集計規則であり、独立の評定データや別の確率モデルではない。予測性能を主張するなら、既存水準の保留セルなど予測対象と分割を先に定める |

応用を再開した際の焦点候補は審査員の相対的位置と演奏位置の不確実性。順位の優劣や審査の公平性を断定するものではない。全136審査員ペアの差や順位確率を探索的に増やす前に、比較対象と精度条件を定める。実データfitの収束は、既知真値での回復・被覆や進行中の基盤評価の代わりにならない。

## 4. 再生成と限定検査

保存済みのPDFを使う。出力先は存在しないディレクトリ／ファイルを指定する。

```sh
python3 scripts/chopin_stage1_input.py \
  --scores results/workflows/20260923-application-scope-01/chopin-scores.pdf \
  --rules results/workflows/20260923-application-scope-01/chopin-rules.pdf \
  --output results/workflows/NEW-chopin/input
python3 test/chopin_stage1_input.py
julia --project=. test/chopin_stage1_spec.jl results/workflows/NEW-chopin/input
julia --project=. scripts/chopin_stage1_spec.jl \
  results/workflows/NEW-chopin/input results/workflows/NEW-chopin/spec.json
```

取り込み処理はPython標準ライブラリとインストール済みPoppler、接続は既存Julia依存を使う。PDF更新・テーブル構造変更はハッシュまたは受入検査で停止する。これらのコマンドはMCMCを開始しない。パッケージ本体、通常テスト入口、実行中pilotの固定ソースは変更しない。

## 5. Ordinal prior and API boundary audit (2026-10-13)

The [sampler-free audit](../../scripts/ordinal_prior_boundary_audit.jl) checks the
remaining model-choice boundary on **artificial** ratings: six persons, one
item, 17 raters and K = 2, 3 or 25. The K = 25 fixture observes only categories
8–25 but declares 1–25. It does not read competition inputs, choose an empirical
prior, fit a model or estimate prediction performance. The tested package is the
published development commit `fe523ff8f50c6f0d1b3ba57263731e9c80a3422f`.
The [receipt](../../results/workflows/20261013-ordinal-prior-boundary-01/verification.json)
records 57 passing assertions, independent exact-arithmetic scale calculations,
and the unchanged empirical inputs and frozen study sources.

### What the existing scalar prior implies

The compiled K = 25 likelihood retains all 25 categories and agrees with an
independently evaluated adjacent-category formula using a BigFloat normalizer.
At zero coordinates, each probability is 1/25; the combined probability of
unobserved categories 1–7 is 7/25. This is a likelihood sanity check at one
coordinate, **not** a prior-predictive average or an empirical score prediction.
Omitting those possible categories changes the model's denominator.

The actual log-prior Hessian and threshold reconstruction give, with step SD s,

\[
\operatorname{Var}(\tau_1)=\cdots=\operatorname{Var}(\tau_{23})=s^2,
\qquad \operatorname{Var}(\tau_{24})=23s^2,
\qquad \operatorname{Cov}(\tau_j,\tau_{24})=-s^2.
\]

The last step's SD is therefore sqrt(23), approximately 4.80 times the free-step
SD. The prior is proper and matches the implemented free-coordinate policy;
the concern is its substantive interpretation, not a missing Jacobian or a
likelihood error. K = 3 has two equally variable opposite steps, while K = 2
has one structurally zero step. Small-category evidence alone can hide the
asymmetry that becomes prominent at K = 25.

Two finite counterexamples separate likelihood and prior claims:

- Reversing the category direction, reversing/negating the step ladder and
  negating the locations preserves all response probabilities after reversal.
  Reusing the same independent free-step priors changes the log-prior by -2.64
  at the recorded artificial point.
- Changing the reference from one physical rater to another, with corresponding
  person/severity shifts, preserves every observed-row log likelihood. Reusing
  the same independent priors changes the log-prior by 2.075 at the recorded
  artificial point. Reporting centered posterior severities does not change
  the distribution used during estimation.

These examples demonstrate noninvariance under the stated reuse of priors;
they do not quantify the resulting posterior sensitivity in competition data.

### Which existing API can express an alternative?

| Existing route | Severity/step prior and location convention | Consequence |
| --- | --- | --- |
| Scalar `mfrm_spec` with `MFRMPrior` | First rater and the only item are fixed at zero; free severities/steps have independent normal priors | This is the accepted input adapter's compatibility route. Keep its anchor and asymmetric step implications visible. |
| `Experimental.ExchangeablePrior` | Exchangeable severities for multidimensional fixed-coefficient MFRM; free-step priors retain their old meaning | The scalar specification is rejected. This selector is neither a scalar remedy nor an exchangeable-step option. |
| D1 MGMFRM with `slope_restriction(...; item_slopes=:fixed_one, rater_consistency=:fixed_one)` and normalized exchangeable prior | Both severity and step vectors are centered with symmetric kernel priors; person and item locations are prior-anchored | Already available as an experimental Julia route. The literal response scale is 1.7 and the single item remains free. It is a distinct Bayesian target. |

The last route has 46 free coordinates in this fixture versus the scalar route's
45. Rescaling locations and steps by 1/1.7, and accounting for the item/rater
location shift, reproduces the scalar likelihood at the checked nonzero point.
The audit also reconstructs its normalized severity/step covariance from its
actual prior Hessian. Neither result establishes identical priors or posteriors.
No new scalar API or additional sampler was introduced for this audit.

### Match a declared quantity before comparing prior scales

For the scalar reference-rater prior, 16 of the 136 rater contrasts have variance
s² and 120 have variance 2s². Their mean variance is (32/17)s². A symmetric
zero-sum Gaussian kernel with SD t has contrast variance 2t², so matching that
mean requires **t = sqrt(16/17)s**, not sqrt(2)s. The latter rule belongs to a
different negative-sum free-rater prior and must not be copied into this chart.

For the 24 negative-sum steps, 253 contrasts have variance 2s² and 23 have
variance 26s²; their mean is 4s². Here the corresponding matching rule is
**t = sqrt(2)s**. These rational-arithmetic checks are independent of the Julia
Hessian calculation. They match an unweighted average, not each contrast or the
whole prior. The D1 model additionally requires the 1.7 unit conversion and an
explicit person/item location-prior decision. These conversions are not selected
scientific SDs or evidence of prior plausibility.

### Decision and remaining work

Retain both existing routes with their actual names and meanings. Do not silently
replace the input adapter's prior, infer an exchangeable scalar implementation
from the selector's name, or rerun the real data to choose a convenient prior.
The next model-specific preparation is a declared contrast-scale and
prior-predictive comparison on synthetic high-category ratings, using the
existing D1 route where its full model is intended. A posterior performance
claim still requires its own adequately precise evidence; the current checks
do not require another large simulation or a new model family.

Empirical fitting keeps the relevant supported-API/MS6 condition in Section 3.
The audit closes the 25-category algebra/API clarification, not prior adoption,
recovery, calibration or independent review. Runtime and published sources are
unchanged. One initial audit-script error extracted an entire NamedTuple instead
of its `direct_draws`; the corrected run passes all 57 checks. The initial 56
passes are retained and not added as independent evidence. Only Julia 1.12.5
was run here; earlier native Stan evidence is reused for its recorded scope,
without claiming a new K = 25 Stan verification.

To reproduce this optional check from a checkout containing the audit script,
use a Julia project with the recorded package revision:

```sh
julia --project=YOUR_ANALYSIS_PROJECT scripts/ordinal_prior_boundary_audit.jl NEW_REPORT.json
```

## 6. Synthetic high-category prior predictions (2026-10-13)

**Decision:** matching the average step-contrast variance does not match the
distribution of ratings. Exchangeable steps remove the distinguished last-step
prior, but that change alone does not make a complete model's prior predictions
plausible for an application. The illustrative complete priors below place
56.60–66.34% of their rating probability on categories 1 and 25. No application
prior is selected and no competition data are fitted.

The [optional script](../../scripts/ordinal_prior_predictive_probe.jl) answers
the next question in Section 5 using the unchanged published package revision.
The [prospective settings](../../results/workflows/20261013-ordinal-prior-predictive-01/plan.json)
fix the cells, seeds, draw counts and descriptive quantities before execution.
The [verification record](../../results/workflows/20261013-ordinal-prior-predictive-01/verification.json)
retains all results, computation costs and the separate verification-stage
interruption. It is an exploratory modeling check, not a preregistered
confirmatory study or evidence of posterior calibration.

### Separate the step mechanism from the complete model

The controlled comparison holds the unit-logit rating location at -2, 0 or 2
and varies only the step prior. A negative-sum free-step prior with SD s is
compared with a symmetric zero-sum Gaussian with kernel SD sqrt(2)s. Both have
mean pairwise step-contrast variance 4s². The two values s = 0.25 and 1 are
illustrations, not recommended defaults. Each cell uses the same 4,096 IID
normal vectors, allowing draw-wise paired differences and paired MCSE. K = 3
is an exact-distribution control: the two step constructions coincide there.
The K = 25 results therefore are not inferred from a small-category check.

At location zero, the endpoint probabilities are equal within each draw because
the steps sum to zero. The free-step prior can nevertheless give an asymmetric
*interior* probability profile. The exchangeable prior is invariant to reversed,
negated steps, so its integrated profile is symmetric around category 13;
finite Monte Carlo averages retain sampling error.

| Controlled K = 25, location = 0 | Free-step prior | Exchangeable steps | Exchangeable minus free, paired MCSE |
| --- | ---: | ---: | ---: |
| Expected score, s = 0.25 | 13.132 | 13.019 | -0.113 (0.025) |
| Endpoint probability, s = 0.25 | 8.548% | 7.878% | -0.670 (0.027) percentage points |
| Expected score, s = 1 | 13.697 | 13.083 | -0.614 (0.060) |
| Endpoint probability, s = 1 | 11.766% | 7.069% | -4.697 (0.146) percentage points |

The complete-model comparison instead uses the actual public prior-predictive
generators on an artificial complete design of six persons, one item and
17 raters (102 rows). It declares categories 1–25 although the artificial input
scores use only 8–25. Those scores never condition the prior generation or
determine the selected scales; observed-score reference marks are not interpreted.
Each of four cells generates 2,048 independent parameter/response draws.

- The scalar model has person SD 1.5, reference-rater severity zero, other
  severity SDs 1, the item fixed at zero, and free-step SD s.
- The normalized D1 model fixes both slopes at one. In unit-logit units it has
  person SD 1.5, an **additional independent item SD 1**, centered severity
  kernel SD sqrt(16/17), and centered step kernel SD sqrt(2)s. Its supplied raw
  SDs are divided by 1.7. The mean pairwise severity and step-contrast variances
  match the scalar construction, but individual contrasts and the full joint
  distribution do not. The random item also creates a shared location shift.

In the scalar model, the rating-location variance is 2.25 for the reference
rater and 3.25 for each other rater (average 3.191). In the normalized model it
is `2.25 + 1 + (16/17)^2 = 4.136` for every rater. Thus matching mean rater
contrasts deliberately does not assert matched marginal rating locations.

| Complete model prior | s | Expected score (MCSE) | Endpoint probability (MCSE), % |
| --- | ---: | ---: | ---: |
| Scalar MFRM | 0.25 | 12.992 (0.079) | 62.381 (0.255) |
| Normalized D1, fixed slopes | 0.25 | 13.119 (0.121) | 66.336 (0.203) |
| Scalar MFRM | 1 | 13.111 (0.079) | 56.597 (0.531) |
| Normalized D1, fixed slopes | 1 | 12.890 (0.121) | 60.006 (0.391) |

These complete-model differences must **not** be attributed solely to step
exchangeability. Probabilities are averaged equally over the 102 artificial
rows, integrating response randomization analytically. MCSE uses the independent
complete prior vector as its unit; the 102 rows are not treated as independent
simulation replications. Replicated scores and their separate summaries are
also retained and checked. All cells and the -2/+2 controlled results remain
available in the saved records; the figure emphasizes the zero-location contrast.

![Synthetic category probability profiles](../../results/workflows/20261013-ordinal-prior-predictive-01/prior-profiles.png)

**Figure. Prior category probabilities under the declared artificial settings.**
Panels A/C isolate the step prior at location zero; B/D use the distinct complete
model priors. Vertical scales differ across panels. Shaded bands are pointwise
mean ± 1.96 MCSE, clipped at zero for display. They are Monte Carlo precision
bands, not parameter credible intervals, prior predictive intervals or
simultaneous uncertainty bands. Notes are outside the image.

### Implication, API scope and verification

A mean score close to 13 can hide considerable probability on 1 and 25. Narrower
steps do not necessarily spread ratings across the middle of the scale. With
all steps zero, the category weights are `1, exp(eta), ..., exp(24eta)`; they
are uniform only at eta = 0. More generally, a zero-sum ladder fixes the ratio
of endpoint weights at `exp(24eta)`, while the cumulative steps determine the
intermediate weights and normalizing denominator. This explains why location
priors and step shape need joint interpretation.

The earlier [A0 mechanism review](paired-rating-prior-review.md) already derives
the role of ordered steps and category-mode regions. Reuse that evidence rather
than repeating its seven-condition experiment. This new check contributes the
25-category, reference-rater and currently available API context. It does not
establish that ordered steps are necessary, or that a lower endpoint probability
is inherently better. The next specification decision concerns scientifically
intended location, step order/shape and contrast scales together, before any
larger simulation or empirical fitting. Scientific prior adoption and the
relevant supported-API/MS6 boundary remain open.

`BayesianMGMFRM.prior_predictive_check` handles the scalar route;
`Experimental.prior_predictive_check` handles the explicit normalized,
slope-restricted route. The existing `prior_predictive_sensitivity` wrapper
only compares log-loading SDs and does not represent this cross-model/step-prior
comparison. No new public API or change to a default was needed here. The
optional audit uses internal coordinate access to verify the public generators;
it is not a newly supported analysis interface.

All 194 Julia checks pass. Independent NumPy/SciPy recomputation from the saved
coordinates passes 2,824 array/summary checks, with maximum absolute difference
6.40e-14 across the quantities checked. This is a separate implementation check
by the same analyst, not independent scientific review. The Julia stage took
56.27 s including startup, with observed peak RSS 1.55 GiB. Successful saved-draw
verification and plotting took 11.43 s. An initial 0.58 s plotting-stage
interruption arose when a descendant changed process group; the existing guard's
identity-tracked descendant-group option allowed that stage to finish. No prior
draws were regenerated. There were zero posterior fits, new empirical analyses,
changes to the 526 frozen MS3 files, or public source/guide updates. Only Julia
1.12.5 and the recorded Python environment were checked; no new native Stan or
full-suite run is claimed.

To reproduce with the recorded package revision in a separate Julia project:

```sh
julia --project=YOUR_ANALYSIS_PROJECT scripts/ordinal_prior_predictive_probe.jl NEW_OUTPUT_DIRECTORY
```

## 7. Location, mean profile and order: specification decision (2026-10-13)

**Decision:** the next smallest implementation candidate is an explicit,
opt-in Gaussian **mean profile** for locations and centered steps on the
existing normalized D1, fixed-slope route. This is an engineering direction,
not adoption of numerical priors for Chopin or a new public API. A hard ordering
constraint remains a different model and is not made a prerequisite for every
PCM analysis. This bounded specification review is complete; do not repeat the
A0 mechanism grid or the Section 6 simulations to reach the same decision.

### What should a user be able to specify?

| Choice | Interpretation | Current support and boundary |
| --- | --- | --- |
| Reference rating location | Where a stated reference person/rater lies relative to the category ladder | Current scalar and normalized constructors center their free location priors at zero. An item/ability mean cannot be supplied through these prior constructors. Changing a hard anchor is not an equivalent change to a prior mean. |
| Centered step mean profile | The typical arrangement of adjacent transitions, separately from overall location | Current step priors have zero mean in their declared coordinates. An arbitrary centered mean vector is not accepted. |
| Residual step width | Uncertainty around that profile, expressed in kernel or contrast units | Current scale parameters exist, but their meanings differ between the scalar free-step and normalized centered priors. Matching an average contrast does not match the entire prior. |
| Hard versus soft ordering | Whether every step vector must be ordered, or reversals remain possible | Neither a symmetric zero-mean prior nor an ordered mean vector imposes hard ordering. The previous A0 sorting experiment is a mechanism check, not a fitting option. |

Threshold ownership is a separate choice. A profile must be attached to the
actual ladder's category order and owner/group IDs; it is not automatically a
person, item or rater effect. The first proposed implementation scope retains
the current item-owned D1 PCM ladders and fixed coefficients. The broader
shared/criterion/rater-group roadmap, mixed-category models and two free slope
blocks are not silently included.

### A reference probability profile separates location and shape

For K ordered categories, let H = K-1 and let q be a strictly positive vector
summing to one. Here q describes a scientifically specified **reference**
person/rater at fixed parameter values. It is not an observed frequency vector
to fit automatically, nor a population-average prior prediction. For the
unit-logit PCM, the adjacent log odds are

\[
\log(q_{h+1}/q_h)=\eta_0-m_h,\qquad \sum_{h=1}^H m_h=0.
\]

Therefore the unique location and centered step profile are

\[
\eta_0=\frac{\log q_K-\log q_1}{H},\qquad
m_h=\eta_0-(\log q_{h+1}-\log q_h).
\]

At a reference ability and severity of zero, the corresponding item mean is
`-eta_0`. This fixes the prior-location convention: do not independently give
ability and item means free common shifts and then claim data identification.
On the existing normalized fixed-slope route, divide location/step means and
their SDs by the literal 1.7 constant. With variable coefficients the meaning
of a reference profile also depends on their specified values, so this mapping
is not an unqualified generalized-model option.

The finite checks use six artificial profiles: binary uniform, a three-category
central profile, and four 25-category profiles (uniform, two bell-shaped
profiles and a two-mode profile). They recover each complete probability vector
from the derived location/steps, preserve the category-reversal transformation,
and reject zeros, negative/nonfinite values, invalid normalization and positive
values that underflow in Float64. A zero probability cannot be represented by
finite PCM coordinates; it must not be silently replaced by a small constant.

For illustration, weights proportional to `exp(-(k-c)^2/(2*4^2))`, k = 1,...,25,
have step means `m_h=(h-12.5)/16`. Moving c from 13 to 19 leaves that centered
shape unchanged and moves the reference location from 0 to 0.375. The item
mean moves from 0 to -0.375. The number 4 is the width of these score-space
weights; it is not a latent-person SD or residual-step SD. None of these numbers
is a selected competition prior.

Probabilities evaluated at the means generally differ from probabilities
averaged over the prior. The proposed profile would still require joint prior
prediction with all declared uncertainties; the [Stan prior-predictive
definition](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html#prior-predictive-checks)
integrates over prior parameter uncertainty.

### Soft ordering, hard ordering and their densities

For a proposed centered Gaussian residual with kernel SD t,

\[
\tau=m+\epsilon,\qquad
\operatorname{Cov}(\epsilon)=t^2(I-11^\top/H).
\]

Its marginal step SD is `t*sqrt((H-1)/H)` and any step-difference SD is
`sqrt(2)*t`. The **residuals** are exchangeable. With a nonconstant mean profile,
the full step prior is not exchangeable across category positions, and its
label/metadata must say so. Rater exchangeability is a separate policy.

For an adjacent mean gap d, the probability of a reversal is
`Phi(-d/(sqrt(2)*t))`. In the artificial bell profile above, d = 1/16, giving
42.98% for t = 0.25 and 48.24% for t = 1. These are probabilities for **one
adjacent pair**, not the probability of any reversal in the ladder. An ordered
mean can therefore leave substantial disorder. Smaller residual variance or a
hard constraint expresses a stronger assumption, not an automatic improvement.

The inversion formula also gives

\[
m_{h+1}-m_h=2\log q_{h+1}-\log q_h-\log q_{h+2}.
\]

Thus a nondecreasing step profile corresponds to log-concavity of this reference
probability vector. Hard ordering restricts which reference shapes can occur;
the tested two-mode profile requires a reversal. This concerns the conditional
profile, not a claim that mixtures over people must be unimodal.

For free step coordinates v of length H-1, with the last step reconstructed as
the negative sum, the normalized mean-profile density is

\[
\log p(v)=-(H-1)\log(t\sqrt{2\pi})+\tfrac12\log H
-\frac{\|v-m_{1:H-1}\|^2+
 [1^\top(v-m_{1:H-1})]^2}{2t^2}.
\]

Fixed mean translation introduces no new Jacobian and leaves the precision
matrix unchanged. At H = 1 (binary responses), the step shape is structurally
zero and contributes no density. The [Stan constraint reference](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms)
distinguishes a symmetric constrained Gaussian from independent free coordinates
with a final negative sum. The formula here uses the package's last-reconstructed
coordinate measure, not Stan's orthonormal coordinates.

Hard ordering would require a separately normalized target and coordinate
handling. The earlier A0 factor H! is valid for its exchangeable continuous
prior. It cannot be copied to this nonconstant mean profile: for two steps with
means (-1,1) and kernel SD 1, the ordering probability is 0.921350, so conditioning
on order multiplies the density by 1.08536, not 2. Sorting a nonexchangeable
draw instead creates a permutation-mixture law, a third construction. None is
implemented by sorting parameters during an existing likelihood evaluation.
Stan's [ordered-vector transform](https://mc-stan.org/docs/reference-manual/transforms.html#ordered-vector)
likewise has its own change-of-variable handling; an ordered declaration is
not a reason to omit prior normalization when it depends on model parameters.

### Verified boundary and next implementation scope

The [optional finite audit](../../scripts/ordinal_prior_specification_audit.jl)
passes 82 Julia assertions on the published package revision. For K = 2, 3 and
25, a private mean-shift prototype agrees with the explicit normalized Gaussian
density and its gradients, preserves the Hessian, reduces to the old density
at zero means, and reproduces the intended reference probabilities through the
existing likelihood. The likelihood always uses actual parameter coordinates;
only the prior evaluates centered residuals. Existing constructors explicitly
reject the unsupported mean keywords.

Independent SciPy covariance-based normal densities and analytic precision
gradients pass 36 additional comparisons; the maximum checked discrepancy is
7.46e-14. The [receipt](../../results/workflows/20261013-ordinal-prior-specification-01/verification.json)
records the cases and preserved sources. This is same-analyst verification,
not independent scientific review. There are no new prior draws or posterior
fits. Julia execution including startup took 41.65 s (observed peak RSS
1.18 GiB); Python verification took 0.60 s. Native Stan execution, fitted
workflow, cross-version checks and calibration for this new profile are pending.

An implementation increment must carry the same explicit means and units
through prior generation, fitting, initialization, diagnostics, named summaries,
prediction/refit, save/reload, help and the prior record. Preserve old zero-mean
records and their identities; new nonzero-profile records need a distinct
canonical policy/version and exact category/owner alignment. They must not be
silently read as the existing exchangeable-step prior. The first scope is fixed
hyperparameters and item-owned, independent D1 fixed-slope Gaussian profiles;
it does not add hard ordering, estimated profile hyperparameters, pooling, new
threshold owners or a scalar-prior migration. Native backend agreement and a
small complete workflow check precede any new performance study. Prior adoption
and empirical use retain the relevant scientific/API acceptance boundary.


## 8. Mean-profile API candidate and workflow check (2026-10-13)

**Outcome:** the optional location/step-mean policy from Section 7 now has an
isolated implementation, `Experimental.MeanProfilePrior`. It extends the
published source in a separate [candidate](../../results/workflows/20261013-mean-profile-candidate-01/candidate/)
and preserves the published runtime and all 526 MS3 files. It is not merged,
released or included in the October GitHub preview. The
[verification receipt](../../results/workflows/20261013-mean-profile-candidate-01/verification.json)
binds source, environment, numerical checks and saved results.

The question for this increment was whether one explicit fixed prior policy
could survive the whole user workflow, without silently changing its statistical
meaning between generation, fitting and reuse. `MeanProfilePrior(model, base;
item_means, step_means, category_levels, units)` accepts dictionaries for every
actual item ID and the complete declared category order. The first scope remains
independent D1, item-owned PCM with item slopes and rater consistency fixed at
one. Person/rater means remain zero; item means set reference locations. K-1
step means sum to zero, excluding the structural baseline. Binary step shape is
zero. Units are explicit; `:unit_logit` converts supplied means by 1.7 while base
SDs remain raw. A distinct canonical prior record retains raw means and IDs;
legacy zero-mean schemas and target identities remain unchanged.

The implementation translates only the Gaussian prior and its generator; the
likelihood always evaluates actual coordinates. Initialization uses the declared
means. Summaries, reports, existing-level K-fold requests and manual saved fits
retain the same profile. Full step priors with nonconstant means are distinguished
from their exchangeable residuals. Ordered means impose no hard ordering.
English REPL help, a no-sampling named-item example and the local manual describe
this distinction and the difference between reference probabilities and joint
prior predictions. Existing prior-sensitivity wrappers still vary loading SD
only; they do not compare arbitrary mean profiles.

### Evidence and what it establishes

- 2,639 connected prior/slope regression assertions passed. After correcting two
  new test call-site mistakes, 161 profile-specific assertions passed, including
  K=2/3/25, R=1/3, normalized densities/gradients, mean-unit conversion,
  coupled prior generation, malformed input rejection, saved records, reports
  and heldout-target mismatches. Successful regressions were reused.
- A separately written native CmdStan 2.39 model checked zero/nonzero means at
  three parameter points for each K/R combination. All 48 density/gradient
  assertions passed; maximum absolute differences were 8.53e-14 and 6.54e-13.
  These are same-analyst finite implementation checks, not independent scientific
  review or a new public CmdStan fitting backend.
- Exactly one artificial training fit used two chains, 10 warmup and eight retained
  draws per chain. It saved before reporting, and its **sampler_warning** was
  retained (three maximum-tree-depth hits, zero divergences, and insufficient
  draws for the rank diagnostics). The first harness incorrectly expected an overall insufficient-draws
  flag and attempted direct JSON encoding of a report containing NaN diagnostics.
  The saved fit was reused through the existing `save_fit_report`/`load_fit_report`
  API; no sampling was repeated. Nine saved-workflow assertions passed; a test that assumed insertion order
  instead of the actual canonical item order was corrected in the six passing
  fresh-process assertions. One of two prepared folds was scored; this is
  not a completed cross-validation comparison.
- The affected English manual was built and its local links checked. This is
  local documentation validation, not publication or browser acceptance of a
  new public release.

This closes the bounded implementation/workflow question, not the scientific
choice of means or residual scales. The short fit does not establish convergence,
recovery, coverage, SBC or predictive performance; its warning is evidence to
retain, not a reason to automatically extend the run. Higher dimensions, free
slopes, hard ordering, learned hyperparameters, other threshold owners and
scalar-prior migration remain outside this increment. No new application prior
or Chopin/Uchihara/EVA estimate is adopted. Return this capability to the existing
MS5/MS6 acceptance work; neither a new prior grid nor extra performance study is
made a prerequisite merely because the option now exists. MS3 continues under
its original fixed design.
