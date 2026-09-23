---
name: status
description: Show Sirius state read-only - effective per-project settings and downgrades, the lease, source checkpoints and pending questions, queued and in-progress Issues, and PRs waiting for review or merge. Use for /sirius:status.
---

# Sirius status

Read-only. Make no writes anywhere.

1. `sirius-config show`: for each project, show the repositories, sources, effective `implement_gate` and `merge`, and every `downgrades` reason. Show config errors first when there are any.
2. `sirius-lease status` and whether `~/.sirius/STOP` exists.
3. Checkpoints under `~/.sirius/state/intake/`: last completed cutoff per source, and any pending question word for word.
4. For each repository, with `gh`:
   - Issues that are eligible for implementation under the project's gate;
   - Issues with `working` (from the marker comment: branch, PR, last update);
   - Issues with `needs-info` or `waiting`;
   - PRs with `human-review`: for `manual` projects, "waiting for you to merge"; for `auto` projects, the result of `sirius-merge check`.
5. The newest file in `~/.sirius/runs/` and `~/.sirius/logs/tick/`: when the last run was and its `SIRIUS_STATUS`.

When the current directory is a registered project (`sirius-config project`), show that project first and in detail, and the others as one line each.

End with what is waiting on the user, most urgent first.
