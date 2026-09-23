---
name: setup
description: 現在のディレクトリのリポジトリをSiriusへ登録する、またはグローバル設定を作る。~/.sirius/config.yamlと~/.sirius/repos/<owner>__<repo>.yamlを対話的に書き、オペレーターにしかできない作業（権限、レビュー用アカウント、ルールセット、スケジューラ）のチェックリストを表示する。/sirius:setupに使う。
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
   - `merge.mode`: `manual` は人がreadyなPRのタイトル先頭に `[merge]` を付け、その後Siriusがマージすることを意味する。`auto` は、レビュー用アカウントの判定、承認、CI、baseブランチの条件がすべて揃ったときにSiriusがマージすることを意味する。
   - `reply.mode`: `draft` はSiriusが送信せず提案文をIssue/レポートに書くだけ。`send` はSiriusが実際に返信する。LINEには送信の仕組みがないので、`reply.mode: send` を選んでもLINE向けの返信は当面Issue/レポートへの記載にとどまる。
   - `merge` の下の各種ルール: `ci_required`、`approvals`（レビュー用アカウントに加えて必要な人の承認数）、`human_branches`（ブランチ→理由、`*` は全ブランチ）、`deploys`（ブランチ→そのマージが何をデプロイするか）、`deploy_workflows`（ブランチ→デプロイを行うActionsワークフロー名）。
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

1. レビュー専用の別GitHubアカウント（マシンユーザー）を作り、対象リポジトリへの書き込み権限を与える。エージェントが使うアカウントと同じであってはならない。
2. 専用の gh 設定ディレクトリでログインする:
   ```bash
   GH_CONFIG_DIR=~/.sirius/identities/reviewer gh auth login
   ```
3. `config.yaml` に追加する:
   ```yaml
   identities:
     reviewer: {login: <account>, gh_config_dir: ~/.sirius/identities/reviewer}
   ```
4. 各リポジトリのデフォルトブランチに、承認1件を必須とし、pushで古い承認を無効化し、最新のpushへの承認を必須とするルールセットを追加する。これが無いと、ゲートはSirius自身のツールだけで守られることになる。正確な `gh api` コマンドか設定ページのURLを示す。

1〜3が済むまで、`sirius-config` はそれらのリポジトリを `manual` として報告する。

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
