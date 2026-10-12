# MGMFRMの事前選択：用途、交換可能性、尺度の意味

2026-09-24。**評定者IDが単なるラベルで、特定の評定者を事前に区別する根拠がない用途では、正規化exchangeable事前を次の科学的候補として優先する。現行raw事前は既存結果と計算参照のために保持し、source事前は指定した参照対象との比較に使う。** これは構造上の推奨であり、新しい既定値や具体的なSDの採用ではない。既存の式・実装から導出し、追加MCMCなしに確認した。

**実装接続の続報（同日、第9節）:** 内部のnormalized MGMFRMについて、同じ明示事前記録から事前予測を生成し、保存済み標本の復元時にも尺度・分布・適用モデルの説明を再構成できるようにした。公開APIの拡張や事前の既定値変更ではない。

## 1. 何を選ぶ判断か

[推定対象と識別性](mgmfrm-estimands-identification.md)の整理では、条件付き尤度に原点・尺度の不定性がある一方、明示したproperなraw事前の下では事後分布が存在することを示した。今回は、その事前が人物・項目・評定者の比較にどのような基準と非対称性を与えるかを問う。

事前の交換可能性は、全評定者を同じ値に固定することではない。対応する評定者を一緒に改名・並べ替えたとき、同じ事前確率を与える性質である。職務・訓練・所属群などによる差を想定する用途で、全員の交換可能性を無条件に要求するものではない。本書の既存候補には、そのような群別事前や階層尺度推定は含まれない。

## 2. 数学上の候補と実際の利用経路

| 候補 | 現在の実装 | 適した役割 | 採用時に残る条件 |
| --- | --- | --- | --- |
| raw | `Experimental.GeneralizedPrior`。公開された実験的MGMFRMのfit・事前予測・保存経路 | 既存の初回候補、計算・実装の参照、過去の結果の再現 | 最後の評定者・ステップを区別する分布を受け入れ、ID対応を保持する |
| normalized exchangeable | 内部の `_MGMFRMNormalizedPriorLogDensity(...; prior_model=:exchangeable)` | 評定者IDに依存しないことを要求する用途の次候補 | SDの意味、事前予測、公開API・保存・報告への統合と検証 |
| normalized source | 同じ内部ターゲットの `prior_model=:source` と明示 `source_rater` | 保存したsource参照ターゲットとの数式・backend比較 | 区別する評定者ID・測度・尺度を固定する。一般的な対称事前として扱わない |

**公開 `Experimental.ExchangeablePrior` は固定係数MFRM用で、推定負荷量を持つMGMFRMには使えない。** また、初回候補の比較で使った `source_aligned` というraw尺度設定は、normalized source事前とは異なる。単にrawのSDを全て1へ変えてもsource事前にはならない。

正規化MGMFRMの内部参照と固定係数MFRMの公開事前も同一ではない。前者は厳しさ・log一貫性・項目ステップを正規化したゼロ和ブロックで扱う。後者の `ExchangeablePrior` は評定者厳しさを交換可能にし、固定係数モデルの自由ステップ事前を保持する。

本書は既存のsource実装の測度と分布を点検する。原著全体との完全再現を新たに確認したものではなく、sourceの名称からその承認を推測しない。[過去のbackend比較](normalized-prior-backend-comparison.md)も、その対象・条件に限った数値的証拠として扱う。

## 3. ゼロ和ブロックの分布

長さnのゼロ和ベクトルを `z=Cv`、`C=[I_(n−1); −1ᵀ]` とする。vは最後を除いた自由座標で、密度はdvに対して定義する。厳しさではn=R、log一貫性でもn=R、各項目の非基準ステップではn=K−1である。

### raw：自由座標が独立

`v ~ N(0, sigma² I)` から、

```math
\operatorname{Cov}(z)=\sigma^2 CC^\top,\qquad
\operatorname{Var}(z_j)=\sigma^2\ (j<n),\qquad
\operatorname{Var}(z_n)=(n-1)\sigma^2.
```

