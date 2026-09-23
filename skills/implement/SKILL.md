---
name: implement
description: Implement eligible GitHub Issues in the repositories listed in ~/.sirius/projects/*.yaml, honoring each project's implement gate, and deliver draft-then-ready PRs that passed an independent review. Called by the Sirius run skill.
user-invocable: false
---

# Implement Issues

Run the implementation queue. Sirius uses no labels. Three things on GitHub are the durable state, so every transition can be observed and resumed:

- the `[implement]` prefix on an Issue title: the go-ahead to build it;
- one marker comment `<!-- sirius-implement -->` on the Issue, whose `phase` is `working`, `waiting`, `blocked`, or `ready`;
- the linked PR: draft while in progress, ready when handed off.

## Inputs

From `run`: the frozen project table (from `sirius-config show`), the run ID, the worker limit, and the remaining time. Never widen scope beyond the repositories in that table.

## Eligibility

An open Issue (not a PR) in a listed repository whose title starts with `[implement]`, and whose marker comment is absent or has phase `working` (resume) but not `waiting`, `blocked`, or `ready`.

Who adds `[implement]` depends on the project's `implement_gate`: a person for `human`, and `create-issue` for `auto`. In `human` projects, never add it yourself; the guard hook refuses it. An Issue a person wrote and prefixed is eligible in either mode.

Skip an Issue that already has a ready PR closing it.

Page through every Issue in every listed repository until `hasNextPage` is false. `gh search` is a fast first pass, not proof of completeness.

## Dependencies

Collect `blockedBy`, parent and sub-Issues, and explicit "depends on" or "blocked by" lines in the body. Open blockers are hard edges. Treat inferred conflicts (same migration, schema, generated file) only as a reason not to run two Issues at once. Run only the ready layer, oldest first across repositories, within the worker limit. Report cycles and ambiguous dependencies instead of claiming them.

## Claim

Just before each claim, re-fetch the Issue. If it is still eligible:

1. create or update the marker comment `<!-- sirius-implement -->` with phase `working`, the run ID, the branch, and timestamps;
2. re-fetch the comments and confirm yours is the only marker with phase `working` for a live run, and that no competing PR appeared;
3. use the branch `sirius/issue-<number>-<slug>`, and reuse an existing matching branch or draft PR when it can be recovered safely.

At the start of the phase, look at Issues that already carry the marker. Resume their branch or PR. If a claim is stale (no live worker, no progress in the lease window, nothing recoverable), set the marker back to no phase and note the recovery once. Never take over a claim with recent progress.

## Work in parallel

Read [worker-contract.md](references/worker-contract.md) before launching workers. Give each worker one Issue and its own worktree, created under `~/.sirius/worktrees/<repo>/<branch>` from the current remote default branch. Never reuse the user's checkout or copy its uncommitted changes.

Launch all workers in the ready layer in one batch. Use the configured `implementer` (`claude`: subagents; `codex`: `codex exec` in the worktree). Workers implement, verify, push, and open a draft PR. They do not review, mark ready, change titles, or merge.

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
3. set the marker phase to `ready`, with the PR URL, reviewed head SHA, reviewer, and review time;
4. re-fetch both and confirm the PR is ready and the marker says `ready`.

Do not put `[merge]` on the PR here. A ready PR goes to the merge skill, which decides from the project's `merge` setting.

## Failures

- Before a branch or PR exists: clear the marker phase for a retryable setup failure and note it once.
- After a branch or PR exists: keep phase `working` and resume next run.
- Waiting on someone outside: phase `waiting` with what is awaited. A person clears it by deleting the phase line or the marker.
- Needs a decision only the user can make: phase `blocked` with the question.
- Decisions about dependencies, secrets, production writes, destructive operations, or anything only the user can decide: do not guess. Keep the PR draft and put the question in the report.
- If the Issue is closed or `[implement]` is removed mid-run, stop its worker and report the leftover branch; do not delete it.
- In a fresh pnpm worktree, install dependencies with the repository's lockfile instead of linking another checkout's `node_modules`.

## Report

One row per Issue: repository and number, gate, dependency state, branch, PR, review result, checks, and marker phase. Group them as `ready`, `in_progress`, `blocked`, `skipped`, and `failed`.
