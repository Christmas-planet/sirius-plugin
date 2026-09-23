# Sirius

Slack や LINE で来た依頼を GitHub Issue にし、別のモデルのレビューを通した PR にして、プロジェクトごとの設定に従ってマージまで進める Claude Code プラグインです。

```
Slack / LINE ─▶ Issue ─▶ 実装（ドラフト PR）─▶ 独立レビュー ─▶ ready PR ─▶ マージ
                         ▲ implement_gate                                  ▲ merge
```

## インストール

```text
/plugin marketplace add Christmas-planet/sirius-plugin
/plugin install sirius@sirius
```

プロジェクトのディレクトリで次を実行します。

```text
/sirius:setup
```

## コマンド

| コマンド | 役割 |
|---|---|
| `/sirius:setup` | 全体設定と、このディレクトリのプロジェクトを登録する。あなたにしかできない作業のチェックリストも出す |
| `/sirius:run` | 1サイクル実行する（マージ → 確認待ちの再開 → Slack/LINE の取り込み → 実装） |
| `/sirius:status` | 読み取り専用で状況を表示する。あなた待ちのものを最後にまとめる |
| `/sirius:stop` | 直ちに止める（`~/.sirius/STOP` を作る）。`/sirius:stop resume` で再開 |

## 設定はすべて `~/.sirius/` にある

```
~/.sirius/
  config.yaml            全体: 実装役とレビュー役、上限、スケジューラ、レビュー用アカウント
  projects/<name>.yaml   プロジェクトごと: dir、repos、sources、implement_gate、merge、merge_rules
  state/ runs/ locks/    実行状態
  STOP                   あれば全停止
```

プロジェクトのリポジトリ（`.claude/` を含む）には何も置きません。これは次の2つの理由からです。

- `.claude/` 配下を自由に編集できないチームでも使えるようにするため。
- エージェントが自分の PR で自分のゲートを緩める経路を作らないため。

ひな形は [templates/](templates/) にあります。

### 2つのゲート

| 設定 | 値 | 意味 |
|---|---|---|
| `implement_gate` | `human` | 人が Issue に `implement` ラベルを付けたら実装する |
| | `auto` | 受入条件がはっきりした `sirius` Issue なら実装する |
| `merge` | `manual` | PR を ready にして通知する。マージは人がする |
| | `auto` | 下の条件がすべてそろったら `sirius-merge` がマージする |

全体の `config.yaml` の値が上限です。プロジェクト側で緩くすることはできません。条件が足りないときは、`sirius-config` が自動で `manual` に落とし、その理由を `downgrades` に表示します。

### `merge: auto` の条件

- 実装とレビューが別のモデルであること（`implementer` と `reviewer`）
- レビュー専用の別 GitHub アカウント（`identities.reviewer`）が、今の head に対して判定を投稿し、Approve していること
- head が base の先端に載っていて、衝突がないこと
- CI がすべて成功していること
- 人が押すべきブランチ、ラベル、パスに当たらないこと
- `STOP` がないこと

加えて、リポジトリのルールセットで「今の push への承認1件」を必須にしてください。そうすれば、エージェントがこの仕組みを通らずにマージしようとしても GitHub が止めます。

## 既知の限界（v0.1）

レビュー用アカウントの資格情報は、エージェントと同じマシンの `~/.sirius/identities/reviewer` にあります。そのため、手順を守らないエージェントは `sirius-merge verdict` に虚偽の検証結果を渡し、レビュー用アカウントとして承認を投稿できてしまいます。

「別アカウントでなければ承認できない」ことは GitHub が保証します。しかし「本当に別のモデルが検証した」ことは、プロセスが同じ権限で動いている限り証明できません。

これを塞ぐには、レビューを GitHub Actions 側で実行し、レビュー用のトークンを Actions のシークレットにだけ置く必要があります。そうすれば、ローカルのエージェントはレビュー用の資格情報を持ちません。この構成は次の版の課題です。それまでは、失うと困るリポジトリで `merge: auto` を使わないでください。

## 安全の層

1. **GitHub のルールセットと別アカウント**（本命）: レビュー用アカウントの承認なしにはマージできない。
2. **`sirius-merge`**: マージの唯一の入口。条件をすべて確かめ直してからマージする。
3. **guard hook**（補助）: `gh pr merge`、`--admin`、force-push、エージェントによる `implement` の付与を止める。設定ファイルの変更には人の承認を求める。hook はタイムアウトすると止まらないので、これだけには頼らない。

プラグインは `permissions.deny` を同梱できないため、`/sirius:setup` が追加すべき設定を提示します。

## 定期実行

`config.yaml` の `scheduler` で1つだけ選びます。

- `loop`: 開いているセッションで `/loop 10m /sirius:run`
- `launchd`: `/sirius:setup` が `~/.sirius/bin/sirius-tick` と plist を用意する。`StartInterval` で起動し、`KeepAlive` は使わない。`blocked` や `failed` で終わると macOS の通知が届く。

ロックはマシン単位です。同じキューをクラウドのルーチンと併用しないでください。

## 旧 Sirius からの移行

```bash
scripts/migrate-legacy          # 変換結果を表示するだけ
scripts/migrate-legacy --write  # ~/.sirius/projects/*.yaml と config.yaml を作る
```

移行したファイルには `needs_review: true` が付き、確認が済むまでは `human` / `manual` で動きます。

## 開発

```bash
claude --plugin-dir .
tests/run.sh
```