自由座標同士の対比分散は `2 sigma²`、自由座標と最後の座標の対比分散は `(n+2)sigma²`。n>2では非交換可能である。ゼロ和という制約だけでは、周辺分散や対比の不確実性は揃わない。

### exchangeable：全座標を対称にする

既存実装の正規化密度は、

```math
g(v;\tau)=\frac{\sqrt n}{(2\pi\tau^2)^{(n-1)/2}}
 \exp\!\left[-\frac{v^\top v+(\mathbf1^\top v)^2}{2\tau^2}\right].
```

自由座標の共分散は `tau²(I_(n−1)−11ᵀ/n)`、全座標では

```math
\Sigma=\tau^2(I_n-\mathbf1\mathbf1^\top/n).
```

従って全ての周辺SDは `tau sqrt((n−1)/n)`、全ての対比SDは `sqrt(2) tau` になる。τはkernel SDであり、全座標の周辺SDそのものではない。全座標の正規核を自由座標に制限した際の精度行列は `CᵀC`、その行列式はnなので、上の正規化定数を得る。

### source：log一貫性に線形項が加わる

sourceの厳しさ・ステップは同じgを使う。log一貫性ℓ=logγでは、指定した評定者qについて、

```math
g_{\rm source}(v;\tau,q)
=g(v;\tau)\exp[-\ell_q-\tfrac12\tau^2(R-1)/R].
```

これは単なる定数差ではない。gの下で `E[exp(−ell_q)]=exp(tau²(R−1)/(2R))` なので正規化され、平方完成から、

```math
E[\ell]=\tau^2(\mathbf1/R-e_q),\qquad
\operatorname{Cov}(\ell)=\tau^2(I_R-\mathbf1\mathbf1^\top/R).
```

すなわち分散・共分散はexchangeableと同じでも、指定評定者のlog一貫性平均は `−tau²(R−1)/R`、他の評定者は `tau²/R` となる。

この線形項は、積1の全γにlognormal核を置き、q以外の正の自由γからlog座標へ移すという既存の測度から導ける。全ベクトルでは `sum ell=0` だが、自由座標の変数変換は `exp(sum_(r≠q) ell_r)=exp(−ell_q)` を与える。一方、rawは初めから自由log座標の正規密度を定義する。rawにこの項がないことをヤコビアンの欠落と扱わない。

qはγ=1に固定したgold-standard評定者ではない。qを取り替えると事前が変わる。単なるIDの変更ならqの実体も一緒に対応させる必要がある。既存source実装が区別を設ける理由と、利用者がその評定者に持つ実質的な知識を混同しない。

## 4. 初回候補と同じ数値のSDを入れたとき

R=5、厳しさのσまたはτを1、log一貫性のσまたはτを0.5とした計算値を示す。**同じ数値を与えた分布の比較であり、公平な尺度一致や事前の採用を意味しない。** sourceのqは明示的に選んだ一人で、最後の自由度を再構成する評定者と同じとは限らない。

| 性質 | raw | exchangeable | source |
| --- | --- | --- | --- |
| 厳しさの周辺SD | 自由な4人は1、最後は2 | 全員0.894427 | 全員0.894427 |
| 厳しさ差のSD | 自由同士1.414214、最後との対比2.645751 | 全対比1.414214 | 全対比1.414214 |
| log一貫性の平均 | 全員0 | 全員0 | qは−0.20、他は+0.05 |
| log一貫性の分散 | 自由な4人は0.25、最後は1 | 全員0.20 | 全員0.20 |
| 一貫性γの事前平均 | 自由な4人は1.133148、最後は1.648721 | 全員1.105170 | qは0.904837、他は1.161834 |

sourceのqと他のjのlog比は `N(−tau²,2tau²)` である。τ=0.5なら `gamma_q/gamma_j` の中央値は0.778801だが、算術平均は1となる。平均だけを見て「両者を同じ事前で扱っている」と判断できない。

