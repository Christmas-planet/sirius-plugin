---
name: implement
description: ~/.sirius/repos/*.yamlに列挙されたリポジトリで、対応可能なGitHub Issueを、各リポジトリの実装ゲートに従って実装し、独立レビューを通過したdraft→readyのPRとして仕上げる。Sirius runスキルから呼ばれる。
user-invocable: false
---

# Issueを実装する

実装キューを動かす。Siriusはラベルを使わない。GitHub上の3つの状態が永続的な情報源であり、どの遷移も観察・再開できる:

- Issueタイトルの `[implement]` 接頭辞: 実装してよいという合図;
- Issue上のmarkerコメント1つ `<!-- sirius-implement -->`。`phase` は `working`、`waiting`、`blocked`、`ready` のいずれか;
- 紐づくPR: 作業中はdraft、引き渡すときにready。

## 入力

`run` から: 凍結済みリポジトリ表（`sirius-config show` から）、実行ID、ワーカー上限、残り時間。この表にあるリポジトリを超えて範囲を広げない。

## 対象の条件

一覧にあるリポジトリの、タイトルが `[implement]` で始まるオープンIssue（PRではない）で、markerコメントが無いか、phaseが `working`（再開）だが `waiting`、`blocked`、`ready` ではないもの。

`[implement]` を誰が付けるかは、そのリポジトリの `implement.gate` によって決まる: `human` なら人が、`auto` なら `create-issue` が付ける。`human` のリポジトリでは自分では絶対に付けない。guard hookが拒否する。人が書いて接頭辞を付けたIssueは、どちらのモードでも対象になる。

すでにreadyなPRがひも付いているIssueはスキップする。

一覧にある各リポジトリで、`hasNextPage` が false になるまで全Issueをページ送りする。`gh search` は速い一次スキャンであって、網羅の証明ではない。

## 依存関係

`blockedBy`、親/子Issue、本文中の明示的な "depends on" / "blocked by" の行を集める。オープンなブロッカーは強い制約として扱う。推測された衝突（同じマイグレーション、スキーマ、生成ファイル）は、2つのIssueを同時に走らせない理由としてだけ扱う。実行できる層だけを、リポジトリを横断して古い順に、ワーカー上限内で走らせる。循環や曖昧な依存関係は、勝手に解決したと主張せず報告する。

## 着手

着手ごとに、Issueを取り直してから行う。まだ対象なら:

1. markerコメント `<!-- sirius-implement -->` を作成または更新し、phaseを `working`、実行ID、ブランチ、日時を書く;
2. コメントを取り直して、生きている実行の `working` phaseのmarkerが自分のものだけであること、競合するPRが現れていないことを確認する;
3. ブランチ `sirius/issue-<number>-<slug>` を使う。既存の一致するブランチやdraft PRが安全に復元できるなら再利用する。

phaseの最初に、すでにmarkerが付いているIssueを見る。ブランチかPRを再開する。着手が古くなっている（生きているワーカーがなく、リース期間内に進捗がなく、復元できるものがない）場合は、markerをphaseなしに戻して、一度だけ復元の記録を残す。最近進捗があった着手を横取りしない。

## 並列に作業する

ワーカーを起動する前に[worker-contract.md](references/worker-contract.md)を読む。各ワーカーには1つのIssueと専用のworktreeを与える。worktreeは `~/.sirius/worktrees/<repo>/<branch>` の下に、現在のリモートのデフォルトブランチから作る。ユーザー自身のチェックアウトを再利用したり、そのコミットされていない変更をコピーしたりしない。

実行できる層のワーカーは、すべて1バッチで起動する。設定された `implementer`（`claude` ならサブエージェント、`codex` ならworktree内の `codex exec`）を使う。ワーカーは実装・検証・push・draft PR作成を行う。レビュー、readyへの変更、タイトル変更、マージはしない。

ワーカーへ渡すときは、そのリポジトリの `investigate.read_first`、`investigate.knowledge`、`implement.conventions`、`forbidden`、`verify.commands`、`verify.live`、`verify.not_enough` を必ず添える。これらはworker-contractのプロンプトに差し込む値であり、省略しない。

## レビューと修正

レビューする前に[review-contract.md](references/review-contract.md)を読む。各ワーカーの結果について、そのworktreeの中で:

1. ローカルのheadがpush済みPRのheadと一致することを確認する;
2. 設定された `reviewer`（そのリポジトリの `review.reviewer` があればそちらを優先し、`review.focus` を渡す）で新しくレビューを実行する;
3. 実行可能な指摘はすべて実装役に返し、コミット・pushしてから、新しいレビュワーで再レビューする;
4. 最新の完了したレビューが実行可能な指摘なしと報告したときだけ止まる。

クラッシュした、タイムアウトした、部分的なレビューはクリーンとはみなさない。リトライ回数の上限はない。ユーザーの判断が要るブロッカーがあれば、PRをdraftのまま、phaseを `working` のままにし、markerコメントを更新して、次の実行に続きを任せる。

## チェックと引き渡し

クリーンなレビューの後、`gh pr checks` を確認する。失敗がブランチ由来なら、直してからレビューに戻る（差分が変わったため）。チェックが保留中なら、次の実行までPRをdraftのままにする。

レビューがクリーンで必須チェックが通ったら:

1. PRとIssueを取り直す;
2. `gh pr ready`;
3. markerのphaseを `ready` にし、PRのURL、レビュー済みheadのSHA、レビュワー、レビュー日時を書く;
4. 両方を取り直して、PRがreadyでmarkerが `ready` になっていることを確認する。

ここで `[merge]` をPRに付けない。readyになったPRはmergeスキルに渡り、そのリポジトリの `merge.mode` から判断する。

## 失敗

- ブランチやPRができる前: やり直せるセットアップの失敗ならmarkerのphaseを消し、一度だけ記録する。
- ブランチやPRができた後: phaseを `working` のままにして次の実行で再開する。
- 外部の誰かを待っている: phaseを `waiting` にし、何を待っているか書く。人がphaseの行かmarker自体を削除して解除する。
- ユーザーにしか判断できない決定が必要: phaseを `blocked` にして質問を書く。
- 依存関係、秘密情報、本番への書き込み、破壊的な操作についての判断、そのリポジトリの `forbidden` に触れる判断は、絶対に推測しない。PRはdraftのままにし、質問をレポートに書く。
- 実行中にIssueがクローズされたり `[implement]` が外れたりしたら、そのワーカーを止め、残ったブランチを報告する。削除しない。
- 新しいpnpmのworktreeでは、別のチェックアウトの `node_modules` をリンクするのではなく、そのリポジトリのlockfileで依存関係をインストールする。

## レポート

Issueごとに1行: リポジトリと番号、ゲート、依存関係の状態、ブランチ、PR、レビュー結果、チェック、markerのphase。`ready`、`in_progress`、`blocked`、`skipped`、`failed` にグループ分けする。
