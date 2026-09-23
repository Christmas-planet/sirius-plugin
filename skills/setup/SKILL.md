---
name: setup
description: 現在のディレクトリのリポジトリをSiriusへ登録する、またはグローバル設定を作る。~/.sirius/config.yamlと~/.sirius/repos/<owner>__<repo>.yamlを対話的に書き、オペレーターにしかできない作業（権限、スケジューラ）のチェックリストを表示する。merge: autoは別GitHubアカウントを使わず、実装役とは別モデルの独立検証をゲートにする。/sirius:setupに使う。
disable-model-invocation: true
---

# Sirius setup

セットアップは対話的に行う。`~/.sirius/config.yaml` や `~/.sirius/repos/` への書き込みはすべてWriteかEditツールを通し、guard hookがユーザーに承認を求める。これらのファイルをシェルから書かない。プロジェクトのリポジトリの中には何も書かない。

## 1. グローバル設定（初回だけ）

`~/.sirius/config.yaml` が無ければ、AskUserQuestionで尋ねる:

- **implementer** と **reviewer**: `claude` か `codex`。`merge.mode: auto` を機能させるには両者が異なっている必要がある。implementerに `claude`、reviewerに `codex` を勧める。
- **上限**: どのリポジトリでも使ってよい最も緩い `implement_gate`（`human` か `auto`）、`merge`（`manual` か `auto`）、`reply.mode`（`draft` か `send`）。個々のリポジトリはこれより厳しくできるが、緩くはできない。
- **scheduler**: `none`（手で `/sirius:run` を実行する）、`loop`（開いているセッションで `/loop 10m /sirius:run`）、`launchd`（このMacでバックグラウンドからN分ごと）。1つのマシンにつきスケジューラは1つにし、同じキューにクラウドのルーチンを重ねない: リースは機械単位。

[テンプレート](../../templates/config.yaml)から書く。

## 2. このリポジトリを登録する

1. 現在のディレクトリで `git remote get-url origin` を読む。`owner/repo` に変換し、`gh repo view` で確認する。
2. `sirius-config repo <owner/repo>` を実行する。すでに設定ファイルがあれば、それを見せて編集を提案する。新規に作る代わりに。1つのリポジトリにつき設定ファイルは1つだけ。
3. ソースとゲートを尋ねる:
   - Slack: 正確なワークスペースID（`T…`）とチャンネルID（`C…`）。Slackコネクタが使えるときは、ユーザーが選べるようチャンネル一覧を出す。名前やワイルドカードは対象にならない。
   - LINE: アプリに表示されている通りの正確なチャット名（このMacだけ）。
   - `implement.gate`: `human` は人がIssueタイトルの先頭に `[implement]` を付けてからSiriusが実装することを意味する。`auto` は、受入条件がはっきりしているIssueにSirius自身が作成時から接頭辞を付けることを意味する。
   - `merge.mode`: `manual` は人がreadyなPRのタイトル先頭に `[merge]` を付け、その後Siriusがマージすることを意味する。`auto` は、実装役とは別モデルによる独立検証の判定（PASS）、CI、baseブランチの条件がすべて揃ったときにSiriusがマージすることを意味する。承認は同一GitHubアカウントで行い、別のレビュー用アカウントは使わない。
   - `reply.mode`: `draft` はSiriusが送信せず提案文をIssue/レポートに書くだけ。`send` はSiriusが実際に返信する（Slackは `slack_send_message`、LINEはComputer Useでのアプリ操作）。返信は、オペレーター本人がその会話で過去に送った文面に合わせた自然な日本語で書く。`reply.style` に文体Skill名（例: `write-like-kazuki`）か自由記述の指示を、`reply.never` に絶対に言わないことを書ける。
   - `merge` の下の各種ルール: `ci_required`、`approvals`（独立検証の判定に加えて必要な人の承認数）、`human_branches`（ブランチ→理由、`*` は全ブランチ）、`deploys`（ブランチ→そのマージが何をデプロイするか）、`deploy_workflows`（ブランチ→デプロイを行うActionsワークフロー名）。
   - `investigate` / `review` / `verify` / `forbidden`: どこまで埋めるかはユーザーに委ねる。分からない・決めていないものは空のままにしてよいと伝える。
