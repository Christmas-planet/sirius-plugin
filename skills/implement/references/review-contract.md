# Review contract

The implementer and reviewer are `implementer` and `reviewer` in `~/.sirius/config.yaml` (`claude` or `codex`). `merge: auto` requires them to differ; with the same model on both sides, `sirius-config` falls back to `manual`.

Run every review from the isolated Issue checkout after fetching the base and checking out the exact pushed pull-request head.

## Command shape

- `codex`: `codex review --base <verified-base-branch> "<review-prompt>"`
- `claude`: launch a new Claude subagent in the checkout with the prompt below and the diff against the base. It must not reuse the implementer's context.

Use a fresh reviewer for every pass. Do not resume the prior reviewer session. Do not enable unsafe sandbox or approval bypasses.

## Review prompt

```text
Review this pull-request diff for actionable correctness, security, data-loss, concurrency, compatibility, regression, and missing-test problems. Read repository instructions and the linked Issue acceptance criteria. Do not focus on subjective style unless it causes a concrete maintenance or correctness risk.

For each finding, report severity, file and line, evidence, impact, and the smallest valid fix. If and only if there are no actionable findings, end with the exact line NO_FINDINGS. Do not emit NO_FINDINGS when review could not complete.
```

## Decision rules

- Exit success alone does not mean clean; inspect the completed review output.
- `NO_FINDINGS` is valid only when it is the final verdict of a completed review and no actionable finding appears elsewhere in that review.
- Tool errors, authentication errors, rate limits, timeouts, incomplete output, and contradictory findings are not clean.
- After any code, test, configuration, lockfile, or generated-file change, discard the old verdict and run a fresh review.
- If the implementer believes a finding is false, gather concrete repository evidence and include it in the next fresh review. Do not self-dismiss the last remaining finding.
- Store review output outside the repository or in ignored temporary state. Never commit reviewer logs or credentials.

## Clean-review evidence

Record the reviewed head SHA, base branch and SHA, reviewer, timestamp, and clean final verdict in the Issue's single marker comment. For `merge: auto` projects, the merge skill turns this into a verdict posted by the reviewer account. A later pushed commit invalidates this evidence.
