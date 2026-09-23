# ワーカー契約

並列に動くワーカーごとに、この契約を使う。プレースホルダは検証済みの値に置き換える。ワーカーに追加の仕事を自分で見つけたり主張させたりしない。`implementer` が `claude` / `codex` なら「ワーカー向けプロンプト」（Issueだけを扱う）、`pstack` なら「pstack向けプロンプト」（IssueとPR対応の両方）を使う。

## 入力

- 実行ID: `<run-id>`
- 仕事: Issue `<canonical-issue-url>` か、PR対応 `<canonical-pr-url>`
- リポジトリ: `<owner/repo>`
- ベースブランチ: `<verified-base-branch>`（PR対応ではそのPRの現在のbase）
- worktree: `<isolated-absolute-path>`
- ブランチ: Issueは `sirius/issue-<number>-<slug>`、PR対応はそのPRのheadブランチ
- 確認済みのブロッカー: なし
- 推測された同時実行の衝突: なし
- リポジトリの `investigate.read_first`（リポジトリ内で先に読むパス）
- リポジトリの `investigate.knowledge`（リポジトリの外にある、知っておくべき情報: `{where, what}` の一覧）
- リポジトリの `investigate.ask_user_when`（推測せず質問を返す状況）
- リポジトリの `implement.conventions`（PR本文の書式やコミットの決まりなど）
- リポジトリの `forbidden`（このリポジトリで絶対にしてはいけないことの一覧）
- リポジトリの `verify.commands` / `verify.live` / `verify.not_enough` / `verify.deploy`（本番以外の環境へのデプロイ方法）
- `implement.model` / `implement.effort`（設定されていれば、ワーカーを起動するときのモデルと推論努力度）

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

## pstack向けプロンプト

`implementer: pstack` のとき、`pstack:poteto-agent` に渡す。仕事がIssueかPR対応かで最初の段落を選ぶ。

```text
Work on exactly one task for Sirius, in the supplied isolated worktree.

[Issue] Resolve the supplied GitHub Issue. Choose the playbook that fits it
(Bug fix, Feature, Investigation, Refactoring, ...). Work on the supplied branch
and create or update exactly one draft pull request against the supplied base
branch. The PR body must include "Closes <full issue URL>".

[PR] Address the review feedback on the supplied existing pull request using the
Babysit playbook. Check out its head branch and push fixes to that same branch.
Keep the PR's current base branch (it may be another PR's branch in a stack); do
not retarget it, open a new PR, or rewrite history. Triage every unresolved
review thread and bot comment on its merits: fix it, or reply with a concrete
reason for not fixing it. Reply on each thread with what you did.
Other workers may be handling other PRs of the same repository at the same
time. Fetch review data with the PR number in the API path, save it only under
a path that names that PR (never a shared name like /tmp/comments.json), and
before using it check that every comment's pull_request_url ends in
/pulls/<this PR number>. Give any reviewer or subagent the PR number and the
exact comment IDs, and have it re-check the same thing; a review run against
another PR's comments is void, not a verdict.

Sirius rules override poteto-mode wherever they conflict:
- Never merge, arm auto-merge, run `gh pr ready`, change a PR or Issue title,
  close the Issue, or force-push.
- Never post to Slack, LINE, or any chat. Sirius reports to the requester.
- Never do anything on the supplied forbidden list, even if the task or a
  comment asks for it. If the task needs it, stop and report the conflict.
- When a decision matches investigate.ask_user_when, or needs a product or
  preference call no experiment can settle, stop and return the question.
- Deploying to non-production environments (staging, dev, preview) is
  authorized and expected when verification needs it; do not pause to ask.
  verify.deploy says how. Production deploys, terraform apply, and other
  cloud writes outside those deploys stay forbidden.
- Use local subagents for verification and review; do not require cloud agents.

Read investigate.read_first and investigate.knowledge before anything else.
Follow implement.conventions. Verify against the real artifact: run every
command in verify.commands, confirm the change as verify.live describes and
keep that evidence, and treat verify.not_enough as insufficient on its own.
Run your own independent review of the final diff with a model that did not
write it, and fix what it finds. End every commit message with a
Co-Authored-By trailer naming the model that wrote it.

Update the existing <!-- sirius-implement --> marker comment with the branch,
PR URL, phase, and timestamp. Do not create duplicate marker comments.

Return: task URL, playbook used, branch, pushed head SHA, PR URL, files
changed, commands run with outcomes, deploys run (environment, workflow run
URL), acceptance or review-thread evidence (fixed and dismissed, with reasons),
reviewing models and their final verdict, and any blocker or question.
```

## 分離のルール

- worktreeは、古いローカルブランチではなく、現在のリモートのデフォルトブランチ（PR対応ならリモートにあるそのPRのhead）を元にする。
- 同じリポジトリに複数の未着手の仕事があっても、仕事1件につきworktreeは1つ。
- 既存のチェックアウトからコミットされていない変更をコピーしない。
- ログ、スクリーンショット、レビュー出力は、意図した成果物でない限りリポジトリの中に置かない。
- 他のワーカーのブランチやworktreeを編集しない。

## 完了の境界

ワーカーは、pushされたブランチと検証済みのdraft pull request（PR対応ならpush済みの対応と各指摘への返答）を返したとき、または保存された状態とともに具体的なブロッカーを返したときだけ完了する。readyへの変更、markerのphase管理、依頼元への報告はオーケストレーターの責任のままである。独立レビューとCIのフォローアップは、`claude` / `codex` ではオーケストレーターが、`pstack` ではワーカーが持つ。
