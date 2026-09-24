---
name: run
description: Siriusの1サイクルを実行する - readyなPRのマージ、保留中の確認の再開、設定されたSlack/LINEソースの取り込みからGitHub Issueへの変換、対応可能なIssueの実装を、~/.sirius内のリポジトリごとの設定に従って行う。/sirius:run、そのloop実行、スケジュール実行に使う。
---

# Sirius run

1回分の範囲を決めて動かす。実際の作業は構成スキル（`merge`、`intake-slack`、`intake-line`、`create-issue`、`implement`）が行う。プラグインの `bin/` はプラグイン有効時にPATHへ入っているので、`sirius-config`、`sirius-lease`、`sirius-merge` は名前で呼べる。

## 1. 設定を読み込み、凍結する

1. `~/.sirius/STOP` があれば `stopped` を報告し、`SIRIUS_STATUS: ok` で終える。他は何もしない。
2. `sirius-config show` を実行する。`ok` が false なら外部への書き込みは一切せず、エラーを報告して `SIRIUS_STATUS: blocked` で終える。
3. そのJSONを、この実行における凍結済みの表として保持する: 各リポジトリ、正確なソース、実効的な `implement.gate` / `merge.mode` / `reply.mode`、フォールバックの理由を示す `downgrades`。加えて各workspace（`workspaces`）: メンバーのリポジトリ、そのworkspaceが持つソース、実効的な `reply.mode`。これを台帳にハッシュとして残す。
4. これらのリポジトリ、workspace、ソースだけが対象。カレントディレクトリのリモート、アクセスできるすべてのリポジトリ、見えるすべての会話へフォールバックしない。設定はどのプロジェクトリポジトリの中にも置かれないので、PRが何かを変えてもゲートは緩まない。
5. 実行中は `~/.sirius/config.yaml` も `~/.sirius/repos/*.yaml` も `~/.sirius/workspaces/*.yaml` も変更できない。guard hookはこうした変更に人の承認を求めるので、無人の実行では誰も承認できない。設定がおかしいと感じたら、そのままレポートに書く。

## 2. リースを取る

凍結済み表にある各リポジトリについて、`sirius-lease acquire <run-id> --scope repo:<owner/repo>` を今すぐ取る。取れたリポジトリは、このフェーズ4（マージ・取り込み・実装のすべて）を通して保持し、フェーズ5の整合が終わってから解放する。すでに他の実行が持っているリポジトリは、この実行の対象から丸ごと外す（マージも取り込みも実装もしない）。レポートに `busy` として載せ、フェーズ5には進めない。全体を1本でロックする機械単位のリースはもう使わない: これにより、別々のリポジトリの作業が、別々の `/sirius:run` 呼び出しの間で本当に並行して進められる。同じリポジトリに対する取り込み（チェックポイントの読み書きとIssue作成）を2つの実行が同時に行うことも、このリースが防ぐ。workspaceが持つソースの取り込みは、そのworkspaceのメンバー全員の `repo:` リースを取れたときだけ行う。1つでも取れなければ、そのworkspaceの取り込みだけを今回スキップして `busy` と報告する（取れたメンバーのマージ・実装は続ける）。

LINE取り込みだけは追加で別扱いにする。ネイティブmacOS LINEアプリを操作するComputer Useセッションは機械に1つしかないので、`intake-line` を呼ぶ前に `sirius-lease acquire <run-id> --scope line` を取り、そのフェーズが終わったら解放する。他の実行がすでに `line` スコープを持っていたら、この実行のLINE取り込みだけをスキップし、（`repo:<owner/repo>` を取れている）他のリポジトリのSlack取り込みやマージ・実装は続ける。

保持している各リースについて、フェーズごとに `sirius-lease heartbeat <run-id> --scope <same-scope>` を実行する。台帳は `~/.sirius/runs/<run-id>.json` に保つ: ID、ハッシュ、範囲、カーソル、URL、件数、時刻だけ。メッセージ本文、秘密情報、リポジトリの内容は絶対に保存しない。秘密情報はツール出力にも出さない: `.env` などの中身を確かめるときはキー名だけを表示し（`cut -d= -f1`）、sedやgrepの正規表現で値をマスクして表示しない。引用符付きや複数行の値はパターンから漏れ、そのまま出力される。出てしまったら、その値は漏えいしたものとして扱い、再発行を運用者に報告する。

