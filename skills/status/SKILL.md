---
name: status
description: Siriusの状態を読み取り専用で表示する - リポジトリごとの実効設定とdowngrade、リース状況、ソースのチェックポイントと保留中の質問、キュー中/進行中のIssue、レビューやマージ待ちのPR。/sirius:statusに使う。
---

# Sirius status

読み取り専用。どこにも書き込まない。

1. `sirius-config show`: リポジトリごとに、リポジトリ名、ソース、実効的な `implement.gate` / `merge.mode` / `reply.mode`、`downgrades` の理由をすべて表示する。設定エラーがあれば先に見せる。
2. 対象範囲にあるリポジトリごとの `sirius-lease status --scope repo:<owner/repo>`、`sirius-lease status --scope line`、そして `~/.sirius/STOP` の有無。機械全体を1本でロックする「run」スコープはもう無い。
3. `~/.sirius/state/intake/` 配下のチェックポイント: ソースごとの最終完了カットオフと、保留中の質問があれば一言一句そのまま。
4. リポジトリごとに `gh` で:
   - タイトルが `[implement]` で始まり、まだmarkerが付いていないIssue（キュー中）;
   - markerのphaseが `working`（ブランチ、PR、最終更新）、`waiting`、`blocked`（質問付き）のIssue;
   - `human` のリポジトリでSiriusが `[implement]` を付けずに作ったIssue: 「あなたが `[implement]` を付けるのを待っている」;
   - readyなPR: `manual` のリポジトリで `[merge]` が無ければ「あなたが `[merge]` を付けるのを待っている」、それ以外は `sirius-merge check` の結果。
5. `~/.sirius/runs/` と `~/.sirius/logs/tick/` の中で最も新しいファイル: 最後の実行がいつで、その `SIRIUS_STATUS` が何だったか。

現在のディレクトリが登録済みのリポジトリなら（`sirius-config repo --dir` で判定）、そのリポジトリを最初に詳しく見せ、他は1行ずつにする。

最後に、ユーザー待ちのものを緊急度の高い順にまとめる。
