---
name: implement
description: Implement eligible GitHub Issues in the repositories listed in ~/.sirius/projects/*.yaml, honoring each project's implement gate, and deliver draft-then-ready PRs that passed an independent review. Called by the Sirius run skill.
user-invocable: false
---

# Implement Issues

Run the implementation queue. GitHub labels and one marker comment per Issue are the durable state, so every transition can be observed and resumed.

## Inputs

From `run`: the frozen project table (from `sirius-config show`), the run ID, the worker limit, and the remaining time. Never widen scope beyond the repositories in that table.

## Eligibility

An open Issue (not a PR) in a listed repository, without `working`, `human-review`, `waiting`, or `needs-info`, and:

| Project `implement_gate` | Also required |
|---|---|
| `human` | the `implement` label, added by a person |
| `auto` | the `implement` label, or the `sirius` label |

Never add `implement` yourself; the guard hook refuses it. Skip an Issue that already has an open PR that closes it.

Page through every Issue in every listed repository until `hasNextPage` is false. `gh search` is a fast first pass, not proof of completeness.

## Dependencies

Collect `blockedBy`, parent and sub-Issues, and explicit "depends on" or "blocked by" lines in the body. Open blockers are hard edges. Treat inferred conflicts (same migration, schema, generated file) only as a reason not to run two Issues at once. Run only the ready layer, oldest first across repositories, within the worker limit. Report cycles and ambiguous dependencies instead of claiming them.

## Claim

Just before each claim, re-fetch the Issue. If it is still eligible:

1. create the `working` label if it is missing (never modify existing labels) and add it;
2. re-fetch and confirm `working` is on it and no competing PR appeared;
3. create or update one marker comment `<!-- sirius-implement -->` with the run ID, branch, phase, and timestamps;
4. use the branch `sirius/issue-<number>-<slug>`, and reuse an existing matching branch or draft PR when it can be recovered safely.

At the start of the phase, look at Issues that already carry the marker. Resume their branch or PR. If a claim is stale (no live worker, no progress in the lease window, nothing recoverable), remove `working` and note the recovery once. Never take over a claim with recent progress.

## Work in parallel

Read [worker-contract.md](references/worker-contract.md) before launching workers. Give each worker one Issue and its own worktree, created under `~/.sirius/worktrees/<repo>/<branch>` from the current remote default branch. Never reuse the user's checkout or copy its uncommitted changes.

Launch all workers in the ready layer in one batch. Use the configured `implementer` (`claude`: subagents; `codex`: `codex exec` in the worktree). Workers implement, verify, push, and open a draft PR. They do not review, mark ready, change final labels, or merge.

## Review and repair

Read [review-contract.md](references/review-contract.md) before reviewing. For each worker result, in its worktree:

1. confirm the local head equals the pushed PR head;
2. run a fresh review with the configured `reviewer`;
3. send every actionable finding back to the implementer, then commit, push, and review again with a new reviewer;
4. stop only when the latest completed review reports no actionable findings.

A crashed, timed-out, or partial review is not a clean one. There is no retry count. If a blocker needs the user, keep the PR draft, keep `working`, update the marker comment, and let the next run continue.

## Checks and handoff

After a clean review, check `gh pr checks`. When a failure comes from the branch, fix it and go back to review, since the diff changed. When checks are pending, leave the PR draft for the next run.

When the review is clean and required checks pass:

1. re-fetch the PR and the Issue;
2. `gh pr ready`;
3. create the `human-review` label if missing, add it to the Issue and the PR, and remove `working` from the Issue;
4. update the marker comment with the PR URL, reviewed head SHA, reviewer, and review time;
5. re-fetch both and confirm the labels.

`human-review` means ready for the merge phase, not merged. The merge skill decides what happens next from the project's `merge` setting.

## Failures

- Before a branch or PR exists: remove `working` for a retryable setup failure and note it once.
- After a branch or PR exists: keep `working` and resume next run.
- Decisions about dependencies, secrets, production writes, destructive operations, or anything only the user can decide: do not guess. Keep the PR draft and put the question in the report.
- If the Issue is closed or loses eligibility mid-run, stop its worker and report the leftover branch; do not delete it.
- If `human-review` or `human-merge` appears while a worker runs, stop changing it.
- In a fresh pnpm worktree, install dependencies with the repository's lockfile instead of linking another checkout's `node_modules`.

## Report

One row per Issue: repository and number, gate, dependency state, branch, PR, review result, checks, and final labels. Group them as `ready`, `in_progress`, `blocked`, `skipped`, and `failed`.
