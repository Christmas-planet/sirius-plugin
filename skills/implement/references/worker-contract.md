# Worker contract

Use this contract for each parallel implementation worker. Replace placeholders with verified values; never ask a worker to discover or claim additional Issues.

## Inputs

- Run ID: `<run-id>`
- Issue: `<canonical-issue-url>`
- Repository: `<owner/repo>`
- Base branch: `<verified-default-branch>`
- Worktree: `<isolated-absolute-path>`
- Branch: `sirius/issue-<number>-<slug>`
- Verified blockers: none open
- Inferred concurrency conflicts: none

## Worker prompt

```text
Implement exactly the supplied GitHub Issue in the supplied isolated worktree.

Read the complete Issue, comments, repository instructions, relevant code, and tests. Restate the acceptance criteria before editing. Preserve unrelated changes and do not expand scope. Follow repository-specific setup and validation commands. Run the strongest relevant local verification, including formatting, lint, typecheck, tests, build, and behavior checks when applicable.

Commit intentional changes to the supplied branch, push it, and create or update exactly one draft pull request against the verified base branch. The PR body must include: Closes <full issue URL>, implementation summary, tests and evidence, risks or limitations, and an acceptance checklist. Follow the repository's PR template when it has one.

End every commit message with a Co-Authored-By trailer naming the implementing model, so the reviewer can confirm it is a different model.

Update the existing <!-- sirius-implement --> Issue progress comment with the branch, draft PR URL, phase, and timestamp. Do not create duplicate marker comments.

Do not run the independent review. Do not mark the PR ready. Do not merge, close the Issue, change any title, or process another Issue.

Return: issue URL, branch, commit SHA, draft PR URL, files changed, commands run with outcomes, acceptance evidence, and any blocker.
```

## Isolation rules

- Base the worktree on the current remote default branch, not a stale local branch.
- Use one worktree per Issue even when several ready Issues share a repository.
- Do not copy uncommitted changes from an existing checkout.
- Do not place logs, screenshots, or review output inside the repository unless they are intentional deliverables.
- Do not edit another worker's branch or worktree.

## Completion boundary

The worker is complete only when it returns a pushed branch and a verified draft pull request, or a concrete blocker with preserved state. Review, CI follow-up, readiness, and the marker phase remain the orchestrator's responsibility.
