# 共通予測契約と「受験者 × 課題 × 評定者 × 評価観点」の設計

**Implementation status updated 2026-10-13:** see [§8.1](#81-current-integrated-candidate-and-evidence-reuse-2026-10-12) for the current candidate and evidence boundaries; earlier implementation tables retain their dated scope.

2026-10-09。利用者の提案を受けたコード点検・数学的設計。**共通の分析経路を先に整え、4ファセット化は明示した新モデルとして段階的に実装する。** この文書は新APIの実装完了や、相関・4ファセットモデルの統計的受入を意味しない。進行中の2次元・固定Q pilot、その事前分布・推定・採点・比較規則は変更しない。

現在の完了判定は[ROADMAPのMS1〜MS6](../../ROADMAP.md#completion-milestones)による。ここにある共通抽出・分析経路の試作はMS5の材料であり、対応型ごとの数値一致だけでは公開API統合の完了にならない。採用するモデル・操作をMS4の支持範囲へ結び付け、共通の利用経路と保存復元を検証する。4ファセット化は別のモデル範囲として扱い、現行pilot・本評価・API確定の前提へ自動追加しない。

局所依存・評定者尺度の階層化・未知水準の予測への次の拡張は、[共有効果と母集団予測の実装仕様](shared-effects-hierarchy-prediction.md)にまとめた。識別の反例、正規化と座標、分割／積分／採点、既存残差診断との接続、段階ごとの完了条件を記録する。

## 1. 現状の接続範囲

| 対象 | 既存の共通経路／再利用できる部分 | 残る接続 |
| --- | --- | --- |
| `MFRMFit`、`GMFRMFit`、`MGMFRMFit` | カテゴリ確率、観測別対数尤度、WAIC/LOO、較正、`compare_models` | 観測ID・予測条件・尺度を一体で受け渡す契約。カテゴリ機能レポートはGMFRM/MGMFRMにも未接続 |
| `Experimental.CorrelatedMGMFRMFit` | 検証済み保存レコードから、既存評定行の同時事後標本に条件づけた確率・事後予測・レポート | 上記のモデル比較経路とWAIC/LOO/較正/カテゴリ機能 |
| `Experimental.NormalizedMGMFRMFit` | 正規化事前の保存レコードと予測経路。現在のpilotはこの側を使用 | 相関モデルと同じレポート層の未接続箇所。従来の `MGMFRMFit` と同じ型ではない |
| 固定係数の多次元MFRM結果群 | 独立／相関などの専用保存・診断・予測レポート | こちらも比較・較正等を個別に接続する必要がある。固定識別力を比較する場合の対象に含める |

確認箇所は [bayesian_fit.jl](../../src/bayesian_fit.jl) の `_ModelComparisonFit`、`_model_comparison_contract`、`_require_model_comparison_compatibility`、`_require_kfold_comparison_compatibility`、`pointwise_loglikelihood_matrix`、`_fit_report_category_functioning`、および [correlated predictive](../../src/mgmfrm_correlated_2d_predictive.jl)、[correlated/normalized reports](../../src/mgmfrm_correlated_2d_reports.jl)、[fixed-coefficient results](../../src/mfrm_fixed_q_samples.jl)。

現在の `compare_models` は**同じデータ・行順・カテゴリ・次元数・Q**を要求する。次元数/Qの変更は既存の明示的な感度比較に分けてある。`compare_kfold` は集計結果を受け取り、観測インデックス・fold・予測対象の一致を検査するが、その値だけで別々の元データが同じ観測だとは保証できない。新経路では元データ／学習集合への結び付けを残す。既存チェックを単に緩める変更にはしない。

## 2. 保存形式を越えて取り出す情報

まず **既存水準に条件づけた観測行の予測**を共通化する。名称は仮称であり、汎用レジストリや別の保存システムを先に作らず、既存結果型ごとの小さなアダプタで以下を満たす。

| 情報 | 必須の意味／検査 |
| --- | --- |
| 観測 | 元データの名前空間と一意な `outcome_id`、人物・物理課題・評定者・観点、カテゴリと得点方向、観測値、包含規則。元の行位置も残すが、比較のIDに行番号だけを使わない。IDで整列し、欠落・重複・異なる観測値を拒否 |
| 応答イベントと採点単位 | `response_id`／録音等の共有イベントと、一回の評定結果のIDを区別する。必要に応じてイベント×評定者×観点×反復で一意性を宣言。既存の `response_id` の意味を黙って変更しない |
| 標本 | chain・iteration・選択元インデックス、選択順と重複、ウォームアップ除外、保存座標、診断状態。同じ選択を確率と尤度の両方に適用し、別々の乱数抽出で対応を崩さない |
| 確率 | `draw × observation × category`、明示したカテゴリ順。観測ごとに和1。内部では安定なlog-softmaxも保持し、極小確率が0に丸められた後に `log(probability)` で尤度を作らない |
| 観測別対数尤度 | `log p(y_n | draw_s, declared_conditioning)`。事前や変数変換Jacobianを含まない。列の和が既存の総対数尤度と合い、観測カテゴリのlog確率と一致。相関モデルの人物能力は既に同時事後標本であり、予測時にρをもう一度作用させない |
| 学習と評価 | 学習データの内容ハッシュ、学習/評価ID、fold割当、除外規則、学習内で決めた変換。評価の観測値だけを変更しても学習ターゲットが変わらないこと。保存済み学習行だけを評価行へ付け替える操作は禁止 |
| 予測対象 | 既存／新規の人物・課題・評定者・イベント、条件づけに使える情報、周辺化する効果、その積分方法。未実装の新規水準は明示的に拒否。`posterior_predictive` という名称だけで同じ予測対象としない |
| 集計単位 | 観測の重み、人物等の集計単位、共有イベントの保持、独立反復block。得点を平均する単位と、不確実性を計算する単位を分ける。pilotの5foldを5独立反復として扱わない |
| モデル／実装 | 尤度式の識別子、固定倍率λ、固定/推定負荷量・一貫性、D・Q・次元ラベル、閾値構造、位置/尺度制約、事前分布と基準水準、共分散の階層。backend/source/cacheの識別子は数学的ターゲットの識別子と別に保存 |

すべてのモデルで同じパラメータ配列を強制する必要はない。比較の対象はまず同じ観測カテゴリーの予測分布である。DやQが違っても、同じ学習情報から同じ観測を予測する明示的比較は設計できる。一方、パラメータ値の直接比較や「この一要因だけを変えた」という解釈には別の尺度・事前の対応が必要になる。特にunit-logit MFRMとλ=1.7のMGMFRMは、負荷量を1にするだけで同じモデル／事前にならない。

**接続する順序：**

1. 検証済み標本・観測・予測条件のアダプタと数値的な一致検査。まず従来3型、相関MGMFRM、正規化MGMFRM。その後、固定係数の多次元MFRM結果群を同じ検査に通す。
2. 学習行の観測別尤度からWAIC/LOOと診断を接続。通常の重要度サンプリング、既存のHill平滑化、参照PSISを区別する（§7）。同時に既存行の較正を接続し、学習内の記述であることを表示。相関推定や事後予測が成功しただけでLOOが安定だとはしない。
3. 共通foldへの再推定・評価行の採点を接続。既存水準の評定留保と、新規人物・新規イベントの留保を別タスクにする。後者は適切な効果の積分とまとまり単位の分割が実装されるまで提供しない。
4. カテゴリ機能は、カテゴリ利用状況・予測確率と、モデル固有のステップ/閾値の解釈を分けて実装する。確率アダプタができても閾値順序等の診断が自動的に同じ意味になるわけではない。

共有イベントの条件付き独立な行をまとめて評価する場合、各drawの行対数尤度を**先に合計してから**予測密度を計算する。行ごとに事後平均した密度の積とは一般に異なる。新規イベントの共有効果は積の中で共同に積分する。単に行別LOOを足して「イベント留保」と呼ばない。PSISの問題は診断・明示的再推定で扱い、都合の悪い行を比較から落とさない。

### 数値効率と完了条件

保存レコードの検証・raw→direct変換・カテゴリ線形予測子を要求単位で再利用する。確率、尤度、較正の呼び出しごとに巨大な標本を復元し直さない。必要なdraw/観測の分割処理を可能にし、確率が不要なら `S×N×K` を作らない。例えば4,000 draw ×1,250観測×4カテゴリのFloat64だけで160 MBを使う。最適化は固定した入力で出力一致、ピークメモリ、経過/CPU時間を測って判断する。

アダプタの完了条件は、(a) 各対応型の保存/再読込後の一致、(b) 同じdraw選択でネイティブ確率・総/観測別尤度との一致、(c) 観測の置換・ID整列・カテゴリ順と極端なlogitの検査、(d) 異なるデータ/条件/重み/foldの拒否、(e) 宣言した比較軸だけが異なるケースの受理、(f) heldout値からの学習漏洩がないこと、(g) 診断不適格結果の保持と表示、である。各分析の完了はこの後に別々に記録する。合成標本は接続検査、既存の実標本は再読込/数値再現検査に使い、いずれも新たな統計的反復には数えない。

## 3. 4ファセットは明示した測定モデルとして追加する

現在の [FacetData](../../src/facet_workflow.jl) は `person/rater/item` が主要な役割で、`task/occasion/testlet_id` 等はメタデータである。**`task=` を追加しても課題難易度の推定項は増えない。** 物理課題と評価観点を別々のIDで保持し、モデルがどちらにどの効果を置くかを明示する。`item=task×criterion` の既存表現は、対応表を保存して互換性を保つ。既存の `item` の意味や尤度を自動で置換しない。

最初の数学的候補は、固定識別力・固定一貫性の隣接カテゴリモデルとする。受験者p、課題t、評定者r、観点c、カテゴリk=0,…,K−1について、

```math
\log\frac{P(Y_{ptrc}=k)}{P(Y_{ptrc}=k-1)}
=\lambda\{\theta_{p,d(c)}-b_t-v_c-s_r-\tau_{ck}\},\qquad k\ge1.
```

λは宣言した固定値、`d(c)` は既知の純粋Qで定める。最小の一次元版では全観点で同じθを使う。**4つのファセットと4つの潜在次元は別の概念**であり、観点数＝次元数とも限らない。初期候補ではカテゴリ尺度は共通、ステップを観点内で共有し、観点ごとに `sum_k τ_ck=0` とする。課題難易度bが観点間で共通、評定者厳しさsも共通という制約自体が検証対象になる。この式は設計候補であり、既存MGMFRMへの黙示的な差し替えではない。

### 位置の制約と反例

一次元の完全交差では、課題・評定者・観点の各ゼロ和、ステップの観点内ゼロ和を置き、θを自由にすると条件付き位置設計を識別できる。有限・正のカテゴリー確率から隣接対数オッズを復元し、同一人物の課題差・評定者差・観点差を取れば各ゼロ和効果が決まり、残りからθが決まる。

しかし、多次元で観点全体に一つのゼロ和だけを置くと不足する。各次元で `θ_pd → θ_pd+u_d`、`v_c → v_c+u_d(c)` として、`sum_c u_d(c)=0` を満たせば全確率と観点全体のゼロ和が保存される。全D次元に観点がある場合、D−1方向が残る。

比較する位置基準の候補は次の二つである。

- **次元内の観点ゼロ和：** 各dで `sum_{c:d(c)=d} v_c=0`、θは自由。各次元の能力原点がその観点集合を基準とする。
- **有限パネル内の能力ゼロ和：** 各dで `sum_p θ_pd=0`、vは自由。その受験者パネルを基準とした観点難易度を得る。

いずれも課題・評定者・ステップのゼロ和を併用する。完全交差・既知純粋Q・固定負荷量のこの候補では、差を取る議論を次元内に適用できる。各次元に観点があり全人物を観測するという条件下で、残る位置不定性を除ける。これは分散・相関・自由負荷量を含む一般モデルの識別定理ではない。

二つの位置基準は同じ条件付き確率を表せるが、同じ独立正規事前をそれぞれに置けば一般に同じ事後分布にはならない。前者から後者へは `θ'_pd=θ_pd−mean_p θ_pd`、`v'_c=v_c−mean_p θ_p,d(c)`。同一ターゲットとして比べるなら事前の押し出しと座標の測度も合わせる。現在のpilotの母集団平均0の正規事前は、有限パネルの厳密な平均0制約ではない。新規人物の予測・母集団解釈を含め、どの基準/階層事前を採るかは実装前に明示する。

### 課題項の二重投入・疎な割当て

自由な複合項目難易度β_tcにさらにb_tを足すと、`b_t→b_t+h_t`、`β_tc→β_tc−h_t` で尤度が変わらない。hのゼロ和を要求しても非零の方向が残る。最初は `β_tc=b_t+v_c` とする加法的な制限を検証する。課題×観点の交互作用δ_tcを追加する場合は、完全格子での行/列ゼロ和や明示的階層を定義し、疎な格子ではその制約下の階数を再検査する。properな事前だけでridgeを正則化して「尤度が分離した」とは報告しない。

人物が課題に入れ子、評定者が課題に専属、課題と観点が一対一の場合にも分離不能が生じ得る。全データの連結性だけでなく、**実際の学習foldの制約付き設計**を検査する。観測しなかった水準の列を黙って落としてfull rankに見せない。ステップを無制約にすると観点位置との交絡が生じる。K=2では中心化した唯一の隣接ステップは0で、自由パラメータを追加しない。

## 4. この段階で実行した検証

[識別検査スクリプト](../../scripts/four_facet_identification_audit.py)は整数の隣接logit設計を作り、有理数の消去法で階数を計算する。サンプラーやJuliaの起動を必要としない。13ケースの期待階数を検査し、[5つのテスト](../../test/four_facet_identification_audit.py)で反例の零方向、行置換・水準再ラベル、加法/複合表現の確率一致、二つの位置基準の確率一致を確認した。

| 代表ケース | 列数 / 階数 | 読み取り |
| --- | --- | --- |
| 3人物×3課題×2評定者×2観点、一次元 | 7 / 7 | 指定した位置制約下の完全交差設計 |
| 2次元・4観点、観点全体のゼロ和のみ、中心化ステップあり | 16 / 15 | 次元間の位置方向が一つ残る |
| 同じデータで次元内観点ゼロ和、または人物の次元別ゼロ和 | 各15 / 15 | この固定係数設計では二つとも位置を特定 |
| 人物が課題に入れ子 | 7 / 6 | データ割当てによる交絡 |
| 自由な複合項目難易度＋課題項 | 11 / 9 | 追加した2自由度は重複 |

再実行：

```sh
python3 -B scripts/four_facet_identification_audit.py
python3 -B test/four_facet_identification_audit.py
```

有限の合成設計での厳密な階数検査と確率の数値一致であり、実データの回復・較正・混合や事前の適切性を証明するものではない。新しいfit APIや推定項は追加していない。共通抽出の後続実装は第6節に記録する。

## 5. 優先順位と終了判定

| 段階 | 実施内容 | 終了条件 |
| --- | --- | --- |
| pilot実行中の準備（今回） | コード監査、共通予測契約、4ファセットの式・不定性・反例検査 | 監査対象と未接続箇所、対応型・予測範囲、13ケースの期待階数、次の実装境界を記録。凍結コード不変・追加推定0 |
| pilot終了後の分析統合 | 既存尤度/変換を再利用する最小のアダプタ。まず相関/正規化MGMFRMを含む既存行の整列・尤度・予測 | §2の接続検査が通り、同じ利用者コードで対応型の確率/尤度を得る。WAIC/LOO等は接続した機能ごとに実例と制限を記載 |
| 現行の本評価 | pilot確定→同一ターゲットの効率比較→実装固定→新しい独立反復の本評価 | [foundation §26](mgmfrm-foundation-scale-acceptance.md)と既存N規則を維持。アダプタの基盤だけを必要に応じ再利用し、4ファセット全実装やレポート全項目を前提にしない |
| 最初のモデル拡張 | 明示した4ファセット・固定係数・共通カテゴリの候補。位置基準、事前、学習内デザイン、既存/新規予測対象を定めてからJulia/Stan実装 | 制約/階数・密度/勾配・保存/予測再現が一致。事前に固定した交差/疎な設計で、回復・事前感度・失敗率・予測を精度付きで評価。数値完了と科学的受入は別に記録 |
| 必要性を検証して追加 | 課題×観点、評定者×観点、共有応答効果、自由識別力/一貫性、潜在相関 | 各追加項の目的・識別・事前・予測単位を指定。単独機能の合格だけでその組合せを受入済みにしない |

OS/配布方針は引き続き後段とする。4ファセット設計は[既存の共有契約](../../ROADMAP.md#shared-specification-and-prediction-contract)と応用側の物理課題/観点/応答イベントの区別を具体化するもので、別々のモデル案を重複開発しない。追加の大規模推定や計算資源は今回使用しない。

## 6. 共通抽出の最初の実装（2026-10-09追記）

[prediction_observation_adapter.jl](../../scripts/prediction_observation_adapter.jl) は、packageのinclude/exportを変更せず明示的に読み込む実験用モジュールである。凍結したpilotはこのファイルを読み込まない。最初の実装では従来3型と `Experimental.CorrelatedMGMFRMFit` / `Experimental.NormalizedMGMFRMFit` の合計5型を受け付け、**fit自身が学習した全観測行・既存水準への条件付き予測**を返した。固定係数の多次元MFRMと評価指標への後続の接続は§7に記録する。

リポジトリを作業ディレクトリとし、読み込み済みのfitと、元データ由来の一意な評定結果IDを使う。

```julia
include("scripts/prediction_observation_adapter.jl")
using .PredictionObservationAdapter

rows = prediction_observations(fit;
    dataset_id="study-A/ratings-v1",
    observation_ids=outcome_ids_in_fit_row_order,
    draw_indices=[40, 1, 13, 1])
rows.probabilities              # draw × observation × category
rows.pointwise_loglikelihood    # draw × observation; prior/Jacobianなし
rows.chain_ids, rows.iterations # 選択順と重複を保存
rows.model                     # 尺度、D/Q、制約・事前のネイティブ記録
rows.sampling_quality          # 警告を捨てない
```

`include_probabilities=false` ならカテゴリ確率配列を確保せず尤度のみを得る。両方を要求した場合も同じ線形予測子から計算する。記録型の標本検証・変換は一回の呼出し内で再利用する。ただしネイティブの復元検証自体は全保存drawを検査するので、少数drawの選択が復元コストまで省くわけではない。

固定倍率は `model_family_contract` の実装値から取り出す。現在のscalar GMFRMは原式に従い1.0、多次元MGMFRMは1.7であり、一般化モデルというだけで同じ倍率と扱わない。モデル固有のステップ所有者・位置制約・事前の記録も保持する。

`sampling_quality` は元の保存標本全体に対する診断であり、選択した少数drawの精度保証ではない。順序の変更や重複選択を許す抽出機能と、完全なchain情報を必要とするMCSE/PSIS等の分析条件は区別する。後続の分析機能でその条件を検査する。

`observation_alignment(reference, candidate)` は、候補の列を基準の観測順へ並べるインデックスを返す。データの名前空間・カテゴリ・ID付き観測内容・学習集合・予測条件を照合する。D/Qの異なるモデルも観測を整列できるが、これは比較軸の選択、パラメータ尺度の同一性、モデル順位付けの承認を意味しない。カテゴリの再符号化やファセットIDの別名対応は自動推定せず拒否する。

観測IDは呼出し側が元データの行へ正しく対応させる責任を持つ。共有 `response_id` を一意な評定結果IDへ自動昇格させない。記録型は検証済みsample hashを返す。従来型に同じ保存hashが存在するかのように装わず、`source_hash_status=:not_available_for_legacy_fit` と明記する。出力のbindingは観測の対応を検査するもので、mutableな数値配列全体の改ざん検知用アーカイブではない。

別データ、新規水準、任意のfoldや重みは受け付けない。WAIC/LOO・較正・カテゴリ機能のレポート接続、heldout再推定、packageの公開API化は後続段階に残す。現在の `compare_models` の制限は変更しない。

### 検証結果

[限定テスト](../../test/prediction_observation_adapter.jl)は最終版で560項目を通過した。合成標本では5型、2/4カテゴリ、1/3評定者、正規化事前のsource/exchangeable、AdvancedHMC/CmdStanの保存形式を検査した。保存形式の合成検査はbackendの追加推定や新たな一致証拠ではない。確率・尤度・draw選択・元fit不変・キャッシュ再読込を照合し、変更された記録型標本、重複ID、違う観測値・カテゴリ・学習集合・条件づけを拒否した。

加えて、完了済み `B001-R0-025-F1` の保存事後標本を読み、1,000学習観測と4つの選択drawでネイティブ出力に一致すること、chain/iterationの対応、元ファイルのSHA256不変を確認した。元標本全体の復元検査も通過した。新しい推定・独立反復・pilotの再試行には数えない。

最終実行は286.34秒、観測した最大RSSは2,007,859,200 bytes。Juliaの初回コンパイル、合成結果のキャッシュ往復、実標本の復元を含むテスト所要時間であり、推定本体の高速化率ではない。経過時間の上限は設けず、単一スレッド・低優先度で実施した。全体テストは再実行していない。凍結コード479ファイルと保全成果物1,004件のハッシュ一致を別途確認した。

```sh
# 合成結果の限定検査（追加推定なし）
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 \
  julia --project=. --startup-file=no test/prediction_observation_adapter.jl

# 同じ検査に、既存の保存結果1件の読み取り専用再生を追加
MGMFRM_ADAPTER_REPLAY=results/workflows/20261006-foundation-prediction-pilot-01/attempts/B001-R0-025-F1/samples.jls \
  JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 \
  julia --project=. --startup-file=no test/prediction_observation_adapter.jl
```

実行記録は `results/workflows/20261009-prediction-adapter-01/test-02/`、検証の対応関係は同親ディレクトリの `verification.json` に保存。凍結中の `test/runtests.jl` へはまだ登録していない。

## 7. 固定係数MFRMと評価指標への接続（2026-10-09追記）

同じモジュールに `MultidimensionalMFRMFit`、`Experimental.CorrelatedMFRMFit`、`Experimental.ExchangeableMFRMFit` を加え、抽出対象は合計8型になった。交換可能な評定者事前では独立／相関の両方を扱う。旧fixed-Q v1記録も検証して読み込む。旧記録の内部仕様が `family=:mgmfrm` でも、意味上のモデルは固定係数MFRM、報告する倍率は1.0とする。保存したunit-logit座標を内部のMGMFRM計算へ変換し、条件付き予測へ相関を二重に掛けない。尺度・制約・事前・保存形式・位置診断を保持する。

`prediction_criteria` は、全保存drawを使った共通対数尤度行列を一度作り、指定したネイティブ評価指標へ渡す。fitを直接渡す場合、カテゴリ確率配列は作らない。既に得た全drawの抽出結果も渡せる。元の順序、全chain、等しいchain長、chain内iterationの連続性を検査し、少数drawの選択・重複抽出・順序変更を拒否する。以前の抽出結果に全draw数の記録がなければ、現在のアダプタで抽出し直す。

```julia
evaluation = prediction_criteria(fit;
    dataset_id="study-A/ratings-v1",
    observation_ids=outcome_ids_in_fit_row_order,
    criteria=(:waic, :raw_loo, :hill_smoothed_loo))
evaluation.scores                   # ネイティブ指標と観測別の値
evaluation.problem_observation_ids  # 高分散／高Pareto-kの観測ID
evaluation.sampling_warning         # 元の標本・位置診断の警告
evaluation.criterion_warnings       # 指標ごとの警告
evaluation.uncertainty               # SE/ESSの定義と未計算事項
```

| 指定名 | 計算 | 解釈の境界 |
| --- | --- | --- |
| `:waic` | 既存 `waic` | 観測別対数尤度の標本分散を使う。0.4を超える行のIDを保持 |
| `:raw_loo` | 既存 `loo` | 通常の重要度サンプリング。Hill推定のPareto-kと重みのESSを返す |
| `:hill_smoothed_loo` | 既存 `psis_loo` | このリポジトリのHill推定による裾平滑化。参照PSISとの一致は未検証 |

既定値は `(:waic, :raw_loo)` とする。アダプタでは曖昧な `:loo` / `:psis_loo` 指定を受け付けず、元の推定診断と高Pareto-kの行を落とさない。計算できたことを数値的／科学的受入と同一視しない。

評価単位は単一評定行で、LOOは仕様と水準対応を固定してその一行を除く予測を狙う。新規人物・課題・応答イベントへの予測や、pilotの5分割再推定と同じ評価ではない。返すSEは既存の観測別SEで、人物等のクラスタ調整・独立反復SE・MCMC MCSEは含まない。重要度ESSもMCMC自己相関を補正していない。参照 `loo` はPSISと通常のISを区別し、MCMCの相対効率を扱うため、この接続だけで参照実装への一致や精度を主張しない（[公式loo資料](https://mc-stan.org/loo/reference/loo.html)、[PSIS資料](https://mc-stan.org/loo/reference/psis.html)）。

次の分析統合では、参照PSISとの独立した数値照合と自己相関の扱いを定めたうえで、既存行の較正・カテゴリ機能・レポートへ接続する。共通の観測整列は利用できるが、`compare_models` による自動順位付け、任意foldへの再推定、新規水準、公開API化はまだ追加していない。この作業を本評価や同一ターゲットの効率比較の新たな前提にはしない。

### 接続の検証結果

[限定テスト](../../test/prediction_criteria_adapter.jl)は1,087項目を通過した。§6の560項目を再検査し、固定係数モデルの464項目と評価指標・警告・入力条件の63項目を追加した。固定係数では旧／現行独立、相関、交換可能な評定者事前の独立／相関を、AdvancedHMC/CmdStanの合成保存形式と2/4カテゴリで照合した。3次元とmixed Qも追加検査した。

固定係数の確率は、productionの予測関数・1.7倍への変換を使わずunit-logitの式を組み立てた値と一致し、観測別尤度はネイティブ出力に一致した。評価指標はネイティブ出力との一致に加え、一定尤度の解析解と高分散／高Pareto-kの反例を検査した。少数・重複・順序不一致のdraw、chain/iteration不一致、変更した予測対象・重みを拒否する。これらは接続の検証であり、参照PSIS実装の検証ではない。

完了済みpilotの `B001-R0-025-F1` について、1,000学習観測と4つの選択drawの再生を再確認し、元標本ファイルのSHA256は不変だった。この実標本の再生は確率・対数尤度の接続までで、評価指標の新しい実データ分析には数えない。新規推定・独立反復・native buildは0件。全体テストも再実行していない。

実行時間424.46秒、観測最大RSS 1,992,065,024 bytes。コンパイルと復元を含むテストの費用で、推定本体の速度比較ではない。単一スレッド・低優先度・経過時間上限なしで実行した。凍結コード479ファイルと保全成果物1,004件は不変である。実行ログ・guard receiptは `results/workflows/20261009-prediction-criteria-01/test-01/`、対応する証拠は同親ディレクトリの `verification.json` に保存する。

```sh
MGMFRM_ADAPTER_REPLAY=results/workflows/20261006-foundation-prediction-pilot-01/attempts/B001-R0-025-F1/samples.jls \
  JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0 \
  julia --project=. --startup-file=no test/prediction_criteria_adapter.jl
```

## 8. MS5のAPI対応表と統合順序（2026-10-09）

公開関数のexport有無だけでは対応済みと判断しない。以下の最初の表は2026-10-09時点のdispatch・保存/レポート経路と
§6–7の試作を区別した履歴である。現行候補は下の§8.1を参照する。モデルの科学的受入表はMS4で別途確定する。
`Experimental`名の型はその名前空間の結果型を指す。

| 結果型（合計8型） | 推定・診断/MCSE・保存復元 | 既存行の共通確率/観測別尤度 | fitからWAIC/LOO・比較/再推定 | 残る統合 |
| --- | --- | --- | --- | --- |
| `MFRMFit` | 既存package経路 | 既存経路＋試作 | `_ModelComparisonFit`に含まれる | 観測ID/予測契約を明示して互換性を保つ |
| `GMFRMFit`、`MGMFRMFit` | Experimental推定、既存診断/MCSE/保存 | 既存経路＋試作 | 同unionに含まれる。現在の比較はD/Q等も一致を要求 | 科学的支持範囲、警告、比較可能性の契約を分離 |
| `Experimental.NormalizedMGMFRMFit` | `NormalizedMGMFRMPrior`を明示するfit、記録型の診断/MCSE/手動保存 | native予測＋試作 | 共通union外。試作の指標計算まで | 今回のnormalized C評価と直接つながる最優先対象 |
| `Experimental.CorrelatedMGMFRMFit` | 相関specからfit、記録型の診断/MCSE/手動保存 | native予測＋試作 | 共通union外。reportのWAIC/LOOはunsupported | 相関・尺度・条件づけを保持して接続。独立モデルの統計的受入を流用しない |
| `MultidimensionalMFRMFit` | 固定Q係数fit、診断/MCSE/手動保存 | report内予測経路＋試作 | 共通union外。試作の指標計算まで | unit-logit尺度、旧v1記録の互換性 |
| `Experimental.CorrelatedMFRMFit`、`Experimental.ExchangeableMFRMFit` | 相関/交換可能priorのfit、診断/MCSE/手動保存 | report内予測経路＋試作 | 共通union外。試作の指標計算まで | 固定係数、相関の一回だけの適用、固定されたrater kernel SDの意味 |

根拠は[`_ModelComparisonFit`と指標dispatch](../../src/bayesian_fit.jl)、
[`Experimental.fit/cached_fit`](../../src/experimental.jl)、
[`normalized結果`](../../src/mgmfrm_normalized_fit.jl)、
[`記録型MGMFRMの診断/保存`](../../src/mgmfrm_correlated_2d_samples.jl)、
[`同レポートのunsupported項目`](../../src/mgmfrm_correlated_2d_reports.jl)、
[`固定Q MFRMの診断/保存/レポート`](../../src/mfrm_fixed_q_samples.jl)、
[`8型の試作dispatch`](../../scripts/prediction_observation_adapter.jl)である。
全型で同じ自動`cached_fit`が使える、全型に同じ`posterior_predict`メソッドがある、という表ではない。
手動の保存復元と推定要求の自動キャッシュを区別する。

| 操作 | 再利用できる実装 | MS5で閉じる境界／未対応の扱い |
| --- | --- | --- |
| 共通抽出 | §7の8型、観測ID・カテゴリ・chain/iteration・条件づけ・重み・モデル制約 | MS4で選んだ対応型をpackageへ接続し、文書化した入口だけで抽出/再読込できる。private helperや利用者のdraw変形を要求しない |
| 診断・MCSE・警告 | 型別の既存診断とMCSE、試作のsampling warning | 生標本全体の診断と選択drawの予測を混同しない。未収束・位置の問題・指標の問題を保存/復元/図/レポートまで引き継ぐ |
| WAIC / raw IS-LOO | 共通尤度行列から既存関数を呼ぶ試作 | 公開入口・report・unsupported判定を同時更新する。数値計算可能と推奨可能は別。Hill平滑化は参照PSIS検証まで明示した実験扱い |
| モデル比較 | 観測整列の試作、従来3型の比較関数 | 同じ観測・カテゴリ・学習/保留・重み・予測対象の検査を共有。異なるD/Qの解禁は尤度契約と分割の検査後に限定して行う。単にunionへ型を足して制約を外さない |
| 較正・カテゴリ機能・残差 | 既存MFRM向けconsumer、共有効果文書の残差設計 | どの量をどの条件づけで診断するかを指定してconsumer単位で検証。相関/正規化/固定Q reportのunsupportedを、抽出に成功しただけでcomputedに変えない |
| K-fold再推定 | 従来の計画/再推定、foundation専用binding/score | fit型別の再推定factoryとprior/尺度の再現が必要。foundation専用scriptの成功を一般APIの成功とは扱わない |
| 未知水準・母集団予測 | 分割計画と別モデルの仕様案 | 現在の自動再推定は未知person/rater/itemを拒否。積分・共同/周辺得点・分割単位の実装検証まで未対応を維持。既知行の条件付き予測で代用しない |

統合順序は次の三段階とする。全操作を完成させることを本評価の前提にはしない。

1. **対応範囲を宣言する。** 最初の候補は現在の既知水準・既存行契約を核にし、legacy 3型との
   互換性とnormalized結果の一貫した利用経路を必須とする。他の試作型は対応候補として維持し、
   MS4で科学的支持の有無とexperimentalの範囲を記録する。新しいdefault priorは追加しない。
2. **一つのpublic workflowを閉じる。** 小さい合成データから、仕様→推定→診断/MCSE→対応する
   予測/比較・図→保存→再読込を同じ文書化された関数で再現する。package統合時に型別の小さい
   契約テストを通常テストへ登録する。既存の1,087検査は再利用するが、それだけを公開経路の
   検証とはしない。API実装はMS1後、稼働中の比較/本評価のsource snapshotと分離して行う。
3. **consumerを一つずつ接続する。** 各操作について対応表、help、report、数値一致と反例検査を
   同時に更新する。未実装の操作は明示的に拒否/unsupportedを返す。将来機能を黙って省略して
   MS5の対応範囲を縮めず、MS4の支持表とMS6のレビューで候補版の範囲を確定する。

MS5の終了証拠はAPI/互換性仕様、候補commit、上記public exampleの再現記録と型×操作の
合否表である。MS6では実装者以外が再現・解釈を確認する。Chopin/Uchihara/EVAの入力準備は
保存したまま、実データ推定はAPI確定と各応用が必要とする機能の受入後に行う。

### 8.1 Current integrated candidate and evidence reuse (2026-10-12)

**Published source/manual: installable development preview (2026-10-13).**
Use the [distribution/replay receipt](../../results/workflows/20261013-installable-preview-01/verification.json)
for the published snapshot. The approved 867-file source is published on
`development/20261013-guide`, commit `fe523ff8f50c6f0d1b3ba57263731e9c80a3422f`.
Its runtime, tests, examples and dependency declarations remain identical to the
ICC parent. The [English manual](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261013/)
connects installation to the examples and distinguishes full-environment native
cache reuse from portable JSON reports. Main integration and a package release
remain open. Sections 15–16 record publication and replay evidence.

**Latest local source/help reconciliation (2026-10-13).** The
[workflow-contract successor](../../results/workflows/20261013-workflow-contract-review-01/verification.json)
inherits the 870-file mean-profile implementation and the subsequent English
navigation improvements. It corrects documentation and docstrings; fitting,
transforms, priors, samplers, cache validation and dependencies are unchanged.
The route reconciliation below supersedes the older type-level generalizations.
The new user instruction defers **new simulations**: this increment uses source
inspection, existing saved draws and documentation checks only. It does not
generate prior/predictive draws, restart estimation or change the ongoing MS3 plan.

**Implementation parent: complete crossed ICC (2026-10-13).**
Use the [ICC successor](../../results/workflows/20261013-icc-01/verification.json)
for the implementation snapshot. It adds an explicit two-way observed-score point
estimate and common report integration. Section 14 records evidence and limits.
The [alpha predecessor](../../results/workflows/20261013-ordinal-alpha-01/verification.json)
and prior slope, classification, rank and comparison contracts remain preserved.
The implementation remains unmerged/unreleased; its documentation is now public.

**Parent candidate: explicit slope restriction (2026-10-12).**
Use the [slope API successor](../../results/workflows/20261012-slope-api-01/verification.json)
for the parent snapshot. It connects the bounded D1 fixed/free item-slope
specification to raw-coordinate Julia fitting, existing saved-result operations
and common K-fold refit preparation/scoring. The English help and callable
example retain the threshold/prior/scale contract and short-chain warnings.
Section 12 records the scope and evidence. This is an isolated, unmerged,
unreleased and unpublished candidate, not statistical model-choice acceptance.

**Parent candidate: minimum-version compatibility (2026-10-12).**
Use the [compatibility successor](../../results/workflows/20261012-minimum-workflow-01/verification.json)
for the parent snapshot. All runtime, tests, examples and dependency source are
byte-identical to the ranking parent. Only the saved-reporting guide adds the
practical cache/report choice. Existing K-fold MCSE, classification and ranking
tests pass 1,040 assertions on Julia 1.10.8/macOS arm64; fresh-process replay adds
69. Eight retained actual-fit JSON bundles from Julia 1.12.5 pass 48 reading and
integrity assertions. Native caches written under the newer Julia are not readable
under 1.10.8 (serialization version 30 versus 24); actual-fit recomputation under
the minimum version is not claimed. Keep binary caches in their original Julia
and package environment; portable bundles preserve computed results, not a fit
and its draws. The guide build uses the existing Julia 1.12.5 documentation
environment. No full suite, additional fitting, other OS or hosted release is
claimed. The bounded compatibility evidence supplements, rather than replaces,
the unchanged parent runtime/scientific evidence; MS4/MS6 remain open.

**Parent runtime candidate: finite-cohort ranking (2026-10-12).** The
[ranking successor](../../results/workflows/20261012-posterior-ranking-01/verification.json)
implements `posterior_ranking`, which requires an explicit
person cohort, ability dimension and direction, retaining joint-draw dependence.
It adds midrank summaries, empirical discrete pointwise intervals and optional
top-k inclusion bounds over unspecified boundary tie-breaking. Mean MCSE,
constant/short-chain limits and missing interval MCSE remain explicit. Common
reports, bundles and saved-comparison examples accept optional `ranking` requests;
omission preserves previous shapes and all classification outputs.

Small exhaustive counting and counterexamples verify the rank functional; the
eight retained fit types and D1 MGMFRM route exercise actual saved results,
persistence and fresh-process replay. Likelihood/prior/sampler/dependency evidence
is unchanged, with zero new fits or independent scientific replications. Ranks
remain relative to the named finite cohort, not population positions, composite
multidimensional ranks, known-truth recovery or selection guarantees. This is an
isolated, unmerged, unreleased and unpublished increment; MS4/MS6 remain open.

**Parent candidate: conditional classification (2026-10-12).** The
[classification successor](../../results/workflows/20261012-posterior-classification-01/verification.json)
implements `posterior_classification`, which operates on
explicit person coordinates in one ability dimension, with required cutoff and
probability rule. It retains conditional ability SD/ETI, individual posterior
risk, expected cohort error counts and any-error probability evaluated jointly.
It is also an optional common report section and saved-comparison example option,
with source identity, warnings, captured failures and public bundle persistence.
Existing sections and comparison values are checked against eight actual cached
short fits; no new fit or independent scientific replication is generated.

Numerical MCSE, conditional posterior uncertainty and known-truth repeated-study
error rates remain separate. Exact finite examples test dependence and boundary
rules; final-source replay reuses the saved results. Classification is binary,
one dimension at a time, with no standard-setting default, linking, ranking,
multidimensional composite, conditional-precision curve or new-design guarantee.
Likelihood/prior/sampler evidence is reused unchanged. The source/manual is
isolated, unmerged, unreleased and unpublished; MS4/MS6 acceptance stays open.

**Parent candidate: K-fold numerical error (2026-10-12).** The
[MCSE successor](../../results/workflows/20261012-kfold-mcse-01/verification.json)
preserves the D1 model, priors,
sampler and cache format, and adds optional first-order MCMC error to common
K-fold aggregation/comparison and the saved-cache example. Sum the delta
influence across ratings within each draw; keep autocorrelation and distinguish
independent simulation streams from dependent training datasets. Fold/model RNG
independence declarations are separate. Data-sampling SE is still not computed.

Short/degenerate numerical estimates and missing/failed folds stay unavailable,
with diagnostics retained. The existing actual D1/D2 short caches reproduce
unchanged scores and correctly return missing MCSE. The default existing K-fold
contract is regression-checked; mathematical checks and fresh-process persistence
use saved or synthetic draws with zero new fits/independent scientific replications.
The receipt distinguishes staged validation from the unchanged parent evidence.
No new statistical acceptance, release, merge or publication is claimed.

**Parent candidate: matched-dimensionality extension (2026-10-12).** The
[one-dimensional MGMFRM successor](../../results/workflows/20261012-unidimensional-mgmfrm-01/verification.json)
adds D1 explicitly with an
all-active one-column Q, retains the MGMFRM likelihood/prior rules, and labels
its contract separately from scalar rater-step GMFRM. The new public planning
example aligns item-owned steps, scale, loading count and prior convention with
a between-item D2+ comparator. Matching these conventions does not equalize
joint predictive priors or supply K-fold SE/MCSE. Correlated fitting remains 2D.

The density/gradient oracle and native Stan checks cover the changed dimension
boundary; the existing D2 family contracts and native targets remain verified.
Four deliberately short new fits cover the public execution/result paths, with
two saved D2 folds reused for actual heldout comparison. Report persistence and
a fresh-process replay retain all warnings. No independent simulation replication,
scientific acceptance, release, merge or publication follows. Read the staged
receipt for the exact checks and retained runner failures; successful saved fits
were not refitted to resolve a build-cache path mistake. The eight-type integration
evidence below is retained for the unchanged operations, not claimed as a newly
rerun full suite on this successor.

The [workflow reconciliation and cache repair](../../results/workflows/20261012-workflow-evidence-review-01/verification.json)
reviews the cumulative candidate, not just its newest API. This supersedes the
implementation status in the dated tables above. It does not supply MS4 scientific
acceptance or MS6 independent review. Use the candidate path in the receipt;
the root checkout and the previously hosted preview are different snapshots.

**Current public-manual handoff (2026-10-12).** The
[documentation-only successor](../../results/workflows/20261012-supported-workflow-handoff-01/verification.json)
reconciled the manual. Its runtime, tests, examples and committed
dependency files are byte-identical to the cache-repair candidate; only NEWS and
five public guide pages change. The
[public model/operation and scientific-evidence tables](../../results/workflows/20261012-supported-workflow-handoff-01/candidate/docs/src/scope.md)
connect the eight result types to usable entry points and claim limits. They add
the previously omitted normalized-MGMFRM and exchangeable-rater-MFRM rows and
distinguish the raw prior's rater-label asymmetry from normalized priors.
The saved comparison/recovery guide is now English, retaining its seven code
examples and all legacy heading/permalink links. These are claim-to-help and navigation
repairs, not MS4 verdicts or new scientific evidence. Reuse the parent runtime
verification rather than repeat fitting for a documentation change.

**Previous executable public-workflow candidate (2026-10-12).** The
[eight-type workflow successor](../../results/workflows/20261012-eight-model-saved-workflow-01/verification.json)
is the parent of the D1 extension above. It preserves its own parent's library
source and dependencies, extending `examples/saved_prediction_workflow.jl` and
its focused tests/help. The example now accepts all eight types and optional
per-model category, explicitly selected finite-cohort reliability and
response-matched agreement choices. Dataset/rating IDs come from the comparison
arguments; all fits must share the same row order. Different row orders still
use `saved_model_comparison` with per-model IDs and individual reporting routes.
Native report schemas and warning semantics are retained. The existing calls
remain valid; invalid requests fail before output is written. An external I/O
failure is not an all-model transaction.

Validation reuses one previously fitted fold per type (eight saved fits, 16 draws
each): 165 checks cover score/diagnostic/MCSE agreement, metadata, requested
sections, warnings and report reload. Focused example tests add 46 checks, with
13 in the existing fresh-process replay. These are staged implementation checks,
not extra replications, calibrated inference, automatic model selection or an
independent-user review. The earlier sixteen-fit and common-report persistence
evidence remains applicable to unchanged library code.

| Result type | Fitting entry | Common operations verified in the candidate | Retained boundary |
| --- | --- | --- | --- |
| `MFRMFit` | `fit` | Saved-row prediction/criteria/comparison, refit preparation and heldout scoring, diagnostics/MCSE, recovery, integrated reporting, cache/report persistence | Stable one-dimensional MFRM; arbitrary new likelihood terms are not implied |
| `GMFRMFit`, `MGMFRMFit` | `Experimental.fit` with explicit prior | The same common operations | Experimental targets; family, threshold ownership, scale and dimensionality can change together |
| `Experimental.NormalizedMGMFRMFit` | `Experimental.fit` with `NormalizedMGMFRMPrior` | The same common operations | Raw and normalized priors are different targets; no default-prior recommendation follows |
| `Experimental.CorrelatedMGMFRMFit` | `Experimental.fit` on a correlated specification | The same common operations | Declared two-dimensional correlation target; not arbitrary-dimensional fitted covariance |
| `MultidimensionalMFRMFit` | `Experimental.fit` with fixed Q coefficients | The same common operations for canonical records | Unit-logit scale; legacy v1 refusal remains explicit for reports/recovery |
| `Experimental.CorrelatedMFRMFit`, `Experimental.ExchangeableMFRMFit` | `Experimental.fit` with the declared correlation/prior | The same common operations | Correlation and fixed rater-kernel scale retain their model-specific meanings |

Here, common comparison means the qualified `compare_predictions` and
`compare_kfold_predictions` routes, not automatic expansion of legacy
`compare_models`. K-fold preparation, scoring and aggregation are implemented;
the saved example actually fitted two folds for each of the eight types. That
example is not a general, resumable multi-model refit executor. Its sixteen
short fits are operability evidence, not precision, calibration or model-choice
evidence. No repeated-sampling K-fold SE or automatic winner is established.

The integrated `reporting` option connects category functioning, explicitly
selected finite-cohort reliability and response-matched agreement for all eight
types. It does not extend every historical MFRM diagnostic to every model.
Assignment-adjusted DFF and Pathway maps remain scoped to ordinary unidimensional
MFRM. Category step owners follow the fitted family/threshold contract; an API
report does not make arbitrary facet-specific thresholds estimable after fitting.
New-level prediction, fitted DFF/halo, conventional Strata, composite decisions
and ability-precision curves retain their separate requirements. Observed-score
nominal/ordinal alpha and complete-crossed two-way ICC are now implemented as
described in Sections 13–14; sparse-design ICC, their coefficient intervals and
severity adjustment are not. Selected-person classification and finite-cohort
ranking are implemented within their declared cohorts and dimensions.

**Evidence reuse and the defect it exposed.** Against the completed ordinary-test
snapshot, the incoming integrated candidate preserves 58 of 64 existing `src`
files byte for byte and adds six source files that
supply the added reporting/sensitivity functions. Existing-file differences are
localized to reporting/figures, recorded-sample validation and module inclusion;
`Project.toml` and both committed manifests are unchanged. The common prediction,
comparison, refit and recovery implementations are unchanged. Their successful
numerical work is retained rather than repeated. Source identity is evidence for
reuse, not proof against every possible cross-module interaction.

A targeted check then connected the sixteen previously saved actual-fit caches
to the new integrated report. The first six passed; ten recorded-fit caches were
rejected solely because reconstructed posterior means/SDs differed at floating-
point roundoff. Across the first fold of each affected type, 129 fields differed,
all means/SDs, with maximum absolute difference 2.22e-16. Original input hashes
matched. The same differences appeared with both dependency environments; using
`-O2` instead of `-O0` did not resolve the failures. A particular compiler or
package version has not been established as the cause.

The isolated fix allows a moment-only comparison envelope of
`8 * n_draws * eps(Float64) * max(abs(reconstructed_mean), reconstructed_sd)`.
It is a compatibility policy for finite reduction roundoff, not a scientific
precision criterion or a certified universal error bound. All remaining fields
are compared exactly, and original sample/artifact/archive hashes are still
verified. Stored values are never rewritten. Boundary and altered-payload tests
include small and substantive moment changes, modified quantiles, invalid SDs,
changed metadata, and re-sealed artifacts. The failed stages and successful
partial evidence are retained in the receipt.

**Remaining completion work.** Staged local checks from multiple snapshots and
environments are not a single current full-suite run. The bounded minimum-Julia
saved-result checks above and the dated manual's hosted checks are complete;
full distribution, other OS and package CI/release acceptance remain separate. MS4 must select a
scientifically defensible roster, and MS6 still needs an independent reviewer
and an unfamiliar user. Broader requested product features remain on the roadmap;
they are neither erased from it nor automatically prerequisites for every
supported foundation workflow. Use the
[current global/local priority checkpoint](../../ROADMAP.md#globallocal-priority-review-2026-10-12)
and explicit implementation order to select further work, preserving this cache
compatibility fix and distinguishing completed reporting increments from their
remaining scientific, workflow and publication acceptance.

### 8.2 Current model/prior/operation reconciliation (2026-10-13)

**The operation is conditional on the full route, not just a family or result
type.** The eight-type table above remains a useful saved-workflow inventory;
it does not enumerate all coefficient/prior policies. The following distinctions
are required when advertising the current source. `A` denotes Julia AdvancedHMC,
and `C` denotes CmdStan; all experimental routes retain their structural limits.

| Route | Prior and threshold owner | Fitting / saving | Critical interpretation or operation limit |
| --- | --- | --- | --- |
| Scalar MFRM | `MFRMPrior`; shared RSM or item PCM | Stable `fit`; default is random-walk Metropolis and one chain, not NUTS; documented alternative backends and manual caches | Unit-logit convention; scalar maps/fit statistics do not automatically apply to generalized models |
| Scalar GMFRM | `GeneralizedPrior`; rater-owned steps | `Experimental.fit`, A/C; manual cache; automatic experimental cache restricted to A | Item discrimination multiplies rater consistency; this is not simply D1 of item-step MGMFRM |
| Independent fixed-Q MGMFRM | `GeneralizedPrior`; item steps, D≥1 | `Experimental.fit`, A/C; manual cache; automatic experimental cache restricted to A | Returns `MGMFRMFit`; response-surface functions require this type and D≥2 |
| Independent normalized MGMFRM, unwrapped | Explicit `NormalizedMGMFRMPrior`, exchangeable/source; item steps, D≥1 | A/C, but binary fitting only on A; manual cache only | Returns `NormalizedMGMFRMFit`; no normalized-fit response-surface method; no correlated normalized route |
| D1 fixed/free item-slope restriction | Exchangeable normalized prior; item steps; rater consistency fixed one | A with raw coordinates only; manual cache and known-level refit planning | Also returns `NormalizedMGMFRMFit`; coefficient policy and removed/fixed coordinates come from metadata; no CmdStan or source-prior route |
| D1 mean-profile restriction | `MeanProfilePrior` over the exchangeable base; item steps; both coefficients fixed one | A/raw only; manual cache and known-level refit planning | Also returns `NormalizedMGMFRMFit`; exact item/category IDs and mean units are part of the target; unpublished in the October source preview |
| Correlated MGMFRM | Explicit `GeneralizedPrior`, LKJ shape in specification; item steps, between-item D=2 | `correlated(spec)` then A/C; manual cache only | No higher-D fitted covariance, normalized prior or response-surface method |
| Fixed-coefficient multidimensional MFRM | `MFRMPrior` or fixed-scale `ExchangeablePrior`; item steps | Independent or admitted between-item D=2 correlated specification; A/C and manual caches | Unit logits; exchangeable-rater prior is not an MGMFRM normalized prior; no response-surface method |

Source checks use `experimental.jl`, `mgmfrm_normalized_fit.jl`,
`mgmfrm_slope_restriction.jl`, `prediction_refit.jl`, `response_surface.jl` and
the stable fitting entry in `bayesian_fit.jl`. Family-level
`surface_contract(:mgmfrm).supported_backends` cannot substitute for the
slope-wrapper contract `surface_contract(model; prior)`. Saved normalized,
fixed-slope, free-slope and mean-profile fits require metadata to distinguish
their policies; a shared result type does not make their priors interchangeable.

**Discrepancies corrected.** The generic `Experimental.fit` help implied that
CmdStan applied to every supported configuration, and the common sampler text
did not exclude normalized automatic caching. These now state the exceptions.
The high-level support/prior tables omitted slope and mean-profile variants;
they now link to their exact requirements and distribution status. Surface
guides described independent MGMFRM too broadly; they now name the actual
`MGMFRMFit` method and D≥2 requirement. The older inventory's implication that
all ICC/alpha remained future work is corrected above. No unsupported method
is added just to make the previous wording true.

**Uncertainty and persistence.** Reuse the documented ETI API: summary
`lower`/`upper` are quantile probabilities and `intervals` contains masses;
plots use `interval`. Model-coordinate summaries are separate from raw-coordinate
summaries. Changing to 99% ETIs reuses draws, but tail MCSE and scientific
precision remain unresolved for short warned fits. HDI is still not integrated.
Manual native caches require the original Julia/dependency environment; portable
JSON carries computed reports, not reconstructible fits. K-fold preparation
still requires actual training fits and known levels. No new-level predictor,
automatic comparison winner or general simulation runner follows from this review.

**Bounded exit and remaining acceptance.** Verify these specific help/support
corrections against the selected candidate and existing saved draws, retaining
all warnings. The previous eight-type cache/refit/report evidence remains
applicable to unchanged computation; this is not a fresh all-model fit or a
single full-suite/platform acceptance. MS4's claim decision, relevant broader
compatibility checks, independent scientific review, unfamiliar-user acceptance
and successor publication remain open. New simulations stay deferred under the
user's current instruction; their prospective specifications can be reviewed
without running them.

The saved-result check reuses five actual short fits: raw D2, normalized D2,
D1 fixed/free item slopes and D1 mean profiles. In their matching dependency
environments, 38 legacy-workflow assertions and 12 mean-profile assertions
pass. These check public 99% raw/model-coordinate summaries, containment of
the corresponding 90% intervals, retained warning status, shared result types
with distinct coefficient policies, surface method availability and a 2×2
conditional probability grid using all retained raw-MGMFRM draws. Loading an
existing portable report preserves its warning and mean units. No fit,
prior draw, predictive replication or random dataset is generated.

The initial attempt used the newer mean-profile environment for all five caches.
The raw fit passed five checks, but the older normalized cache was refused by
artifact validation. Its successful earlier replay environment has 64 different
non-package dependency records. Restoring that environment while retaining the
same reviewed source allowed all four older caches to pass; the mean-profile
cache passed separately in its own environment. No validation was relaxed and
no cache was rewritten. This establishes environment-sensitive native replay,
not the identity of a causal dependency or universal cross-environment support.
The first failure and script are retained; its five overlapping passes are not
added to the final 50. Environment matching should precede cache selection in
subsequent replay tasks, rather than treating a shared Julia version as enough.

The final English manual and REPL help pass 197 language/example checks, a
23-page build and 1,344 local fragment links. Only prose and docstrings in
`experimental.jl` and `response_surface.jl` change; all executable text outside
those documentation strings, tests, examples and dependency declarations remain
identical to the sealed guide parent. Existing numerical evidence is reused.
The frozen MS3 sources, published preview and both sealed local predecessors
remain unchanged. The final result is an unpublished review candidate, not a
full-suite/platform pass, unfamiliar-user acceptance or scientific model adoption.

## 9. 設定・ヘルプ・具体例の整備時期

**着手はMS4終了後まで待たない。** MS4は科学的に支持する用途・prior・主張を決める工程であり、
関数の引数、出力、未対応入力、保存復元、警告の説明は現在の実装から整備できる。
MS5の最終受入はMS4の支持表と整合する必要があるが、作業開始の依存関係とは分ける。

| 時期 | 整備するもの | 完了を示す証拠 |
| --- | --- | --- |
| pilot中の現在 | 設定をデータ/モデル・事前・計算・予測/評価・出力へ分けた説明、既存docstringへの案内、保存結果を読む試作例、対応/未対応表 | 文書と実際の引数が一致。試作と公開APIを区別し、例が入力を変更せず、警告や予測単位を表示する |
| MS1後、MS2/MS3と並行 | 分離した候補snapshotで共通入口をpackageへ統合し、同じ入口のdocstring・guide・合成データ例を更新 | 対応型のpublic workflowと限定テスト。help・例・runtimeで設定名/既定値/未対応時の挙動が一致。評価中snapshotのhashは不変 |
| MS4後 | 支持するモデル/条件/予測対象、prior推奨の有無、数値上の既定値と科学的推奨の区別を確定 | 全ての科学的推奨がMS4の証拠行へ対応。未解決条件はhelp・report・例でも未解決として見える |
| MS5→MS6 | 最終仕様と説明の整合、初見の利用者による再現、API版と互換性方針の固定 | private helperや手動draw整形なしの再現記録。診断警告の意味と予測対象を利用者が説明でき、blocking feedbackが解決済み |

設定の説明は新しい万能Config型を増やす要求ではない。まず既存のkeywordを整理し、
モデル/事前を変える選択と、計算精度/表示だけを変える選択を見分けられるようにする。
`task`列を渡すだけで課題効果が増えた、保存recordの読込成功で診断が通った、という誤読を防ぐ。

現在の利用者向け入口は[設定とヘルプ](../src/experimental.md#settings-and-help)、
[具体例](../src/examples.md#common-saved-fit-prediction-preview)、
[実行script](../../examples/common_prediction_observations.jl)である。
既存のnormalized例は推定→診断/MCSE→保存復元→report/図を既に示す。新しい例はその保存結果と
元の観測ID列を読み、8型に対応する試作から確率配列の軸・全drawのWAIC/raw IS-LOO・警告を表示する。
これはpublic API全体の確定や参照PSIS検証ではない。新しい例自体は追加推定・ファイル書込みを行わない。

元データの観測IDは読込時に保持し、欠測除外や行の並べ替えにも追従させる。利用者が最初に誤った
IDと行の対応を渡したことまでは、試作のbinding hashから判別できない。共通抽出のequal-row得点と、
foundation専用のglobal person×dimension重みのheldout得点も説明で区別する。
実データへの適用は引き続きMS6と必要機能の受入後である。

### 今回の利用例の検証

[限定テスト](../../test/common_prediction_example.jl)の17項目で、合成MGMFRMの保存cacheからの
読込、非辞書順の観測ID保持、配列軸、全drawのWAICと既存計算の数値一致、sampling warningの
表示、入力cacheのSHA256不変、ID重複/欠落/空欄の拒否を確認した。合成drawの接続検査であり、
追加MCMCや科学的受入の証拠ではない。8型の抽出自体は§7の既存検査を再利用する。

後続の変更はCLIヘルプ/引数検査をimport前へ移すものに限定した。`JULIA_LOAD_PATH=@stdlib`で
`--help`・引数なし・誤った引数の3ケースを実行し、packageをロードせずUsageを表示できた。
`--help`の実測は約0.24秒、観測最大RSS約192MiB。推定本体の高速化率とは別の測定である。
記録は`results/workflows/20261009-common-prediction-example-01/`。17項目の処理本体の検査は
約177秒・最大RSS約1.30GiBで、Juliaのコンパイルを含む。全体テストと文書サイト全体のbuildは
行わず、リンク先の存在、凍結ソース479件・保全成果物1,004件、効率比較の設計receiptの不変を確認した。

## 10. MS6のレビュー資料と実施手順

pilot中にレビューの問いと必要資料を確定し、候補完成後の確認漏れを減らす。
ここでは担当者を割り当てたり、レビュー済みと記録したりしない。現在のC1〜C6の判断は
[ROADMAPの証拠対応表](../../ROADMAP.md#current-claim-to-evidence-register-ms4-preparation)を参照し、
同じ判断を別の台帳へ複製しない。9月のレビュー資料と当時の未解決事項も履歴として保持する。
最終MS6判定にはMS4の支持範囲とMS5の候補版が必要だが、数式や過去の証拠の予備レビューは先にできる。

### 渡す資料と、今から準備できる範囲

| 資料 | 現在の入口 | 最終レビューまでに揃えるもの |
| --- | --- | --- |
| 対象・主張 | ROADMAPのC1〜C6、[推定対象と識別](mgmfrm-estimands-identification.md)、foundation §12/20 | MS4の量・条件別verdict、許容する説明と除外、数式の前提。raw/normalized、独立/相関、固定/未知水準を混同しない |
| 完了した回復・感度・失敗 | 192fitの[最終集計](../../results/workflows/20261004-foundation-fixed-facet-assessment-01/summary.json)と[費用・精度分析](../../results/workflows/20261004-foundation-fixed-facet-assessment-01/final-analysis-20261006.json) | 計画/入力/結果hash、全条件の予定分母と適格ID、R1/SD 0.25の過少被覆を含む未解決の説明。新たに192fitをやり直さない |
| 予測・効率 | foundation §§23–26、凍結したpilot、本比較の設計receipt | MS1終了receipt、MS2採否と実装hash、MS3の固定Nと最終6平均/7対比・副指標。現在は未完成であり、途中集計を最終結果として渡さない |
| 利用者の再現 | §8–9の対応表、設定guide、合成例と保存結果の例 | MS5候補commit、Project/Manifest、合成入力と観測ID・尺度・seed、許可された公開関数だけを使う手順、期待する出力/警告、保存復元の照合記録 |
| 版と互換性 | 既存のtarget/source/sample/cache identity | 科学的評価に使った版とAPI候補版の対応。対象/採点を変える修正なら影響する証拠を再点検し、単に最新commitへ合格を移さない |

### 科学レビューで答えてもらう問い

| 問い | 必要な確認・回答 |
| --- | --- |
| 数式と推定対象 | 事前で定める原点/尺度と尤度から区別できる量を分けられるか。zero-sum kernel SDと周辺SD、位置変換とJacobian、完全交差の導出の適用範囲が一致するか |
| 回復・感度・失敗 | 条件ごとに32反復、6条件が同じブロックを共有すること、対応差の適格集合を確認する。184/192や全量診断成功を較正保証に変えていないか。1/32のI1被覆を含め、負の証拠が推奨priorの判断に残るか |
| 予測と不確実性 | 既知水準の未使用評定という対象、global person×dimension重み、完全5fold条件、反復SEとMCMC MCSEの区別、欠測/失敗を含む予定分母が保たれるか。R0→R1のNLL差を推定法だけの差と誤読していないか |
| 計算と採用範囲 | 密度一致・診断・精度・費用を別々に判断しているか。速さや良い予測が回復/較正の問題を解決したことになっていないか。新しいbackendへ証拠を移す根拠が十分か |
| 結論 | C1〜C6の各結論の範囲・強さに同意できるか。修正が必要なら、主張・証拠・API説明のどこをどう変えるべきか。較正等の未確定を明示した範囲にも、支持できる核があるか |

### 初見利用者の再現課題

実装者による操作確認と区別し、最終候補と文書だけを使う。次の課題は追加の統計研究ではなく、
一つの小さい合成workflowと保存結果の再利用で確認する。既存の大規模推定を再実行する必要はない。

1. 入力の役割、カテゴリ順、Q行の対応、観測IDを設定し、モデルとpriorを選ぶ。説明用の短い
   draw数・prior値を、精度保証や推奨値だと受け取っていないかを自分の言葉で説明する。
2. 候補版で文書化した合成例を実行し、診断・MCSE・事後区間を確認する。準備済みの警告を含む
   合成fixtureでも、警告の意味と「数値は返ったが結論は保留」の区別を説明する。
3. 保存結果を新しいJulia sessionで読み、指定した要約・確率・得点・図を再現する。正規化事前、
   尺度、backend、診断警告が保持されることを確認する。個人の作業pathやprivate helperに依存しない。
4. 観測IDの重複/欠落、異なるカテゴリ順、予測対象の取り違え、未知水準などの小さい反例を試す。
   未対応入力に黙って別の計算が適用されず、理由と修正方法が分かるかを確認する。
5. 何を条件づけた予測か、何を重み付けした得点か、SEが何の不確実性か、どこまで比較できるかを
   説明する。具体例のコマンドが動いたことだけで再現課題の合格にはしない。

### 人選・記録・終了条件

科学レビュー担当と初見利用者確認担当は**未割当**。担当者、実装への関与、レビュー役割を記録し、
実装者自身の再検査を独立レビューに数えない。外部への依頼はまだ行わない。
担当未定でも資料の整合や既存証拠の照合は進められるが、MS6を完了とはできない。

レビュー記録には候補commit・証拠の基準日・担当/役割・対象C番号・確認した操作・再現ログ・
指摘・重要度・対応commit・再確認結果を残す。対象分布/採点/保存結果の取り違え、根拠を超えた
科学的主張、指定したpublic workflowを再現できない問題は完了を妨げる指摘として扱う。
未対応を適切に明示した将来拡張は、その候補版の約束に含まれない限り完了条件へ自動追加しない。

実装者が対応内容を記録し、レビュー担当が指摘の解決を確認した後、MS4の支持範囲・MS5のAPI版・
互換性とhelpを同じ候補commitへ結合する。完了を妨げる指摘がなく、科学レビューと初見再現の
両方が記録された時点でMS6を閉じる。レビュー資料の準備、テスト件数、独立した算術検算は
その最終判定を代替しない。

## 11. Small slope pilot and computational refinement (2026-10-12)

**Question and decision.** Can a matched item-slope restriction be implemented
without changing the threshold owner or the shared prior, and does ordinary
prior whitening improve usable sampling efficiency? The
[frozen plan](../../results/workflows/20261012-slope-pilot-01/plan.json) and
[closed verification](../../results/workflows/20261012-slope-pilot-01/verification.json)
answer the engineering question with finite mathematics and a small simulation.
They do not choose an empirical model or complete the public fixed/free-slope API.
The current source/manual candidate in §8.1 remains unchanged.

### Target, scale and what is identified

For adjacent categories, the prototype uses

\[
\log\{p(Y=k)/p(Y=k-1)\}
=1.7\{a_i\theta_p-b_i-r_j-t_{ik}\}.
\]

Rater consistency is fixed at one. Rater severity and each item's actual step
vector sum to zero. The two models differ only in fixing all item slopes at one
versus assigning independent normal priors to their log slopes. Both use the
same independent normal person/item priors and normalized zero-sum Gaussian
severity/step priors. The declared SDs are 0.8 (person), 0.9 (item), 0.6 (severity
kernel), 0.7 (step kernel) and 0.3 (log slope). These are experimental inputs,
not recommended defaults. Fixed coordinates are removed with their prior factors;
a zero prior SD is not used as a substitute for a fixed parameter.

When slopes equal one, multiplying **all** person/item/rater/step coordinates
and their prior SDs by 1.7 gives the unit-logit PCM likelihood. Merely changing
the slope value does not harmonize the scale or the prior. This equality of
likelihood kernels does not equate the prototype to every existing MFRM prior.
In the free model, b is a location/intercept inside this equation; b/a is a
different estimand with a different induced prior.

The likelihood is invariant to theta -> theta+c and b -> b+a*c, and, with free
slopes, to theta -> s*theta and a -> a/s for positive s. Finite counterexamples
verify both identities while showing that the declared prior density changes.
Thus the proper fixed-scale priors anchor these directions; likelihood-only
identification is not established by a successful fit.

The restricted Gaussian prior in free coordinates has covariance LL'. For a
zero-sum block of full length n and kernel SD sigma, the last-reconstructed
free-coordinate covariance is sigma^2 (I - 11'/n). With x=Lz, the transformed
posterior is log p(Lz,y)+log|L|. The scalar implementation, the restriction of
the existing normalized Julia target and independent Stan code agree in density
and gradient, including this Jacobian. The 133 algebra/prior-predictive checks
and 64 native Stan checks pass; maximum native density and gradient differences
are 2.28e-13 and 1.14e-13. Hessians at raw zero are positive definite for fixed
slopes but indefinite for estimated slopes. A condition number at that point
is not evidence about global mixing or a universal benefit of whitening.

### Small simulation and what it showed

Four independent generated datasets cross two allocation patterns with two
truths. Each contains 12 people, four items, three raters and four categories.
The complete design has 144 ratings and all 12 people shared across raters; the
sparse connected design has 56 ratings and only one shared person. Generating
slopes are either all one or (0.6, 0.85, 1.15, 1.6). All four datasets contain
every category, so this pilot does **not** exercise observed category absence.
Finite extreme-coordinate arithmetic was checked separately. There is one
dataset per condition, not replicated coverage or SBC evidence.

Each dataset is fit with both slope policies in raw and prior-whitened
coordinates: 16 fits and 64 serial chains, each with 200 warmup and 200 retained
draws. Physical initial values match across coordinates, simulation seeds are
distinct, and coordinate order alternates. No attempt is replaced or extended.
Prior-predictive draws, all original coordinate summaries, mean and endpoint
MCSE, probability recovery, timing and raw CSV outputs are retained.

| Check or result | Observed outcome | Interpretation |
| --- | --- | --- |
| Execution and trajectory problems | 16/16 completed; zero divergences and depth hits; minimum E-BFMI 0.659 | Necessary checks, not a convergence guarantee |
| Complete numerical screen | 0/16 qualified; 1/16 passes all-coordinate R-hat <=1.01 and 3/16 pass both bulk/tail ESS >=400 | Short chains remain numerically unresolved; this does not prove the models are wrong |
| Same-target coordinate means | 224/224 difference screens pass; 219/224 combined-MCSE precision screens pass | Non-detection of a difference is not adequate precision or full posterior equivalence |
| CPU time | Whitening/raw ratios 0.817–0.946 | Observed runtime reduction alone is insufficient for adoption |
| Minimum coordinate bulk ESS per CPU | Whitening/raw ratios 0.611–1.686 | Some fits generate less usable information per unit cost despite running faster; none is a qualified adoption pair |
| Cost | Sampling 19.0 s elapsed / 16.1 CPU s; roughly 31.8 MiB attempt outputs before completion records | Includes warmup and output; compilation and analysis are separate. All five execution stages total 100.6 s, with 1.52 GiB observed owned-process peak RSS |

The mean comparison uses the predeclared approximate Bonferroni multiplier
3.691 over 224 coordinate means and requires combined mean MCSE <=0.1 pooled
posterior SD. This is a coarse engineering comparison, not an application-specific
accuracy criterion. No pair meets both fits' numerical qualification. Endpoint
MCSE is retained but endpoint equivalence is not claimed. Conditional probability
RMSE/KL against the generating probabilities are descriptive checks, not heldout
performance; they do not support a model-selection recommendation from these
unqualified single datasets. Local per-cell time is not a production speed
guarantee on a machine also doing background work.

### Mathematical refinement using saved draws

The post-pilot analysis reuses the existing
`scripts/mgmfrm_core_location_conditional.jl` helper, without fitting again.
Let m be the person mean and d_i=b_i-a_i*m. With centered persons, d and a held
fixed, the likelihood does not depend on m. Under the specified independent
zero-mean normal person/item priors,

\[
v=\left(J/\sigma_\theta^2+\sum_i a_i^2/\sigma_b^2\right)^{-1},
\qquad \mu=-v\sum_i a_i d_i/\sigma_b^2,
\qquad m\mid\text{rest},y\sim N(\mu,v).
\]

Therefore z_m=(m-mu)/sqrt(v) is a conditionally standard normal direction.
The identity follows by completing the square, and 80 additional checks verify
the scalar formula, existing helper, likelihood invariance, density along this
direction and saved-draw extraction. The within-fit maximum absolute
person-mean/item-location correlation ranges from 0.65 to 0.85. In these saved
draws, standardized residual/offset correlations are at most 0.071, while the
residual still has low ESS under the original sampling coordinates. Postprocessing
has not created independent draws or improved the original chain.

This identifies a specific next computational candidate: reuse the existing
orthogonal person-mean/item-offset map and evaluate conditional standardization
or analytic handling of this mean direction for the restricted target. The
Gaussian identity is existing project mathematics, not a new discovery. Its
applicability has now been checked for this restriction. Independent priors
must not simply be assigned to the offsets; the original joint prior and any
additional Jacobian must be retained. Hard anchors, correlated/non-normal priors
or different location equations require another derivation. Loading/ability
scale curvature is not eliminated by separating the mean.

**Decision.** Close this pilot with all outcomes, adopt neither raw-to-whitened
performance claim nor a new default, and do not expand to a large study. First
verify the proposed location-coordinate density, Jacobian and reconstruction;
any subsequent small comparison gets a separate prospective plan. A larger
recovery/design study requires a named scientific decision, adequate replication
precision and cost justification. This uses
[Stan's distinction between computation and statistical efficiency](https://mc-stan.org/docs/stan-users-guide/efficiency-tuning.html)
and keeps engineering simulation distinct from
[simulation-based calibration](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html).

### Conditional-location follow-up: exact target, bounded computational evidence

The separate [prospective plan](../../results/workflows/20261012-slope-location-01/plan.json)
and [closed receipt](../../results/workflows/20261012-slope-location-01/verification.json)
test the particular mean/item dependence found above. This addresses the
computational feasibility of the matched fixed/free-slope option. It does not
add a condition grid or substitute a new performance study for the package's
model-comparison workflow. Existing candidate source, environments, four datasets
and raw comparator draws are reused without modification.

Let H be the existing symmetric orthogonal person rotation, with
H e1 = 1/sqrt(J), and let u contain the other J−1 person coordinates. Replace
the first rotated coordinate by a standardized conditional residual z_m:

\[
m=\mu(d,a)+\sqrt{v(a)}z_m,\qquad
\theta=H(\sqrt J m,u)^T,\qquad b=d+am.
\]

All remaining coordinates, including free log slopes, retain their original
values. The earlier formula gives mu and v. The inverse computes m from the
person mean, d=b−am, u from H theta, and z_m=(m−mu)/sqrt(v). The orthogonal
rotation has absolute determinant one, as does the triangular location shift.
Replacing the first rotated coordinate therefore gives

\[
\log\left|\frac{\partial x}{\partial z}\right|
=\tfrac12\log\{Jv(a)\},\qquad
\log p_z(z,y)=\log p_x(x(z),y)+\tfrac12\log\{Jv(a)\}.
\]

This determinant remains valid when the offsets and slopes are sampled: order
the unchanged slopes first and the relevant Jacobian blocks are triangular.
When slopes are free, v(a) is not constant, so omitting this term changes the
posterior, including its loading gradients. The original normal prior is
evaluated at reconstructed theta and b; independent priors are **not** assigned
to the offsets. In these coordinates z_m factors as an independent standard
normal under the posterior. This removes the selected mean direction's
dependence, but not general loading/ability scale curvature or every slow
direction elsewhere in the model.

Before sampling, 349 checks verify both inverse directions, the explicit AD
Jacobian determinant, reconstruction through the existing package location map,
the existing conditional-normal helper, original normalized target density and
gradients, likelihood invariance, derivative −z_m and zero mixed Hessian entries
for this direction. A negative control verifies nonzero Jacobian derivatives
for estimated slopes. Independent native Stan evaluation adds 32 checks at
three points for each model/dataset combination: maximum density error
4.55e−13 and gradient error 1.14e−13. These are finite numerical checks supporting
the derivation, not a global floating-point guarantee.

The frozen follow-up consists of eight new fits, one per existing dataset and
slope policy, with four chains, 200 warmup and 200 retained draws, diagonal
metric, maximum depth eight and target acceptance 0.9. The observations and
physical starting points match the previous raw fits; all new chain seeds are
distinct. Forty preparation checks verify that correspondence. Seventy-two
saved-output checks verify plan/CSV identity and every stored raw coordinate's
reconstruction from the sampled coordinates. Julia evaluates and reconstructs
the target; native Stan performs this sampling. No Julia/Stan posterior
sampling equivalence is claimed.

| Dataset / fitted slopes | Previous raw mean-residual bulk ESS | New mean-residual bulk ESS | New minimum raw-coordinate bulk ESS | New / previous raw ESS per CPU, minimum raw coordinate |
| --- | ---: | ---: | ---: | ---: |
| Complete, equal truth / fixed | 201 | 1,380 | 932 | 4.52 |
| Complete, equal truth / free | 212 | 1,637 | 513 | 2.49 |
| Complete, heterogeneous truth / fixed | 129 | 1,014 | 778 | 5.68 |
| Complete, heterogeneous truth / free | 126 | 1,744 | 795 | 5.90 |
| Sparse, equal truth / fixed | 275 | 1,921 | 512 | 1.33 |
| Sparse, equal truth / free | 306 | 2,322 | 560 | 1.27 |
| Sparse, heterogeneous truth / fixed | 339 | 1,247 | 370 | 0.87 |
| Sparse, heterogeneous truth / free | 313 | 1,654 | 501 | 1.27 |

The ESS/CPU column uses the minimum over original coordinates, which need not
be the same parameter before and after the change. It does not use only the
favorable normal direction. Negative autocorrelation can make estimated ESS
exceed the 800 saved draws; it does not mean additional draws were generated.
See [Stan's effective sample size explanation](https://mc-stan.org/docs/reference-manual/analysis.html#effective-sample-size).
The raw timings are historical and were not interleaved with this follow-up.
All ratios are descriptive single-run measurements on a shared machine.

The complete prospective numerical screen passes **0/8 fits**, even though
there are no divergences or depth hits and minimum chain E-BFMI is 0.787.
Every fit has at least one original-coordinate R-hat above 1.01; the maxima
range from 1.0105 to 1.0179. Six of eight pass the all-original-coordinate
bulk/tail ESS thresholds of 400. Qualification also checks every sampled
coordinate and requires mean MCSE <=0.1 posterior SD. All 224 original-coordinate
mean difference screens and combined-MCSE precision screens against the saved
raw fits pass. Because the old and new fits remain unqualified, this is not an
accepted coordinate pair, posterior-equivalence result or model-selection
recommendation. Interval endpoint MCSE are retained without equivalence claims.

Saved diagnostics locate the sparse/heterogeneous fixed-slope case's minimum
bulk ESS in free rater severity, rather than the separated mean. Remaining
flags also concern individual abilities, steps and one free loading across
conditions. This narrows the interpretation: the targeted dependence improves,
while short-chain whole-fit precision remains unresolved. It does not establish
a defect in the likelihood, nor justify endlessly adjusting the sampler until
all checks happen to pass. The normal residual's largest absolute deviations
from mean zero and second moment one are 2.05 and 1.68 estimated MCSE respectively;
these are descriptive oracle checks, not another acceptance or SBC claim.

Sampling consumes 8.5 seconds elapsed / 7.4 CPU seconds and approximately
16.2 MiB of attempt outputs before completion records. The four execution
stages, including compilation and saved-draw analysis, total 73.0 seconds, with
observed owned-process peak RSS 1.68 GiB. These measurements exclude analyst
time and are not projections for large studies. No arbitrary elapsed cutoff,
retry, extra draws or new datasets were used. All 859 current candidate files
and 526 frozen MS3 source/environment files retain their hashes.

**Decision.** Keep the verified map as an internal computational option and
close this comparison. Do not adopt a default, infer a general speedup, or
launch a larger study. The next product task remains the explicit fixed/free
slope fit specification and original-coordinate saved-result contract, with
the common threshold owner, prior and scale kept visible. Numerical warnings
must survive that workflow; implementation acceptance is distinct from empirical
model selection, recovery/SBC acceptance and independent scientific review.

## 12. Explicit fixed/free-slope workflow (2026-10-12)

The [implementation receipt](../../results/workflows/20261012-slope-api-01/verification.json)
closes the bounded product task identified in Section 11. The question is whether
users can change item-slope policy while keeping the threshold owner, location
and step priors, scale constant, observations and refit split explicit. The two
earlier pilots remain closed. Their unqualified fits do not motivate additional
sampling merely to obtain passing diagnostics.

The experimental interface is:

```julia
E = BayesianMGMFRM.Experimental
fixed = E.slope_restriction(spec;
    item_slopes=:fixed_one, rater_consistency=:fixed_one)
free = E.slope_restriction(spec;
    item_slopes=:estimated_positive, rater_consistency=:fixed_one)
```

`spec` must be a one-dimensional MGMFRM partial-credit specification with an
explicit one-column Q matrix. Both models use item-owned steps and adjacent
log odds `1.7*(a_i*theta_p - b_i - r_j - t_i,k)`. This is not the scalar
rater-step GMFRM branch. Mapping the fixed model to a unit-logit PCM also scales
all locations, steps and their prior standard deviations by 1.7. Likelihood
identification is not supplied merely by fixing the slopes; the existing
location-prior contract remains relevant.

Fitting requires an explicit normalized exchangeable prior and currently uses
Julia AdvancedHMC with raw coordinates. Fixed blocks are removed from the
sampled vector and from the normalized prior density, then reconstructed as
ones for downstream model calculations. The existing six-scale prior record
is retained: log-consistency scale is inactive in both policies, and
log-discrimination scale is inactive when item slopes are fixed. Reports mark
these settings as inactive; changing them cannot change the density. They
remain declared inputs in the saved identity. Surface metadata gives the exact
active raw-parameter order for explicit starts.

The existing `NormalizedMGMFRMFit` result type supports summaries, diagnostics,
MCSE, conditional predictions, reports, manual caches and portable bundles.
Fixed parameters are structural constraints, not highly precise estimates.
Policy and target identity survive reload, as do diagnostic warnings. K-fold
preparation retains the restriction; scoring rejects a fit for the other
policy. Those refit tests use synthetic records and do not estimate comparative
heldout performance. Public CmdStan fitting, transformed coordinates, source
priors, higher dimensions/correlation, anchors and automatic caching remain
unsupported for this restriction.

The [English guide](../../results/workflows/20261012-slope-api-01/candidate/docs/src/experimental.md)
and [callable example](../../results/workflows/20261012-slope-api-01/candidate/examples/matched_slope_workflow.jl)
show explicit prior, sampler controls, independent seeds, save/reload and refit
preparation. The example does not select a winning model.

Verification combines 4,124 scoped assertions from recorded successful test
sections, not a full-suite run. Existing normalized-prior/result regressions
are retained, and 32 finite density/gradient comparisons reuse native Stan
outputs from the closed pilot with the new API's raw ordering accounted for.
The only new MCMC consists of two Julia fits on the existing complete/equal-slope
dataset, each with two chains, 10 warmup and eight retained draws. The final
source, inputs and seeds were frozen before execution. Both fits report
`insufficient_draws`; fresh-process cache/report checks retain that warning.

Julia 1.10.8 passes 165 namespace and 18 restricted-target/persistence checks,
using same-version synthetic native caches and portable reports from the actual
Julia 1.12.5 fits. Only the final test-count writer fails because of Julia's
version-dependent return shape; its record is recovered from the successful
log without another numerical run. New-version native cache compatibility and
actual restricted NUTS fitting on Julia 1.10.8 are not claimed. Other harness
corrections and reused successful sections are itemized in the receipt.

The documentation build completes with its existing missing-docstring and
search-index-size warnings. It produces 23 HTML pages; 197 documentation
assertions and 1,265 local fragment-link checks pass. Browser inspection and
hosted publication are not completed. The two-fit example including save/reload
takes 11.7 seconds, while all recorded execution stages, including failed
harness attempts, total 342.8 seconds with observed peak owned RSS 1.56 GiB.
These measurements exclude analyst time and do not support a speed guarantee.

The new candidate contains 862 files; the separate 859-file parent snapshot,
both earlier pilot receipts and all 526 frozen MS3 source/environment files
remain unchanged. The new candidate remains isolated,
unmerged, unreleased and unpublished. The implementation establishes an
operable matched specification; it supplies zero new independent recovery/SBC
replications or accepted model-selection comparisons. The internal location
map is not adopted as a default. Full-suite/platform coverage, distribution
acceptance and independent scientific/user review remain open.

## 13. Observed-score nominal/ordinal alpha (2026-10-13)

The [alpha receipt](../../results/workflows/20261013-ordinal-alpha-01/verification.json)
addresses the requested observed-agreement gap without adding MCMC. The qualified
`krippendorff_alpha` API consumes `FacetData`, requires one item label and an
explicit nominal/ordinal measurement level, and reuses response identity checks.
It returns the coefficient, both disagreements, pairable marginal counts,
coincidence/distance matrices and included/singleton/other-item rating IDs.
Optional `reporting.alpha` preserves this result through common public bundles
and the saved comparison example. Its value does not depend on the fitted
model or sampler quality; existing posterior warnings remain separately visible.

The [English interpretation](../../results/workflows/20261013-ordinal-alpha-01/candidate/docs/src/interpreting-results.md)
states the equation, ordinal distance and missing-rating contract. The
[standalone example](../../results/workflows/20261013-ordinal-alpha-01/candidate/examples/observed_alpha.jl)
needs no fit. Singletons do not enter either disagreement or ordinal margins;
entirely unobserved responses cannot be recovered from absent rows. Negative
alpha stays negative, and zero expected disagreement is undefined. No pooling
of different items, interval-distance metric, CI/SE, bootstrap, ICC, missingness
correction, rater-severity adjustment or population reliability is implemented.

Verification retains 547 finite/reference checks, 322 existing agreement checks,
622 existing reporting checks, 170 new synthetic report checks and eight actual
saved-fit workflows. Julia 1.10.8 adds 579 arithmetic/portable-report checks.
The receipt explains the count-writer error and three incorrect diagnostics-field
assertions; successful sections are retained, and corrected warning checks use
saved-report replay without repeating report generation. Documentation passes
197 policy assertions and 1,278 fragment links across 23 built HTML pages; final
source language policy also covers the updated unreleased notes. This combines
distinct stages/environments, not a full-suite or independent-review result.

There are zero new fits or statistical replications. Execution stages sum to
481.5 seconds including harness failures and overlapping processes; observed
owned-process peak RSS is 2.15 GiB. The separate 862-file parent, eight reused
caches and 526 frozen MS3 files remain unchanged. The new 865-file candidate
is unmerged, unreleased and unpublished; browser/hosted verification and
independent scientific/user acceptance remain open.


## 14. Complete crossed observed-score ICC (2026-10-13)

The [ICC receipt](../../results/workflows/20261013-icc-01/verification.json)
implements the named complete-design coefficient in the existing practical
reporting priority. This increment needs algebra, finite examples and saved-fit
integration, not a new MCMC or recovery study. No larger simulation follows
from its arithmetic success.

The qualified `intraclass_correlation` API requires one item, equal-gap score
interpretation and explicit random/fixed, agreement/consistency and single/average
choices. All responses must have the same rater roster. Incomplete and duplicate
ratings are rejected, without silent deletion. It returns ANOVA components,
coefficient numerator/denominator, response and rater ledgers and source identities.
Negative estimates with a positive denominator remain negative; nonpositive
denominators yield missing coefficients, preserving a finite raw ratio separately.
Repeated responses from a person are disclosed, not treated as proof of independence.
`reporting.icc` preserves the result in public JSON/Markdown/table bundles.

The [English guide](../../results/workflows/20261013-icc-01/candidate/docs/src/interpreting-results.md)
explains the choices. The [no-fit example](../../results/workflows/20261013-icc-01/candidate/examples/observed_icc.jl)
uses two raters differing by one point on three responses: single-rating agreement
is 2/3 and average-rating agreement is 0.8, while consistency is 1 for both.
These are pedagogical observations, not population reliability or calibration
claims. The API guide gives all four ANOVA formulas and denominator limits.

The Shrout-Fleiss example and a rater-offset variant agree with installed
R 4.6.1, psych 2.6.5 and irr 0.85 to the declared 1e-12 tolerance. An independent
rational pair-difference oracle, complete small arrays, recoding/permutation,
negative/undefined values and incomplete rosters cover the finite contract.
Initial Julia 1.12.5 tests pass 763 assertions; three handwritten expectations
were wrong (two decimals and an agreement/consistency label). Those three pass
after correction without changing implementation equations. The initial report
harness also used sparse legacy fixtures as complete cases; the corrected checks
retain their rejection and use complete deterministic reporting draws. These are
synthetic fixtures, not posterior samples or newly fitted models.

New report integration passes 154 assertions across eight types. The public
saved-workflow example passes 16 assertions using two retained actual fits;
both still report insufficient draws, and both give the same ICC because their
observed data are identical. Minimum Julia 1.10.8 passes 775 checks, including
all final arithmetic tests and replay of the 1.12.5 JSON bundles. Newer native
cache compatibility is not implied. The independent R comparisons, minimum
Julia and retained stages are not a single-environment full-suite result.

The final manual passes 197 language/example checks, 23 HTML pages and 1,294
local fragment links. Two intermediate builds exceeded the interpretation-page
size limit; equations and call details were relocated to the API page, retaining
the content and size policy. Numerical checks were not rerun for documentation
changes. Existing missing-docstring/search-index warnings remain in the log;
browser and hosted review are not claimed.

All 865 parent files, two reused fit caches and 526 frozen MS3 files remain
unchanged. The 868-file candidate is isolated, unmerged, unreleased and unpublished.
There are zero new fits and zero statistical replications. This closes only the
complete-crossed two-way point-estimate scope; CI/SE, one-way and incomplete-design
ICC, latent/severity-adjusted reliability, full-suite/platform acceptance and
independent scientific/unfamiliar-user review remain open. These require their
own questions and evidence rather than automatic expansion of this increment.

## 15. Hosted English guide synchronization (2026-10-13)

The [documentation successor](../../results/workflows/20261013-guide-publication-01/verification.json)
addresses the existing root/candidate/hosted-preview mismatch without adding an
API or a new simulation. It changes 21 guide source files for preview dates,
candidate-source availability and the numerical-MCSE/data-sampling-SE distinction.
Runtime, dependencies, tests and examples are byte-identical to the ICC parent.
The 23-page manual passes 197 policy/example checks and 1,294 local fragment
links; the 105-file hosted check includes the previous preview's home/gallery
and the shared version stub. Previous preview files remain unchanged.

Native Chrome review verifies the landing-to-ICC route, working API search,
Wright and item-comparison response surfaces with external notes, and sensitivity
interval/ridge figures. The initially blank page later rendered; no cause is
established. The review also detected the stale no-MCSE claim, corrected before
closure in a second documentation-only deployment. Both automatic Pages runs
succeeded, without cancellation or manual workflow dispatch. No numerical
checks or estimation were repeated for that correction.

The final publication is a development preview, not a source merge, package
release, independent reader review or scientific acceptance. Remote main and
the 526 frozen MS3 files remain unchanged. The resource/evidence receipts retain
the sandbox resource-observation refusal and the successful monitored build;
neither is an estimation failure. There are zero new fits and zero independent
scientific replications.

## 16. Installable source and saved-result replay (2026-10-13)

The [installable-preview receipt](../../results/workflows/20261013-installable-preview-01/verification.json)
addresses the existing public-workflow distribution gap. It reuses the preceding
candidate's numerical evidence and two saved short fits; no estimator is rerun.
The user explicitly approved publishing the 867-file source, including internal
design/validation documents, to the new development branch. Local results and
artifacts, Git metadata and the ignored development Manifest are excluded.
Six documentation files change from the sealed guide parent; implementation,
tests, examples and dependency declarations are preserved. The tracked
minimum-Julia Manifest remains part of the source.

The final public commit installs into a new analysis project with cached
dependencies and offline resolution. All installed source files match; the
working-directory-independent ICC example and two portable JSON report reloads
pass seven checks. This is a public Git retrieval test, not a cold-depot or
online-registry resolution test. Under the complete original dependency graph,
the installed package's public saved-result example passes 23 checks using two
existing native caches; a fresh process passes ten more. Both short-fit warnings
remain `insufficient_draws`. Native replay used the earlier commit whose only
subsequent changes were README and cache-compatibility explanations.

The fresh dependency environment initially rejected a native cache. Read-only
diagnosis found 85 recomputed diagnostic values differing by one ULP, with maximum
absolute difference 4.440892098500626e-16; other artifact values matched. Restoring
all 179 non-package dependency entries resolved it without weakening validation
or changing data/draws. The specific causal dependency was not isolated. A package
pin alone is insufficient for native-cache preservation: retain the original
Julia version and complete Project/Manifest. Portable JSON reports provide the
checked route for sharing already computed results between these environments.

One automatic Pages deployment publishes the updated guide. The build passes 197
policy/example checks, 23 pages and 1,298 local fragment links; 105 hosted files
match their prepared artifacts. Native Chrome confirms the landing install code,
its exact-commit source link and the manual installation section. The previous
preview is retained, with no source-branch CI or manual workflow dispatch.

The receipt retains preparation-script errors separately from this compatibility
finding: example world age inside a closure, a scalar comparator misuse, and a
global-name collision after successful environment restoration. Each continuation
resumed after completed setup rather than repeating installation or inference.
No full suite, platform sweep, scientific replication, main merge, release or
independent acceptance is claimed. The approved source publication and matching
guide close this bounded distribution task; MS4–MS6 keep their existing criteria.

## 17. Five or more facets and reader navigation (2026-10-13)

**Question and place in the roadmap.** Can a reusable package distinguish more
than person/item/rater without confusing extra facet levels, latent dimensions
and metadata? This extends the existing applied-composition contract, not MS3's
frozen target and not a reason to launch a large simulation before a matching
fitter exists. The [current checklist](../../ROADMAP.md#current-completion-checklist)
keeps integrated workflow acceptance ahead of a new general model catalogue.

### First structural question and completed checks

The bounded first fixture has five roles: person, physical task, rater, criterion
and occasion. Its adjacent category logit is

`log(P(Y=k)/P(Y=k-1)) = theta[p] - task[t] - severity[r] - criterion[c] - occasion[o] - step[c,k]`.

This is a **proposed fixed-unit-slope, D1 additive PCM fixture**, not an existing
public fitted model or the complete MGMFRM extension. It uses three categories,
criterion-owned centered steps, zero-sum task/rater/criterion/occasion locations
and freely represented person locations. Scale is fixed by unit logits and
unit coefficients. Person ability is constant across occasions: no growth,
drift, interaction, covariance, shared-response random effect or mixed category
scale is modeled. In a later multidimensional model, criterion roles in Q and
dimension-specific location constraints must be defined again; a criterion is
not automatically both a new dimension and an independently free location.

The [small fixture](../../results/workflows/20261013-guide-facet-audit-01/facet_audit.py)
reuses the existing four-facet design builder, contrasts and rational rank
calculation. It declares all levels before subsetting: 4 persons, 3 tasks,
3 raters, 2 criteria and 2 occasions. The optional sixth role is a two-level
administration mode with another zero-sum additive effect. Each rating supplies
two adjacent-logit design rows; these rows are structural probability equations,
not two independent observations.

| Allocation | Ratings | Columns / exact rank | What it establishes |
| --- | ---: | ---: | --- |
| Five-facet complete cross | 144 | 12 / 12 | No remaining location/step null direction under these constraints |
| Linked half of that cross | 72 | 12 / 12 | This smaller allocation preserves structural identification |
| Each task assigned to only one occasion | 72 | 12 / 11 | Same rating count, but task and occasion cannot be separated |
| A training fold omitting one declared occasion | 72 | 12 / 11 | Full-data identification need not survive a split |
| Six-facet complete cross | 288 | 13 / 13 | One additional additive mode can be separated in this fixture |
| Mode determined by task | 144 | 13 / 12 | More declared facets alone do not produce more identifiable effects |

All six cases preserve rank under row reversal and occasion relabeling. An
explicit null direction for the confounded task/occasion case leaves the entire
category probability vector unchanged to 1.12e-16, while the same parameter
change alters probabilities in the complete cross. The
[saved result](../../results/workflows/20261013-guide-facet-audit-01/facet-audit.json)
records about 0.17 seconds for the in-process audit and **zero posterior fits**.
No random datasets were generated. These finite structural checks do not
establish information strength, practical estimability, prior validity, recovery,
coverage, SBC, independence of repeated ratings or public API support.

### Remaining extension gates

- [x] State facet roles, unit scale, threshold owner and constraints; exhibit
  linked/confounded/missing-level counterexamples without sampling.
- [ ] Select the applied estimands and existing/new-person, task, rater, occasion
  and response prediction contracts. Distinguish systematic occasion shifts
  from growth and drift; retain grouping IDs when splitting dependent ratings.
- [ ] Define a proper joint prior and explicit additive/shared/interaction
  effects. Inspect prior-predictive categories; avoid adding unrestricted
  task-by-criterion item effects and separate task difficulty without constraints.
- [ ] Connect a matching generator, Julia target and independent Stan equation
  implementation. Check density/gradients, transforms/Jacobians, identity,
  likelihood invariances, relabeling and refusal of unsupported configurations.
- [ ] Run a small, prospectively specified workflow pilot contrasting linked
  and weak/confounded allocations at comparable rating cost. Check diagnostics,
  focal MCSE, prior sensitivity, runtime/memory/output and save/reload. A proper
  prior regularizing a likelihood ridge must not be called data identification.
- [ ] Decide whether a larger study could change a specified collection/design
  or method recommendation. If so, prespecify independent replication and
  useful precision for bias, RMSE, coverage and availability, retain all failures
  and justify cost. Fixed-truth recovery, prior SBC and design assurance are
  separate studies; five-facet support is not a claim of arbitrary-facet support.

### Beginner navigation and the boundary of its evidence

The English guide already had a motivating example, worked probabilities,
model-specific theory, executable examples and Julia REPL help. The gap was
discoverability: readers had to know the chapter/function name, computation was
behind lengthy plotting sections, and extra columns could be mistaken for extra
estimated effects. The isolated documentation successor changes existing pages:
home/README task routes; early model–prior–sampler explanation; API-to-theory/help
links; and the facet/level/dimension distinction with the public fitting limit.
It also corrects the local mean-profile manual's implication that installing
the published branch supplies the unpublished mean-profile increment.

Acceptance uses the existing MS6 unfamiliar-user task, with these observable
additions: start from the homepage, find installation and a no-fit example,
locate a calculation and experimental function help without private paths,
explain five raters versus five facets versus five dimensions, identify the
sampler actually requested, and interpret a warning-bearing saved report. Record
where the reader gets stuck and repair that explanation or route. Do not use
page/test counts as proof of comprehension. Actual unfamiliar-user review is
still unassigned; implementer build/link checks cannot close it.

The [final documentation receipt](../../results/workflows/20261013-guide-facet-audit-01/verification.json)
records 197 language/example assertions, 23 built pages and 1,337 valid local
fragment links, including the new task, computation and facet routes. The first
build rendered successfully but two newly introduced developer-oriented phrases
failed the language check; the source was corrected without weakening the rule.
Both logs remain. Guarded builds total 103.4 seconds, including that failed
language stage, with peak observed owned-process RSS about 1.12 GiB. Existing
missing maintainer-docstring and search-index-size warnings remain recorded.
No numerical package tests or MCMC were repeated. The 526 MS3 files, published
867-file source and sealed 870-file parent are unchanged. This successor changes
documentation only, with identical runtime, tests, examples and dependency
versions; no hosted update, new browser review or independent reader acceptance
is claimed.