4. [テンプレート](../../templates/repo.yaml)から `~/.sirius/repos/<owner>__<repo>.yaml`（`owner/repo` を小文字化し `/` を `__` に置き換えたファイル名）を書き、`dir` を現在のディレクトリに設定する。
5. `sirius-config validate` を実行し、`downgrades` を含めて実効結果を見せる。

旧Siriusから移行したリポジトリのファイルには `needs_review: true` が付いている。これは、ユーザーがファイルを確認してこのフラグを外すまで、`human` / `manual` / `draft` に留める。ファイルを一緒に見ながら確認する。自分の判断でフラグを外さない。

Siriusはラベルを作らない。状態はタイトル接頭辞の `[implement]` / `[merge]`、Issueのmarkerコメント、PRのdraft/ready状態にある。

## 3. オペレーターのチェックリスト

該当する手順を、正確なコマンド付きのチェックリストとして表示する。エージェント自身はこれらを行わない: guard hookがルールセットの変更を拒否し、自動モードは設定ファイルへの書き込みを拒否する。

**常に**

- `~/.claude/settings.json` の `permissions.deny` に追加: `Bash(gh pr merge:*)`、`Bash(git push --force:*)`、`Bash(git push -f:*)`。プラグインはこれらの権限ルールを同梱できず、guard hookはあくまで補助。
- 自動モードを使うなら、対象範囲のすべてのリポジトリを自動モードの `environment` に列挙する。さもないと、分類器が知らないリポジトリで正当な作業を拒否することがある。

**いずれかのリポジトリが `merge.mode: auto` を使うとき**

別のレビュー用GitHubアカウントは使わない運用（セルフマージ）を選んでいる。ゲートは `sirius-merge` 自身の検証だけにある: 実装役とは別モデル（`implementer`/`reviewer`、またはリポジトリの `review.reviewer`）による独立検証がPASSした判定コメントが、今のheadと今のbase先端に対して揃っていることを確かめてからマージする。GitHub側の承認必須ルールセットは設定しない（設定していても、同一アカウントは自分のPRをApproveできずGitHub APIに拒否されるため、Approve自体は行わない）。

- `config.yaml` の `implementer` と `reviewer`（またはリポジトリの `review.reviewer`）が異なるモデルになっていることを確認する。`sirius-config` はここが同じだと自動的に `manual` へ降格する。
- 検証レーンをすり抜けられると困る変更（本番公開、支払い、認証情報など）は、リポジトリの `forbidden` に書いておく。レビュワーがこれに触れる変更を見つけたら `human_only` として扱い、`sirius-merge verdict` はその判定をマージに使わせない。

**スケジューラ `launchd`**

`bin/sirius-tick` を `~/.sirius/bin/sirius-tick` にコピーし、ジョブがバージョン管理されたプラグインキャッシュを指さないようにする。次に、選んだ間隔で[テンプレート](../../templates/launchd.plist)からplistを生成し、次のコマンドをユーザーに渡す:

```bash
cp <plist> ~/Library/LaunchAgents/ai.sirius.tick.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.sirius.tick.plist
```

tickは `~/.sirius` から `claude -p "/sirius:run"` を実行するので、プラグインはユーザースコープで有効になっている必要がある（`/plugin install sirius@sirius --scope user`）。プロジェクト設定だけで有効にしていると、スケジュール実行から `/sirius:run` が見えない。tickは `ANTHROPIC_BASE_URL` とモデル上書き用の環境変数を取り除き、`--model opus --effort high` で実行する（`SIRIUS_MODEL` / `SIRIUS_EFFORT` で上書き、`SIRIUS_TICK_KEEP_ENV=1` で環境をそのまま保持）。

ジョブは `KeepAlive` なしの `StartInterval` を使うので、クラッシュが再起動ループを招かない。止めるには: `launchctl bootout gui/$(id -u)/ai.sirius.tick`。

## 4. 仕上げ

そのリポジトリの `sirius-config show` と、残りのチェックリストを表示する。次に `/sirius:status` を提案する。
