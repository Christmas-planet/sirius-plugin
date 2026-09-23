---
name: stop
description: Stop Sirius immediately by creating ~/.sirius/STOP, which blocks every run and every merge; with the argument "resume", remove it. Use for /sirius:stop or whenever the user says to stop Sirius.
disable-model-invocation: true
argument-hint: "[resume]"
---

# Stop Sirius

Without an argument:

1. `touch ~/.sirius/STOP`. Do this first, before anything else.
2. Show `sirius-lease status`. A run already in progress finishes its current step. `sirius-merge` refuses every merge while the file exists, and the next run ends immediately.
3. If the scheduler is `launchd`, also tell the user `launchctl bootout gui/$(id -u)/ai.sirius.tick` for a full stop.

With `resume`:

1. Show `sirius-config validate`. If it reports errors, say that the next run will stop on them.
2. Ask the user to confirm, then `rm ~/.sirius/STOP`.
