---
name: implement
description: ~/.sirius/repos/*.yamlに列挙されたリポジトリで、対応可能なGitHub Issueと、取り込みが見つけた既存PRへの指摘対応を、各リポジトリの実装ゲートに従ってワーカーに渡し、検証済みのreadyなPR（既存PRならpush済みの対応）に仕上げる。implementerがpstackなら調査・実装・検証・STGデプロイ・レビュー対応をpstackのpoteto-agentに任せる。Sirius runスキルから呼ばれる。
user-invocable: false
---

# 作業を実装する

実装キューを動かす。Siriusはラベルを使わない。GitHub上の状態が永続的な情報源であり、どの遷移も観察・再開できる。

仕事は2種類:

- **Issue**: タイトルが `[implement]` で始まるIssue。新しいブランチとdraft PRを作り、readyまで仕上げる。
- **PR対応**: 取り込みが `create-issue` から `pr_task` として受け取った、既存のオープンPRへの指摘対応（レビューコメント、変更要求、Copilot等のbotの指摘）。新しいPRは作らず、そのPRのブランチに対応をpushし、各指摘に返答する。

どちらも、対象（IssueかPR）に付けるmarkerコメント1つ `<!-- sirius-implement -->` で進捗を持つ。`phase` は `working`、`waiting`、`blocked`、`ready` のいずれか。PR対応のmarkerには、依頼元（ソース種別、会話ID、スレッドの `thread_ts` かLINEのチャット名、`request_group`）もIDだけで書く。本文は書かない。

## 入力

`run` から: 凍結済みリポジトリ表（`sirius-config show` から）、実行ID、ワーカー上限、残り時間、この実行の取り込みが返した `pr_task` の一覧。この表にあるリポジトリを超えて範囲を広げない。

## 対象の条件

- Issue: 一覧にあるリポジトリの、タイトルが `[implement]` で始まるオープンIssue（PRではない）で、markerコメントが無いか、phaseが `working`（再開）だが `waiting`、`blocked`、`ready` ではないもの。すでにreadyなPRがひも付いているIssueはスキップする。
- PR対応: この実行の `pr_task` と、一覧にあるリポジトリのオープンPRのうちmarkerのphaseが `working` のもの（前回からの再開）。PRがクローズ・マージ済みなら対象外にして報告する。

`[implement]` を誰が付けるかは、そのリポジトリの `implement.gate` によって決まる: `human` なら人が、`auto` なら `create-issue` が付ける。`human` のリポジトリでは自分では絶対に付けない。guard hookが拒否する。人が書いて接頭辞を付けたIssueは、どちらのモードでも対象になる。PR対応はPRタイトルに接頭辞を付けない（`[merge]` と衝突するため）: `implement.gate: auto` ならmarkerを付けて着手し、`human` ならmarkerを `waiting`（人の着手合図待ち）で作って報告だけする。人がmarkerの `phase: waiting` の行を消すと次の実行で着手する。

一覧にある各リポジトリで、`hasNextPage` が false になるまで全Issueをページ送りする。`gh search` は速い一次スキャンであって、網羅の証明ではない。

## 依存関係

`blockedBy`、親/子Issue、本文中の明示的な "depends on" / "blocked by" の行を集める。`create-issue` が同じ依頼を複数リポジトリに分けたときは `## Related` 節に `Depends on owner/repo#<n>` と別リポジトリのIssueが書かれる。これも同じく依存関係で、そのIssueを取得して状態を確かめる。オープンなブロッカーは強い制約として扱う: ブロッカーがクローズされる（そのPRがマージされる）まで着手しない。別リポジトリのブロッカーは、そのリポジトリの実装・マージが先に進むのを待つ。推測された衝突（同じマイグレーション、スキーマ、生成ファイル）は、2つの仕事を同時に走らせない理由としてだけ扱う。同じPRのブランチ、または積み重なったPR（あるPRのbaseが別のPRのブランチ）は同じ層で並べない: 下のPRから順に1ワーカーずつ。実行できる層だけを、リポジトリを横断して古い順に、ワーカー上限内で走らせる。循環や曖昧な依存関係は、勝手に解決したと主張せず報告する。

## 着手

着手ごとに、対象を取り直してから行う。まだ対象なら:

1. markerコメント `<!-- sirius-implement -->` を作成または更新し、phaseを `working`、実行ID、ブランチ、日時を書く;
2. コメントを取り直して、生きている実行の `working` phaseのmarkerが自分のものだけであること、競合するPRが現れていないことを確認する;
3. ブランチを決める。Issueは `sirius/issue-<number>-<slug>`（既存の一致するブランチやdraft PRが安全に復元できるなら再利用する）。PR対応はそのPRのheadブランチそのもので、baseもそのPRの現在のbase（積み重なったPRなら下のPRのブランチ）。baseを書き換えない。

baseブランチはローカルの `origin/HEAD` から推測しない。Issueは `gh repo view <repo> --json defaultBranchRef` で確かめたデフォルトブランチ、PR対応は `gh pr view --json baseRefName,headRefName,headRefOid` の値を使う。

phaseの最初に、すでにmarkerが付いている対象を見る。ブランチかPRを再開する。着手が古くなっている（生きているワーカーがなく、リース期間内に進捗がなく、復元できるものがない）場合は、markerをphaseなしに戻して、一度だけ復元の記録を残す。最近進捗があった着手を横取りしない。

## 並列に作業する

ワーカーを起動する前に[worker-contract.md](references/worker-contract.md)を読む。各ワーカーには1つの仕事と専用のworktreeを与える。worktreeは `~/.sirius/worktrees/<repo>/<branch>` の下に作る: Issueは現在のリモートのデフォルトブランチから、PR対応はそのPRのheadを取得して。ユーザー自身のチェックアウトを再利用したり、そのコミットされていない変更をコピーしたりしない。

実行できる層のワーカーは、すべて1バッチで起動する。起動のしかたは凍結済み表の `implement.implementer` で決まる:

- `pstack`: `Agent` ツールで `subagent_type: "pstack:poteto-agent"`、`run_in_background: true` のサブエージェントを起動し、worker-contractの「pstack向けプロンプト」を渡す。完了の通知を待つ。poteto-agentは仕事に合うplaybook（Issueなら Bug fix / Feature / Investigation など、PR対応なら Babysit）を自分で選び、調査・実装・検証・独立レビューまで行う。`implement.model` / `implement.effort` が設定されていれば `model` に渡す。
- `claude`: 通常のサブエージェントに、worker-contractの「ワーカー向けプロンプト」を渡す。
- `codex`: worktree内の `codex exec` に、同じプロンプトを渡す（`--model` / `-c model_reasoning_effort=`）。

ワーカーへ渡すときは、そのリポジトリの `investigate.read_first`、`investigate.knowledge`、`investigate.ask_user_when`、`implement.conventions`、`forbidden`、`verify.commands`、`verify.live`、`verify.not_enough`、`verify.deploy` を必ず添える。これらはworker-contractのプロンプトに差し込む値であり、省略しない。ワーカーはマージ、`gh pr ready`、タイトル変更、Slack/LINEへの投稿をしない。

## レビュー

- `pstack`: poteto-agentが自分の手順の中で独立レビュー（`interrogate` や別モデルの確認）を行い、その結果を返す。Siriusはレビューをやり直さない。返ってきた結果から、レビューしたheadのSHA、レビューしたモデル、未解決の指摘の有無を確かめる。未解決の指摘が残っているのに完了と報告されたら、同じ仕事を新しいpoteto-agentに続きとして渡す（前回の要約を信じて閉じない）。
- `claude` / `codex`: [review-contract.md](references/review-contract.md)を読み、各ワーカーの結果について、そのworktreeの中で:
  1. ローカルのheadがpush済みPRのheadと一致することを確認する;
  2. 設定された `reviewer`（そのリポジトリの `review.reviewer` があればそちらを優先し、`review.focus` を渡す）で新しくレビューを実行する;
  3. 実行可能な指摘はすべて実装役に返し、コミット・pushしてから、新しいレビュワーで再レビューする;
  4. 最新の完了したレビューが実行可能な指摘なしと報告したときだけ止まる。

  クラッシュした、タイムアウトした、部分的なレビューはクリーンとはみなさない。リトライ回数の上限はない。

ユーザーの判断が要るブロッカーがあれば、PRをdraftのまま（PR対応ならそのまま）、phaseを `working` のままにし、markerコメントを更新して、次の実行に続きを任せる。

## チェックと引き渡し

レビューの後、`gh pr checks` を確認する。失敗がブランチ由来なら、同じワーカー種別で直してからレビューに戻る（差分が変わったため）。チェックが保留中なら、次の実行まで今の状態のままにする。

Issueの場合、レビューがクリーンで必須チェックが通ったら:

1. PRとIssueを取り直す;
2. `gh pr ready`;
3. markerのphaseを `ready` にし、PRのURL、レビュー済みheadのSHA、レビュワー、レビュー日時を書く;
4. 両方を取り直して、PRがreadyでmarkerが `ready` になっていることを確認する。

PR対応の場合、対応がpushされ、各指摘スレッドに対応内容か見送りの理由が返答され、必須チェックが通ったら、markerのphaseを `ready` にし、pushしたheadのSHA、対応した指摘と見送った指摘の数、レビュワーを書く。PRのdraft/ready状態は変えない。

ここで `[merge]` をPRに付けない。readyになったPRはmergeスキルに渡り、そのリポジトリの `merge.mode` から判断する。

## 依頼元への報告

Slack/LINEの依頼から来た仕事がこの実行で `ready` になったら、依頼元の会話へ1通だけ報告を返す。依頼元は、IssueならIssue本文の Source（`create-issue` が書いた最小限の参照）、PR対応ならmarkerに書いた依頼元のID。

- 文面は[返信契約](../../references/reply-contract.md)に従う。返信の設定（`reply.mode`、`style`、`never`）はソースの持ち主（リポジトリかworkspace）のものを使う。
- 中身: 何をしたか（直したもの、見送ったものとその理由）、見てほしいPRのリンク、相手にしてほしいこと（レビュー・承認など）。確かめた事実だけを書く。
- 同じ `request_group` の仕事が複数リポジトリにあるときは、全部が `ready` になってから1通にまとめる。
- markerに `reported: <permalink or time>` を書き、同じ `ready` について二度報告しない。新しいコミットで再び `ready` になったときだけ、もう一度報告してよい。
- 送るのはこのオーケストレーターだけ。ワーカーは送らない。

## 失敗

- ブランチやPRができる前: やり直せるセットアップの失敗ならmarkerのphaseを消し、一度だけ記録する。
- ブランチやPRができた後: phaseを `working` のままにして次の実行で再開する。
- 外部の誰かを待っている: phaseを `waiting` にし、何を待っているか書く。人がphaseの行かmarker自体を削除して解除する。
- ユーザーにしか判断できない決定が必要: phaseを `blocked` にして質問を書く。
- 依存関係、秘密情報、本番への書き込み、破壊的な操作についての判断、そのリポジトリの `forbidden` や `investigate.ask_user_when` に触れる判断は、絶対に推測しない。PRは今の状態のままにし、質問をレポートに書く。本番以外の環境（STGなど）へのデプロイはこれに含まれない: 検証のために、ワーカーが確認なしで行ってよい。
- 実行中にIssueがクローズされたり `[implement]` が外れたり、PR対応のPRがクローズ・マージされたりしたら、そのワーカーを止め、残ったブランチを報告する。削除しない。
- 新しいpnpmのworktreeでは、別のチェックアウトの `node_modules` をリンクするのではなく、そのリポジトリのlockfileで依存関係をインストールする。

## レポート

仕事ごとに1行: リポジトリと番号（IssueかPR）、ゲート、ワーカー種別と選ばれたplaybook、依存関係の状態、ブランチ、PR、レビュー結果、チェック、STGへのデプロイ、markerのphase、依頼元への報告。`ready`、`in_progress`、`blocked`、`skipped`、`failed` にグループ分けする。