exchangeableのlog比は `N(0,2tau²)`、比の中央値は1、平均は `exp(tau²)>1`。逆向きの比も平均は1より大きくなる。これは対称性と矛盾せず、正の変数の比の平均と逆数が交換できないためである。また、積1は幾何平均1を指定し、各γの算術平均を1には固定しない。

K=4のステップはn=3の同じ式に従う。raw SD1では分散(1,1,2)、exchangeable/sourceのkernel SD1では全て2/3である。ステップの対称な事前は、得点カテゴリーの並べ替えが同じ応答モデルになるという意味ではない。K=2なら唯一の非基準ステップは0で、自由ステップも、その密度への寄与もない。

## 5. 何を揃える比較か

| 揃える対象 | exchangeableのτ | 保持されないもの |
| --- | --- | --- |
| 目標とする全座標共通の周辺SD s | `s sqrt(n/(n−1))`（n>1） | rawの最後の座標の大きな分散 |
| rawの自由座標同士の対比分散 | `sigma`（その対比が存在するn>2） | rawの最後の座標を含む対比分散 |
| rawの平均周辺分散、かつ全対比の平均分散 | `sqrt(2) sigma`（n>1） | n>2では個々の分散・共分散・裾の形 |
| 指定した一つの対比の事前分布 | その対比と目的から決める | 別の対比も同時に一致するとは限らない |

最後から二番目の式は、全座標・全組の対比をそれぞれ等重みで扱い、rawの平均周辺分散が `2(n−1)sigma²/n`、全対比の平均分散が `4sigma²` であることから得られる。n=2なら `tau=sqrt(2)sigma` でrawとexchangeableは分布全体が一致する。n>2ではrawの非対称な共分散を単一のτで再現できない。sourceではさらに平均の差が残る。log一貫性の平均分散を揃えても、指数変換後のγの平均や裾まで一致するわけではない。

従って「rawからexchangeableへ同じ数値のSDで変更し、結果が変わった」という比較だけでは、対称性と分散縮小の寄与を分けられない。次の比較では、保持する量を先に宣言する。全対比を対等に重視するなら `sqrt(2)sigma` は平均分散を合わせる参照になるが、それ自体が科学的に適切な事前尺度だという結論ではない。

### 利用上の対比から尺度へ戻す

exchangeableで、一つの厳しさ差を事前確率95%で±δ_s内に置きたいなら、標準正規の0.975分位をzとし、

```math
\tau_s=\delta_s/(\sqrt2 z).
```

一つの一貫性比を事前確率95%で `[1/C,C]` 内に置きたいなら、

```math
\tau_\gamma=\log C/(\sqrt2 z),\qquad C>1.
```

例えばδ_s=0.5ならτ_s≈0.180388、C=2ならτ_γ≈0.250070。これは計算例であり、推奨値・受入基準には採用していない。95%は個々の対比に対する確率であり、全対比が同時に収まる確率ではない。厳しさは1.7とγを掛ける前の予測子単位であり、異なるγを持つ評定者の得点差を厳しさ差だけから決められない。許容幅には利用場面の根拠が必要である。

## 6. 能力の単位と「事前感度」の区別

原点を変えず能力単位をt倍にするだけなら、同じモデルを表すにはθをt倍、負荷量を1/t倍にし、事前分布全体もその変換で移す必要がある。独立 `theta~N(0,sigma_theta²)`、`log a~N(0,sigma_a²)` なら、変換先では能力SDが `t sigma_theta`、log負荷量の平均が `−log t` になる。

現在の `GeneralizedPrior` はSDのみを指定し、log負荷量平均は0に固定している。したがって、`person_sd`だけを変更する操作は、一般に単なる単位換算ではなく、応答確率に対する事前も変える感度設定である。さらに原点の変更ではbと負荷量の依存も誘導され、同じ独立正規の指定へ戻せるとは限らない。

人物・項目・負荷量の分布を揃え、評定者とステップのブロックだけを比較することはできる。ただし不変な対比でも、事前を変更した後の事後分布が不変になるとは限らない。事前予測の妥当性と事後推論の感度は別々の問いとして扱う。

