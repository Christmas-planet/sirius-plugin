---
name: merge
description: 各リポジトリのmerge設定に従って、readyになったSiriusのPRを仕上げる - manualなリポジトリには通知し、autoなリポジトリでは独立検証の判定をPRに投稿してsirius-merge経由でだけマージする。Sirius runスキルから呼ばれるほか、1つのPR向けに単独でも使える。
---

# マージ

`sirius-merge`（プラグインの `bin/` にある）が、Siriusがマージする唯一の方法。合図はPRタイトル先頭の `[merge]` 接頭辞で、Siriusはラベルを使わない。guard hookが `gh pr merge` とマージAPIを拒否するが、hookはあくまで補助。本当のゲートは `sirius-merge` 自身の検証にある: 実装役とは別モデル（`implementer`/`reviewer`、またはリポジトリの `review.reviewer`）が検証したPASSの判定コメントと、そのモデルが実装したモデルと重ならないことの確認。GitHub側の承認必須ルールセットは前提にしない（承認アカウントを実装アカウントと分ける運用はしない。詳しくは[README](../../README.md)を参照）。

## 対象

凍結済みリポジトリ表にあるリポジトリの、オープンでdraftでないPRのうち、markerが `ready` になっているIssueをクローズするもの、および、タイトルが `[merge]` で始まるすべてのPR。各PRの実効的なmergeモードは `sirius-config repo <owner/repo>` で得る。

## `merge.mode: manual`

人がPRをレビューして、タイトル先頭に `[merge]` を付ける。自分では絶対に付けない。guard hookが拒否する。

- 人の承認（`approvals`）を数えるときは、GitHubの `reviewDecision: APPROVED` を信じない。承認後にheadやbaseが変わっても、ルールセット次第でAPPROVEDのまま残る。各レビューの `commit_id` が今のheadと一致し、baseも承認時から変わっていない承認だけを数える。変わっていたら、変わった差分の再確認を人に頼む（PRコメントか依頼元への報告で）。
- `[merge]` が無い間: PRのheadが変わっていない限り、そのheadについて1回だけ「あなた待ち」として実行レポートに載せる。headが変わるまで毎回報告し直さない。
- `[merge]` が付いたら: `sirius-merge merge <repo> <pr>` を実行する。これは、接頭辞が最新コミットより後に付けられたことを要求するので、人の合図の後に入った新しいコミットが見られないままマージされることはない。新しいコミットが入っていたら、人が見直して `[merge]` を付け直す必要があると報告する。接頭辞を自分で外さない。

## `merge.mode: auto`

PRごとに:

1. `sirius-merge check <repo> <pr>`（読み取り専用）。判定や承認の欠落以外の問題を報告したら、Siriusが持てる範囲を直し（baseへのrebase、CI待ちなど）、残りは報告する。
2. 今のheadに対するレビュー判定が無ければ、実装役ではなく設定された `reviewer`（そのリポジトリの `review.reviewer` があればそちらを優先する）で検証を実行する。`implementer: pstack` なら、この検証もpstackの `pstack:poteto-agent` にShipping playbookの手順1〜3（PRごとの独立した検証とその判定のpatch-id照合）だけを頼み、マージはさせない。検証モデルはコミットのCo-Authored-Byにあるモデルと重ならないものを指定する。4つのレーンを使う:
   - `gates`: リポジトリのチェックを再実行する;
   - `live`: 実画面やエンドポイントで変更を確認し、証跡ファイルを `~/.sirius/evidence/` に保存する。対象リポジトリの `verify.live` に確認方法が書かれていればそれに従い、`verify.not_enough` に挙がっている証跡だけでは不十分として扱う;
   - `audit`: 差分と証跡をIssueの受入条件と突き合わせる;
   - `regression`: baseブランチと比較する。

   さらに対象リポジトリの `verify.commands` があれば実行する。レーンのJSON（検証した `head_sha` と `base_sha`、`lanes`、`verifier_models`、`author_models`、`summary`、契約・金銭・支払い・認証・ストア提出に触れる変更や `forbidden` に触れる変更では `human_only` / `human_only_reason`）を書き、`sirius-merge verdict <repo> <pr> <lanes.json>` を実行する。これがPRに判定コメントを投稿する（GitHubのApprove操作は行わない。承認必須のルールセットを前提としないため）。
   判定は、検証したちょうどそのheadと、そのちょうどのbase先端に対してだけ有効。判定とマージの間にbaseへ何かがマージされたら、rebaseして検証し直す。base更新が多いときは、検証とマージを同じ実行の中で終える。
3. PRタイトルの先頭に `[merge]` を付けて（`gh pr edit <pr> -R <repo> --title "[merge] <title>"`）状態を可視化し、`sirius-merge merge <repo> <pr>` を実行する。これがすべてのチェックを2回実行し、両方が一致したときだけ `--match-head-commit` でsquashマージする。`deploys` に載っているブランチでは、`deploy_workflows` に書かれたワークフローを待ち、失敗したらrevert PRを開く。ワークフローが指定されていなければ、デプロイを未検証として報告し、ユーザーに手で確認するよう求める。
4. 検証済みのマージの後、GitHubがまだクローズしていなければ元のIssueをクローズし、マージのSHAをコメントする。

`sirius-merge` が拒否したら、その出力をそのまま報告する。回避策を取ったり、`--admin` を付けたり、ルールセットを変更したりしない。

## 停止スイッチ

`~/.sirius/STOP` があるとき、`sirius-merge` はすべてを拒否する。`/sirius:stop` がこのファイルを作る。
