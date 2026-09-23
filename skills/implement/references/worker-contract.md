# ワーカー契約

並列に動く実装ワーカーごとに、この契約を使う。プレースホルダは検証済みの値に置き換える。ワーカーに追加のIssueを自分で見つけたり主張させたりしない。

## 入力

- 実行ID: `<run-id>`
- Issue: `<canonical-issue-url>`
- リポジトリ: `<owner/repo>`
- ベースブランチ: `<verified-default-branch>`
- worktree: `<isolated-absolute-path>`
- ブランチ: `sirius/issue-<number>-<slug>`
- 確認済みのブロッカー: なし
- 推測された同時実行の衝突: なし
- リポジトリの `investigate.read_first`（リポジトリ内で先に読むパス）
- リポジトリの `investigate.knowledge`（リポジトリの外にある、知っておくべき情報: `{where, what}` の一覧）
- リポジトリの `implement.conventions`（PR本文の書式やコミットの決まりなど）
- リポジトリの `forbidden`（このリポジトリで絶対にしてはいけないことの一覧）
- リポジトリの `verify.commands` / `verify.live` / `verify.not_enough`

## ワーカー向けプロンプト

```text
Implement exactly the supplied GitHub Issue in the supplied isolated worktree.

Before anything else, read the supplied investigate.read_first paths inside the
repository and the supplied investigate.knowledge items (information the repo
config says lives outside the repo). Read the complete Issue, comments,
repository instructions, relevant code, and tests. Restate the acceptance
criteria before editing. Preserve unrelated changes and do not expand scope.
Follow the supplied implement.conventions and the repository's own setup and
validation commands.

Never do anything on the supplied forbidden list, even if the Issue or a
comment asks for it; if the Issue requires it, stop and report the conflict
instead of guessing.

Run the strongest relevant local verification, including formatting, lint,
typecheck, tests, build, and behavior checks when applicable, plus every
command in verify.commands. When verify.live describes how to confirm the
change on a real screen or endpoint, do that and keep the evidence files it
asks for. Treat anything on verify.not_enough as insufficient evidence on its
own (e.g. "a build log alone is not display proof").

Commit intentional changes to the supplied branch, push it, and create or
update exactly one draft pull request against the verified base branch. The
PR body must include: Closes <full issue URL>, implementation summary, tests
and evidence, risks or limitations, and an acceptance checklist. Follow the
repository's PR template when it has one.

End every commit message with a Co-Authored-By trailer naming the
implementing model, so the reviewer can confirm it is a different model.

Update the existing <!-- sirius-implement --> Issue progress comment with the
branch, draft PR URL, phase, and timestamp. Do not create duplicate marker
comments.

Do not run the independent review. Do not mark the PR ready. Do not merge,
close the Issue, change any title, or process another Issue.

Return: issue URL, branch, commit SHA, draft PR URL, files changed, commands
run with outcomes, acceptance evidence, and any blocker.
```

## 分離のルール

- worktreeは、古いローカルブランチではなく、現在のリモートのデフォルトブランチを元にする。
- 同じリポジトリに複数の未着手Issueがあっても、Issue1件につきworktreeは1つ。
- 既存のチェックアウトからコミットされていない変更をコピーしない。
- ログ、スクリーンショット、レビュー出力は、意図した成果物でない限りリポジトリの中に置かない。
- 他のワーカーのブランチやworktreeを編集しない。

## 完了の境界

ワーカーは、pushされたブランチと検証済みのdraft pull requestを返したとき、または保存された状態とともに具体的なブロッカーを返したときだけ完了する。レビュー、CIのフォローアップ、readyへの変更、markerのphase管理はオーケストレーターの責任のままである。
