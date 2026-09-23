# Sirius

Slack や LINE で来た依頼を GitHub Issue にし、別のモデルのレビューを通した PR にして、リポジトリごとの設定に従ってマージまで進める Claude Code プラグインです。

```
Slack / LINE ─▶ Issue ─▶ 実装（ドラフト PR）─▶ 独立レビュー ─▶ ready PR ─▶ マージ
                         ▲ implement.gate                                 ▲ merge.mode
```

## インストール

```text
/plugin marketplace add Christmas-planet/sirius-plugin
/plugin install sirius@sirius
```

リポジトリのディレクトリで次を実行します。

```text
/sirius:setup
```

## コマンド

| コマンド | 役割 |
|---|---|
| `/sirius:setup` | 全体設定と、このディレクトリのリポジトリを登録する。あなたにしかできない作業のチェックリストも出す |
| `/sirius:run` | 1サイクル実行する（マージ → 確認待ちの再開 → Slack/LINE の取り込み → 実装） |
| `/sirius:status` | 読み取り専用で状況を表示する。あなた待ちのものを最後にまとめる |
| `/sirius:stop` | 直ちに止める（`~/.sirius/STOP` を作る）。`/sirius:stop resume` で再開 |

## 設定はすべて `~/.sirius/` にある

```
~/.sirius/
  config.yaml                       全体: 実装役とレビュー役、上限、スケジューラ、レビュー用アカウント
  repos/<owner>__<repo>.yaml        リポジトリごと: dir、sources、reply、investigate、
                                     implement、review、verify、merge、forbidden
  state/ runs/ locks/                実行状態
  STOP                               あれば全停止
```

設定の単位は「プロジェクト」ではなくリポジトリ1つです。調査の仕方、レビューの仕方、検証の仕方はリポジトリごとに決まるものであり、抽象的な「プロジェクト」単位では決まらないためです。1ファイルにつきリポジトリは1つで、ファイル名は `owner/repo` を小文字化して `/` を `__` に置き換えたもの（例: `acme/my-repo` → `acme__my-repo.yaml`）になります。

対象リポジトリ（`.claude/` を含む）には何も置きません。これは次の2つの理由からです。

- `.claude/` 配下を自由に編集できないチームでも使えるようにするため。
- エージェントが自分の PR で自分のゲートを緩める経路を作らないため。

ひな形は [templates/](templates/) にあります。

### 3つのゲート

| 設定 | 値 | 意味 |
|---|---|---|
| `implement.gate` | `human` | 人が Issue のタイトル先頭に `[implement]` を付けたら実装する |
| | `auto` | 受入条件がはっきりした Issue なら、Sirius が作るときに `[implement]` を付けて実装する |
| `merge.mode` | `manual` | PR を ready にして知らせる。人がタイトル先頭に `[merge]` を付けたら Sirius がマージする |
| | `auto` | 下の条件がすべてそろったら、Sirius が `[merge]` を付けてマージする |
| `reply.mode` | `draft` | 送信せず、提案する返信文を Issue やレポートに書くだけ |
| | `send` | 会話に合わせた自然な返信を実際に送る（Slackは `slack_send_message`、LINEはComputer Use）。書き方は `references/reply-contract.md` と `reply.style` |

ラベルは使いません。状態は、タイトル先頭の `[implement]` / `[merge]`、Issue の目印コメント（`working` / `waiting` / `blocked` / `ready`）、PR が draft か ready かで表します。`[merge]` を付けた後に新しいコミットが入った PR はマージしないので、見直してから付け直してください。

全体の `config.yaml` の値が上限です。リポジトリ側で緩くすることはできません（`reply.mode` も含めて3つとも同じ仕組みです）。条件が足りないときは、`sirius-config` が自動でより厳しい側に落とし、その理由を `downgrades` に表示します。

### `merge.mode: auto` の条件

- 実装とレビューが別のモデルであること（`implementer` と `reviewer`。リポジトリの `review.reviewer` があればそちらを優先）
- 今の head・今の base 先端に対する独立検証の判定コメントが PASS（または `human_only` でない PASS+NOTES）であり、検証したモデルが実装したモデルと重ならないこと
- head が base の先端に載っていて、衝突がないこと
- CI がすべて成功していること
- 人が押すべきブランチ、パスに当たらないこと
- `STOP` がないこと

承認は別のレビュー用 GitHub アカウントでは行いません（セルフマージ）。GitHub の承認必須ルールセットも前提にしていないので、リポジトリ側で設定は不要です。「本当に別のモデルが検証した」ことは、`sirius-merge verdict` が判定コメントの `verifier_models` と実装コミットの `author_models`（`Co-Authored-By` トレイラーから読む）を突き合わせることで確かめますが、これは同じ権限で動くプロセスの自己申告です。手順を守らないエージェントが虚偽の検証結果を渡す可能性を GitHub 側の仕組みで止める層は無いので、失うと困るリポジトリでの `merge.mode: auto` は慎重に検討してください。

## 安全の層

1. **独立検証の判定**（本命）: 実装役とは別モデルが4レーン（gates/live/audit/regression）で検証し、PASS の判定コメントが今の head・base に対して揃っていなければマージしない。
2. **`sirius-merge`**: マージの唯一の入口。条件をすべて確かめ直してからマージする。
3. **guard hook**（補助）: `gh pr merge`、`--admin`、force-push を止める。ゲートが `auto` でないリポジトリでは、エージェントによる `[implement]` / `[merge]` の付与も止める。設定ファイルの変更には人の承認を求める。hook はタイムアウトすると止まらないので、これだけには頼らない。

プラグインは `permissions.deny` を同梱できないため、`/sirius:setup` が追加すべき設定を提示します。

## 並行実行とリース

`~/.sirius/locks/` の下に、スコープごとに独立したロックファイルを持ちます。独立したリポジトリの作業（マージ・実装）は、`--scope repo:<owner/repo>` のリースを取って並行に進められます。LINE の取り込みだけは、ネイティブ macOS LINE アプリを操作する Computer Use セッションが機械に1つしかないため、`--scope line` の専用リースで機械全体を通して直列化します。マシン全体を1本でロックする「実行全体のリース」はもうありません。

ロックはマシン単位です。同じキューをクラウドのルーチンと併用しないでください。

## 定期実行

`config.yaml` の `scheduler` で1つだけ選びます。

- `loop`: 開いているセッションで `/loop 10m /sirius:run`
- `launchd`: `/sirius:setup` が `~/.sirius/bin/sirius-tick` と plist を用意する。`StartInterval` で起動し、`KeepAlive` は使わない。`blocked` や `failed` で終わると macOS の通知が届く。

## 旧 Sirius からの移行

さらに古い Sirius（Markdown 台帳）からの一回限りの移行:

```bash
scripts/migrate-legacy          # 変換結果を表示するだけ
scripts/migrate-legacy --write  # 当時の ~/.sirius/projects/*.yaml と config.yaml を作る
```

v0.2（`projects/<name>.yaml`、1プロジェクトに複数リポジトリ）から現行の v0.3（`repos/<owner>__<repo>.yaml`、1ファイル1リポジトリ）への一回限りの移行:

```bash
scripts/migrate-projects-to-repos          # 変換結果を表示するだけ
scripts/migrate-projects-to-repos --write  # ~/.sirius/repos/<owner>__<repo>.yaml を作る
```

どちらの移行でも、生成したファイルには `needs_review: true` が付き、確認が済むまでは `human` / `manual` / `draft` で動きます。

## 開発

```bash
claude --plugin-dir .
tests/run.sh
```