## 7. 今回の判断と実装への反映

1. **rawは既存の計算参照として保持する。** 完了4・失敗1・未着手269のcohort、凍結したruntime、主評価量、保存された事前と結果を変更しない。
2. **評定者IDに科学的意味がない用途の次候補はexchangeableとする。** 対称な構造の選択には数学的な根拠がある。一方、具体的なSDや科学的受入は、用途に沿う対比の幅と事前予測から別途決める。公開APIの既定値を切り替えたわけではない。
3. **sourceは参照対象を明示した比較に置く。** qを事前に区別する構成を保持し、その選択を原典比較の目的と混同なく記録する。「sourceだから一般用途にも適切」とはしない。
4. **変更時は新しいターゲットとして扱う。** 将来の公開API・保存・診断・事前予測で、分布、尺度規約、q、モデル識別子を一貫して伝える必要がある。現在の `ExchangeablePrior` をMGMFRMへ流用する実装は加えていない。

式から得られる対称性・平均・共分散の判断を、長時間の推定で代替しない。次に確認する実質的な問いは、対比の幅がどのような応答確率・カテゴリー使用を許すかである。事前予測を調べる際にも、少数の観測データに見た目を合わせて自動採用せず、成立条件と利用上の根拠を残す。

**続報:** [事前尺度から評定確率へ](mgmfrm-prior-responses.md)で、この問いを6条件の共同事前予測と固定条件の計算に接続した。同じ数値と平均分散一致の比較、rawステップ事前の得点反転非対称性、ステップ縮小による両端確率と集中度の異なる変化を確認した。具体的SDの採用や事後推定は行っていない。

## 8. 検査と境界事例の修正

[既存の事前測度検査](../../test/mgmfrm_prior_measure.jl)へ、実際のJulia密度から平均・共分散を復元して独立の多変量正規式に照合する検査を追加した。R=2,3,5、K=2,4、raw／exchangeable／sourceの指定評定者が最初・最後の場合を扱う。平均分散を合わせても個々の対比は一致しないことも確認する。事前がGaussianであることを使った決定的計算であり、MCMC標本からの推定ではない。

K=2の内部normalized密度では、`first(steps):nsteps:last(steps)` のnstepsが0となり、`ArgumentError: step cannot be zero` を再現した。数学上このブロックは0次元で寄与0なので、自由ステップがある場合だけ補正を加えるよう[実装](../../src/mgmfrm_normalized_prior.jl)を修正した。K=2で未使用のstep SDを変更しても密度と勾配が変わらない回帰検査を追加した。

**この修正は内部Julia密度の境界事例を扱う。** 既存の[CmdStanモデル](../../src/stan/mgmfrm.stan)はK≥3・free_steps≥1を要求する。この実行境界を拡張したり、binaryの両backend一致や推定の成功を主張したりはしない。初回cohortはK=4で、凍結済みのコピーは変更していない。

Julia 1.12.5で、既存の解析・正規化検査690件と新規261件、計951件が通過した。コマンドは `BAYESIANMGMFRM_CMDSTAN_TESTS=false julia --startup-file=no --compiled-modules=existing --project=. test/mgmfrm_prior_measure.jl`。追加MCMC、原著の再照合、独立研究者の査読、GitHub上のCIは実施していない。

新検査を含む既存ファイルをfitなしCIジョブへ登録した。利用者向けの事前比較と数式ページを相互参照で接続し、Documenterの文書検査・HTML生成と、生成HTMLの双方向リンク先の照合も通過した。本書のローカル参照5件・コードフェンスと `git diff --check` を点検した。前回同様、変更範囲外の4 APIのdocstringがmanualに未掲載という警告は残る。HTMLは一時フォルダへ生成し、公開サイトは更新していない。

## 9. 明示事前を予測・保存後の説明へ接続する

### 問題と今回の到達点

normalized MGMFRMには密度・内部サンプラー・保存形式が既にある一方、通常のgeneralized事前予測は独立raw事前を前提としていた。単に同じ数値の尺度を渡したり、出力にexchangeableという名前を付けたりすると、実際の生成分布と報告が食い違う。