リースは機械単位。同じキューに対して使えるスケジューラ（`config.yaml` の `scheduler`）は1つだけ。

## 3. 事前確認（読み取り専用）

- `gh auth status` が通り、対象範囲のすべてのリポジトリにpush権限で到達できる。
- 設定された `implementer` と `reviewer`（リポジトリごとの `review.reviewer` を含む）が使える（どちらかが `codex` なら `codex --version`）。
- 対象範囲の各ソース種別について、そのツールが使える: Slackには読み取り用のコネクタ（Slackの `reply.mode: send` があるなら、送信用にClaude in Chromeも）、LINEにはComputer UseとLINEアプリ。Claude in Chromeが使えなければ、Slackの返信だけを `draft` として扱う。ソースツールが無ければ、そのソースだけを無効化する。
- `merge.mode: auto` のリポジトリでは、1件のreadyなPRに対する `sirius-merge check` が判定を評価できることを確認する。できなければ、この実行ではそのリポジトリを `manual` として扱い、理由を報告する。

最初の外部書き込みの前に、計画を台帳へ書く。オブジェクトを変更する直前に必ず取り直す。

## 4. フェーズ

ここから先は、フェーズ2で `repo:<owner/repo>` のリースを取れたリポジトリだけを対象にする。取れなかったリポジトリは、マージ・取り込み・実装のどれも行わない。

1. **マージ。** readyなPRと `[merge]` が付いたPRについて `merge` スキルを実行する。終わったら、影響を受けたbaseブランチを更新する。
2. **保留中の確認。** `awaiting_confirmation` にある各ソースのチェックポイントについて、保存された質問を実行レポートに載せ、そのソースの取り込みはスキップする。この会話でユーザーが答えていれば、取り込み契約の通りに再開する。
3. **取り込み。** 対象範囲の一時停止していないソースについて、`intake-slack` と `intake-line` を並行して実行する。LINEは `line` スコープのリースを取れたときだけ実行する。それぞれに、ソースとその持ち主（リポジトリならそのリポジトリ自身、workspaceならworkspaceとメンバー全員の解決済み設定）、凍結したカットオフ、新規Issue上限だけを渡す。すべてのIssueは `create-issue` を経由する。
4. **実装。** 凍結済み表、実行ID、`limits.concurrent_workers`、残り時間、取り込みが返した `pr_task`（既存PRへの対応）と依頼元の参照を渡して `implement` スキルを実行する。`implementer: pstack` なら、調査・実装・検証・本番以外へのデプロイ・レビュー対応はpstackのpoteto-agentが行い、Siriusはゲート、記録、依頼元への報告だけを持つ。
5. **整合。** 変更したすべてのIssueとPRを取り直す。チェックポイントと台帳を保存する。状態の保存が終わってから、取ったリースをすべて `sirius-lease release <run-id> --scope <same-scope>` で解放する（`repo:<owner/repo>` を各リポジトリごとに、取っていれば `line` も）。

安全なチェックポイントに届かないほど残り時間が少なくなったら、新しい作業を始めない。余った作業は状態を変えないままキューに残す。

## 5. レポート

リポジトリごと（workspaceのソースはworkspaceごと、振り分け先のリポジトリも添えて）に: 読んだソースとそのカットオフ、作成または重複と分かったIssue、ユーザーの回答待ちの確認、着手・再開・ブロックされたIssue、draft・ready・マージ済みのPR、人が `[implement]` を付けるのを待っているIssue、人が `[merge]` を付けるのを待っているPR、レビューのパス、チェック、リトライ、設定のdowngrade。リース待ち（`busy`）で今回スキップしたリポジトリやLINEも明記する。設定のハッシュ、カットオフ、所要時間、リースを解放できたかを含める。ページ送り、チェックポイント、整合のいずれかが未完了なら、実行を完了扱いにしない。

最後に必ずこの1行で終える:

```
SIRIUS_STATUS: ok | blocked | busy | failed
```

確認、手動マージ、セットアップの不足、設定エラーなど、何かユーザー待ちのときは `blocked` を使う。スケジューラは `blocked` と `failed` でユーザーに通知する。
