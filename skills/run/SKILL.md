---
name: run
description: Run one Sirius cycle - merge ready PRs, resume pending confirmations, read the configured Slack and LINE sources into GitHub Issues, and implement eligible Issues - using the per-project settings in ~/.sirius. Use for /sirius:run, a /loop of it, or a scheduled run.
---

# Sirius run

Coordinate one bounded cycle. Component skills do the work: `merge`, `intake-slack`, `intake-line`, `create-issue`, and `implement`. The plugin's `bin/` is on PATH while the plugin is enabled, so call `sirius-config`, `sirius-lease`, and `sirius-merge` by name.

## 1. Load and freeze the settings

1. If `~/.sirius/STOP` exists, report `stopped` and end with `SIRIUS_STATUS: ok`. Do nothing else.
2. Run `sirius-config show`. If `ok` is false, make no external writes; report the errors and end with `SIRIUS_STATUS: blocked`.
3. Keep the JSON as the frozen project table for this run: projects, exact repositories, exact sources, the effective `implement_gate` and `merge`, and the `downgrades` explaining any fallback. Hash it into the ledger.
4. Only these repositories and sources are in scope. Never fall back to the current directory's remote, every accessible repository, or every visible conversation. Settings never live in a project repository, so nothing a PR changes can loosen a gate.
5. You cannot change `~/.sirius/config.yaml` or `~/.sirius/projects/*.yaml` during a run. The guard hook asks a person to approve such a change, and an unattended run has no one to approve it. If a setting looks wrong, say so in the report.

## 2. Take the lease

Create a run ID (`<UTC timestamp>-<4 random hex>`) and run `sirius-lease acquire <run-id>`. Exit code 3 means another run is active: report it and end with `SIRIUS_STATUS: busy`. Run `sirius-lease heartbeat <run-id>` after every phase. Keep the ledger at `~/.sirius/runs/<run-id>.json`: IDs, hashes, scope, cursors, URLs, counts, and times only. Never store message bodies, secrets, or repository content.

The lease is per machine. Only one scheduler (`scheduler` in `config.yaml`) may run a queue.

## 3. Preflight (read-only)

- `gh auth status` works, and every repository in scope is reachable with push access.
- The configured `implementer` and `reviewer` are available (`codex --version` when either one is `codex`).
- For each source kind in scope, its tool is available: a Slack connector for Slack, and Computer Use with the LINE app for LINE. A missing source tool disables only that source.
- For `merge: auto` projects, `sirius-merge check` on any one ready PR shows the reviewer account working. If it does not, treat that project as `manual` for this run and report why.

Write the plan to the ledger before the first external write. Re-fetch each object just before changing it.

## 4. Phases

1. **Merge.** Run the `merge` skill for PRs with `human-review`. Afterwards, refresh the affected base branches.
2. **Pending confirmations.** For each source checkpoint in `awaiting_confirmation`, put the saved question in the report and skip that source's intake. If the user answered in this conversation, resume it as the intake contract describes.
3. **Intake.** Run `intake-slack` and `intake-line` for the unpaused sources in scope, in parallel. Pass each one only its project's sources and repositories, the frozen cutoff, and the new-Issue limit. Every Issue goes through `create-issue`.
4. **Implement.** Run the `implement` skill with the frozen table, the run ID, `limits.concurrent_workers`, and the remaining time.
5. **Reconcile.** Re-fetch every Issue and PR you changed. Save the checkpoints and the ledger. Release the lease with `sirius-lease release <run-id>` only after the state is saved.

Stop starting new work when the remaining time cannot reach a safe checkpoint. Excess work stays queued with no change of state.

## 5. Report

Per project: sources read and their cutoffs, Issues created or found as duplicates, confirmations waiting on the user, Issues claimed, resumed, or blocked, PRs in draft, ready, or merged, PRs waiting for a manual merge, review passes, checks, retries, and any setting downgrades. Include the settings hash, the cutoff, the duration, and whether the lease was released. Never call the run complete while pagination, a checkpoint, or reconciliation is partial.

End with exactly one line:

```
SIRIUS_STATUS: ok | blocked | busy | failed
```

Use `blocked` when anything waits on the user: a confirmation, a manual merge, a setup gap, or a settings error. The scheduler notifies the user on `blocked` and `failed`.