この問題に対し、既存の `_MGMFRMNormalizedPriorLogDensity` とその正規化済み事前記録を正本として使う。今回追加したのは、**このターゲットからの直接的な事前標本生成、既存予測要約への接続、予測と保存済み標本で共通の事前説明**である。MGMFRM用の新しい公開prior型や並行する保存形式は作っていない。

| 経路 | 今回の動作 |
| --- | --- |
| 明示指定 | 既存の `prior_model=:exchangeable` / `:source`、6尺度、sourceの場合の評定者IDを使う。省略時の科学的候補は選ばない |
| 事前密度 | 既存の正規化済み密度を保持する |
| 事前予測 | 新しい内部 `_mgmfrm_normalized_prior_predictive_check(target; ...)` が、その分布から生成し、既存の応答カーネル・予測要約へ渡す |
| 分布の説明 | `prior_metadata` にkernel SD・周辺SD・対比SD・平均・source評定者・モデルの適用範囲を付ける |
| 保存済み標本の復元 | 既存v1/v2レコードから同じ `prior_metadata` を再構成する。保存レコード、ターゲット識別子の定義、内容ハッシュの定義は変更しない |
| 表と図 | `predictive_check_summary(check)` と既存の事前予測図データを再利用し、図の説明にもnormalizedの種類・source評定者・尺度規約を保持する |

`parameter_space=:raw_unconstrained_coordinates` は座標の表現であって、「独立raw事前」を意味しない。normalizedの予測結果では `check.prior` に実際の正規化済み記録を入れ、独立raw正規やそのヤコビアン方針を誤って報告しない。

### 生成分布を密度に合わせる

各ゼロ和ブロックの長さをnとすると、保存する自由座標はn−1個で、共分散は `tau²(I−11ᵀ/n)`。そのCholesky因子で標準正規乱数を変換する。厳しさ・log一貫性・各項目のステップに適用し、sourceのlog一貫性には第3節の平均 `tau²(1/R−e_q)` を加える。重み付けによる近似やMCMCは必要ない。

人物・項目位置・log負荷量は既存の独立正規生成を使う。同じseed・尺度なら、それらの標本と乱数消費はraw経路と一致する。normalizedの制約ブロックは別分布なので、同じ標本値になることを要求しない。

1評定者なら厳しさとlog一貫性は固定0、2カテゴリーなら唯一の非基準ステップは固定0である。説明では周辺SDを0、対比が存在しない場合の対比SDを `missing`、尺度が分布に影響しないブロックを `scale_active=false` とする。存在しない自由度に正の不確実性を報告しない。Juliaでのこの取扱いは、既存のCmdStan K≥3という境界を拡張しない。

### 一つの記録から説明を再構成する

`prior_metadata.prior` は既存の正本と同じ記録であり、その6尺度から各ブロックの説明を導く。sourceの平均は評定者ID順のベクトルとして出力する。モデル情報には、推定する正の負荷量、固定Q、固定された潜在相関、応答式の1.7、次元名を含める。固定係数MFRM用の `ExchangeablePrior` と混同しないためである。

説明用の `prior_metadata` は保存レコードに重複して書き込まない。古いv1/v2の標本を復元する際にも、そのレコードからターゲットを検証・再構成した後で導出する。尺度やモデル名を説明側だけ書き換えて別の科学的ターゲットに見せることを避ける。既存の識別子不一致・無断上書き・不正レコードの拒否も維持する。

内部レビューで、既に構築したnormalized `target` には次のように接続できる。

```julia
using Random
const B = BayesianMGMFRM

check = B._mgmfrm_normalized_prior_predictive_check(
    target; ndraws=1000, rng=MersenneTwister(24))
check.prior                              # 実際の分布・尺度の正本
check.prior_metadata.blocks.severity     # kernel・周辺・対比SD
check.prior_metadata.blocks.log_consistency.mean
predictive_check_summary(check)          # 既存の予測要約

# 既存の内部normalized標本ファイルを読み込む場合
loaded = B._load_mgmfrm_normalized_prior_samples(
    path; expected_identity=B._mgmfrm_normalized_prior_identity(target))
loaded.prior_metadata
```

