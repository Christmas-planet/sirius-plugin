---
name: merge
description: Finish ready Sirius PRs according to each project's merge setting - notify for manual projects, and for auto projects post the reviewer-account verdict and merge only through sirius-merge. Called by the Sirius run skill; can also be run for one PR.
---

# Merge

`sirius-merge` (in the plugin's `bin/`) is the only way Sirius merges. The go-ahead is the `[merge]` prefix at the start of the PR title; Sirius uses no labels. The guard hook refuses `gh pr merge` and the merge API, but a hook is only a backstop. The real gate is on GitHub: a ruleset that requires one approval on the current head, where only the separate reviewer account approves.

## Targets

Open, non-draft PRs in the repositories of the frozen project table that close an Issue whose marker says `ready`, plus any PR whose title starts with `[merge]`. Get each PR's effective mode with `sirius-config repo <owner/repo>`.

## `merge: manual`

A person reviews the PR and adds `[merge]` to the start of its title. Never add it yourself; the guard hook refuses it.

- Without `[merge]`: once per PR head, list the PR under "waiting for you" in the run report. Do not re-report it every run unless the head has changed.
- With `[merge]`: run `sirius-merge merge <repo> <pr>`. It requires that the prefix was added after the latest commit, so commits pushed after the person's go-ahead are never merged unseen. If new commits came in, report that the person needs to review and add `[merge]` again. Do not remove the prefix yourself.

## `merge: auto`

For each PR:

1. `sirius-merge check <repo> <pr>` (read-only). If it reports a problem other than the missing verdict or approval, fix what Sirius owns (rebase onto the base, wait for CI) and report the rest.
2. If the reviewer verdict for the current head is missing, run verification with the configured `reviewer`, not the implementer. Use four lanes:
   - `gates`: rerun the repository's checks;
   - `live`: confirm the change on a real screen or endpoint, and save evidence files under `~/.sirius/evidence/`;
   - `audit`: compare the diff and the evidence with the Issue's acceptance criteria;
   - `regression`: compare with the base branch.

   Write the lanes JSON (`head_sha` and `base_sha` that you verified, `lanes`, `verifier_models`, `author_models`, `summary`, and `human_only` / `human_only_reason` when the change touches contracts, money, payments, authentication, or store submission) and run `sirius-merge verdict <repo> <pr> <lanes.json>`. It posts the verdict as the reviewer account and approves only a passing verdict that is not human-only.
   A verdict counts only for exactly that head on exactly that base tip. Any merge into the base between the verdict and the merge means rebasing and verifying again; on a busy base, finish verification and merge in the same run.
3. Add `[merge]` to the start of the PR title (`gh pr edit <pr> -R <repo> --title "[merge] <title>"`) so the state is visible, then `sirius-merge merge <repo> <pr>`. It runs every check twice and merges only if both passes agree, then squash-merges with `--match-head-commit`. For a branch listed in `deploys`, it waits for the workflow named in `deploy_workflows` and opens a revert PR if it fails. With no workflow named, it reports the deploy as unverified and asks the user to check it by hand.
4. After a verified merge, close the source Issue if GitHub did not close it, and comment the merge SHA on it.

If `sirius-merge` refuses, report its output as it is. Never work around a refusal, add `--admin`, or change rulesets.

## Stop switch

When `~/.sirius/STOP` exists, `sirius-merge` refuses everything. `/sirius:stop` creates it.
