---
name: setup
description: Register the current project directory with Sirius, or create the global settings, by writing ~/.sirius/config.yaml and ~/.sirius/projects/<name>.yaml interactively, then print the checklist of steps only the operator can do (permissions, reviewer account, rulesets, scheduler). Use for /sirius:setup.
disable-model-invocation: true
---

# Sirius setup

Setup is interactive. Every write to `~/.sirius/config.yaml` or `~/.sirius/projects/` goes through the Write or Edit tool, and the guard hook asks the user to approve it. Never write these files from the shell. Nothing is written inside the project repository.

## 1. Global settings (first time only)

If `~/.sirius/config.yaml` does not exist, ask with AskUserQuestion:

- **implementer** and **reviewer**: `claude` or `codex`. They must differ for `merge: auto` to work. Recommend implementer `claude` and reviewer `codex`.
- **Ceilings**: the loosest `implement_gate` (`human` or `auto`) and `merge` (`manual` or `auto`) any project may use. Projects can be stricter, never looser.
- **scheduler**: `none` (run `/sirius:run` by hand), `loop` (`/loop 10m /sirius:run` inside an open session), or `launchd` (every N minutes in the background on this Mac). Use one scheduler per machine and do not add a cloud routine for the same queue: the lease is per machine.

Write it from [the template](../../templates/config.yaml).

## 2. Register this project

1. Read `git remote get-url origin` in the current directory. Convert it to `owner/repo` and confirm it with `gh repo view`.
2. Run `sirius-config repo <owner/repo>`. If a project already lists it, show that project and offer to edit it instead of creating a second one. A repository may belong to only one project.
3. Ask for the project name (default: the repository name, in kebab-case), any other repositories in the same project, the sources, and the gates:
   - Slack: exact workspace ID (`T…`) and channel IDs (`C…`). When a Slack connector is available, list the user's channels so they can pick. Names and wildcards do not count.
   - LINE: exact chat titles as shown in the app (this Mac only).
   - `implement_gate`: `human` means a person adds the `implement` label to an Issue before Sirius builds it. `auto` means Sirius builds any `sirius` Issue that has clear acceptance criteria.
   - `merge`: `manual` means Sirius makes the PR ready and a person merges. `auto` means Sirius merges when the reviewer account's verdict, the approval, CI, and the base-branch conditions all pass.
   - Rules for each repository in `merge_rules`: `ci_required`, `approvals` (human approvals needed in addition to the reviewer account), `human_branches` (branch → reason, `*` for all), `deploys` (branch → what a merge deploys), and `deploy_workflows` (branch → the Actions workflow that performs it).
4. Write `~/.sirius/projects/<name>.yaml` from [the template](../../templates/project.yaml), with `dir` set to the current directory.
5. Run `sirius-config validate` and show the effective result, including any `downgrades`.

For a project migrated from the old Sirius, the file has `needs_review: true`. That keeps the project on `human` and `manual` until the user has checked the file and removed the flag. Walk through the file with the user; do not remove the flag on your own judgment.

## 3. Labels

For each repository, list the labels, then create only the missing Sirius labels: `sirius`, `implement`, `working`, `human-review`, `needs-info`, `waiting`, and `human-merge`. Never change existing labels. Show what will be created and create it after the user agrees.

## 4. Operator checklist

Print the steps that apply as a checklist, with exact commands. The agent must not do these itself: the guard hook refuses ruleset changes, and auto mode refuses writes to settings files.

**Always**

- Add to `~/.claude/settings.json` under `permissions.deny`: `Bash(gh pr merge:*)`, `Bash(git push --force:*)`, `Bash(git push -f:*)`. The plugin cannot ship permission rules, and the guard hook is only a backstop.
- If auto mode is used, list every repository in scope in the auto-mode `environment`, or the classifier may refuse legitimate work in the repositories it does not know.

**When any project uses `merge: auto`**

1. Create a separate GitHub account for review (a machine user) and give it write access to the repositories. It must not be the account the agent uses.
2. Log it in to its own gh config directory:
   ```bash
   GH_CONFIG_DIR=~/.sirius/identities/reviewer gh auth login
   ```
3. Add it to `config.yaml`:
   ```yaml
   identities:
     reviewer: {login: <account>, gh_config_dir: ~/.sirius/identities/reviewer}
   ```
4. On each repository's default branch, add a ruleset that requires one approving review, dismisses stale approvals on push, and requires approval of the most recent push. Without it, the gate is enforced only by Sirius's own tools. Give the exact `gh api` command or the settings page URL.

Until steps 1–3 are done, `sirius-config` reports those projects as `manual`.

**Scheduler `launchd`**

Copy `bin/sirius-tick` to `~/.sirius/bin/sirius-tick`, so the job does not point into the versioned plugin cache. Then generate the plist from [the template](../../templates/launchd.plist) with the chosen interval, and give the user these commands:

```bash
cp <plist> ~/Library/LaunchAgents/ai.sirius.tick.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.sirius.tick.plist
```

The job uses `StartInterval` without `KeepAlive`, so a crash does not cause a restart loop. To stop it: `launchctl bootout gui/$(id -u)/ai.sirius.tick`.

## 5. Finish

Show `sirius-config show` for the project, the created labels, and the remaining checklist. Suggest `/sirius:status` next.