この例の反復数は操作例であり、科学的な評価に必要な精度を保証する設定ではない。観測得点は予測との比較にだけ使い、事前を更新しない。対象は指定済みの人物・項目・評定者・評定行で、新しい評定者母集団や未知の項目への一般化ではない。

### 検証方法と残る境界

[新しい検査](../../test/mgmfrm_normalized_prior_predictive.jl)は、生成処理へゼロと基底ベクトルの正規乱数入力を与え、その平均と線形写像を復元する。それを実装密度の勾配・Hessianから得る平均・共分散に照合する。有限Monte Carlo標本のモーメントが近いことだけに依存しない。

1・2・3・5評定者、2・3・4カテゴリー、2次元純粋Qと3次元混合Q、source評定者が最初・最後の場合を扱う。生成値から独立に応答式を計算し、全セルのカテゴリー確率を照合する。得点だけを変えても生成パラメータ・擬似評定が変わらないこと、局所乱数の再現性、不正指定を乱数消費前に拒否することも点検する。

保存の検査は、サンプラーを起動せずに作る明示的な検査用レコードで、v1/v2を読み込み、同じ事前説明が戻ることと既存の保存バイト列が保たれることを確認する。検査用の数値列は事後標本やNUTSの性能証拠ではない。

Julia 1.12.5で、新規検査2,238件（生成分布432、予測・適用境界1,770、保存36）が通過した。既存のraw事前検査351件、事前測度検査967件も通過した。検査の実装中に、`missing` を含む説明の比較と、保存前後の `FacetSpec` のオブジェクト同一性を内容の一致と扱っていた比較を修正した。最終検査では `isequal` と保存バイト列を適切に使い分けている。数値生成・保存データの破損を検出したものではない。

今回更新したマニュアルもDocumenterの文書検査・相互参照・HTML生成を通過した。変更範囲外のdocstring未掲載警告4件は継続している。新規検査を既存のfitなしCIジョブとgeneralizedテスト群に登録したが、GitHubでのCI実行や公開サイトの更新は行っていない。

```sh
julia --startup-file=no --compiled-modules=existing --project=. test/mgmfrm_normalized_prior_predictive.jl
julia --startup-file=no --compiled-modules=existing --project=. test/generalized_prior.jl
BAYESIANMGMFRM_CMDSTAN_TESTS=false julia --startup-file=no --compiled-modules=existing --project=. test/mgmfrm_prior_measure.jl
```

公開 `Experimental.fit` / `prior_predictive_check` へnormalizedターゲットを `prior=` として渡す経路は、引き続き受け付けない。公開の `ExchangeablePrior` も固定係数MFRM用のままである。既存の内部推定・保存と事前予測の説明を揃えた段階であり、公開fit/report bundleへの統合、相関MGMFRMへの拡張、新規backend推定の検証や科学的受入までは行っていない。具体的SDの採用、raw cohortと凍結runtimeの変更、新規事後fitも0である。

## 10. 公開された実験的経路への接続（2026-09-26）

`Experimental.NormalizedMGMFRMPrior` と `NormalizedMGMFRMFit` を追加した。
前者は `prior_model=:exchangeable` または `:source`、6尺度、sourceの場合の
評定者IDを明示する。既存のnormalized密度・生成器・サンプラーとv1/v2標本記録を
再利用し、旧 `GeneralizedPrior`、固定係数用 `ExchangeablePrior`、既存の事前・標本
識別子は変更していない。第9節の「公開経路には未接続」は当時の到達点である。

`Experimental.prior_predict` / `prior_predictive_check` / `fit` から、同じ事前を
使える。結果は既存のraw/direct要約、MCSE、診断、既存評定行の事後予測、手動fit
cache、Markdown/JSON/表と任意の図を含むreport bundleへ接続した。各経路は保存した
正本から分布・kernel/周辺/対比SD・sourceのlog一貫性平均・評定者IDを再構成する。
公開cacheは別schemaで型・標本・artifactの一致を検査し、既存の内部標本の保存形式は
維持する。`verify_hash=false` でも標本とartifactの整合性検査を省略しない。

適用範囲は固定Q・推定負荷量・固定された単位潜在相関のMGMFRMである。
相関モデル、raw以外のsampling coordinates、自動request cacheは接続していない。
Julia側のbinary境界は維持し、CmdStanのK≥3制限はコンパイル前に検査する。
混合Qの図表を作れることは、その幾何で識別・回復が検証済みという意味ではない。

[新しい検査](../../test/mgmfrm_normalized_fit.jl)は、明示指定、同じ生成分布、
旧v1/v2標本の公開結果への適用、保存後の説明・要約・予測の一致、改変cacheの拒否を
検査する。標本fixtureは合成された数値列であり、事後推定の証拠には数えない。
`test/postprocessing.jl` と既存generalizedテスト群からも実行する。

```sh
# サンプラーなしの契約・保存・報告検査
julia --startup-file=no --compiled-modules=existing --project=. test/mgmfrm_normalized_fit.jl
# 任意の動作確認：各事前・backendで2 chains、warmup 10、retained 8、max_depth 3
BAYESIANMGMFRM_NORMALIZED_FIT_SMOKE=true BAYESIANMGMFRM_CMDSTAN_TESTS=true \
  julia --startup-file=no --compiled-modules=existing --project=. test/mgmfrm_normalized_fit.jl
```

具体的な科学的SDの採用、既定値変更、元のraw cohort（4/1/269）や凍結runtimeの
変更はない。短いサンプラー動作確認と統計的受入を区別する。

検証はJulia 1.12.6で実施した。既存の生成・予測・旧保存形式の検査2,238件、
新APIの指定境界35件と追加binary CmdStan境界2件、保存・要約・報告1,004件が通過した。
共有する相関MGMFRMのreport/予測とExperimental namespaceの回帰検査は1,870件通過した。
最初の新規テスト実行では、`missing` を含む説明を `==` で比較したこと、公開診断の
`stability` を `status` と読んだこと、公開投影で除かれる内部schemaまで同一と要求した
ことを修正した。これらはテストの期待値の問題であり、データや尺度を変更していない。

Julia/AdvancedHMCとCmdStan 2.39.0の各backendでexchangeable/sourceを1回ずつ、
上記の短い2-chain設定で実行し、各backendで14件の推定・保存・報告検査が通過した。
4 fitはいずれも `sampler_warning` を持つ動作確認であり、収束済み事後比較や科学的
受入には数えない。CmdStanの最初のコンパイルはsandboxが共有PCHへの書込みを拒否して
MCMC前に停止し、必要なビルド権限で再実行した。元cohortへの追加・置換はない。

CairoMakieを一時環境に追加し、合成された3次元mixed-Q/source標本から5種類の図、
PDF/SVG/JSON、report bundleの復元を40件の検査で確認した。事後区間・chain診断・
事後予測のPNGも目視し、source評定者、kernel尺度、診断不足の注記を確認した。
Documenterの検査・HTML生成と、新2 APIおよび使用例のHTMLアンカーの存在確認も通過した。
既存4 APIのdocstring未掲載警告は継続する。Gitメタデータの読み込みが停止したため、
今回のローカルHTMLではrepository/editリンクを無効化し、公開用make設定は変更していない。
依存追加と描画物は一時環境に置いた。公開サイト、GitHub CI、最小Julia版は今回未実行である。

## 11. 2次元・固定Qに絞った尺度と受入条件（2026-09-26）

[基盤検証の計算票](mgmfrm-foundation-scale-acceptance.md)では、既存Cの6尺度を
比較候補として公開APIへ対応づけ、周辺・1対・全対の事前幅と、150量の条件付き
受入設計を数値化した。科学的尺度や許容幅の採用、元raw cohortの置換は行わない。
