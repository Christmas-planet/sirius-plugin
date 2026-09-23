---
name: create-issue
description: Validate one action packet from Sirius intake, resolve its repository from the frozen project table, strip sensitive material, search for duplicates, and create one evidence-backed GitHub Issue. Does not read chat sources or implement anything.
user-invocable: false
---

# Create Issue

Turn one action packet into at most one GitHub Issue. Source skills collect messages; this skill owns every Issue write.

## Tools

Use the authenticated `gh` CLI, or a connected GitHub tool when one is available. Do not use a browser.

## Required input

An action packet in the shape of [the intake contract](../../references/intake-contract.md), plus the frozen project entry from `sirius-config` (repositories, `implement_gate`, notes).

Do not reread Slack or LINE from here. If fields are missing, return `blocked` with what the source skill must collect.

## Validate

Create an Issue only when all of these hold:

1. The work is unresolved and needs tracking.
2. It is within the project's scope.
3. There is enough verified context to state the problem and a completion condition.
4. The repository is decided (see below).
5. The body can be written without secrets or inappropriate private data.

Return `not_actionable` for FYI, acknowledgements, resolved items, success notices, or chat-reply-only items.

## Resolve the repository

Accept only a repository in the project's `repos` list, in this order:

1. an exact `owner/repo` or GitHub URL in the packet that is in the list;
2. the only repository of a single-repository project.

A channel name, chat title, person, or vague product name is not enough. With two or more plausible repositories, return `confirmation_required` and list the candidates with evidence. Never create in a repository outside the project, and never fall back to the current directory.

A project with no repositories returns `blocked: project has no repository`.

## Protect private data

Check repository visibility first with `gh repo view <repo> --json visibility`.

- Always remove credentials, tokens, cookies, private keys, OTPs, passwords, personal addresses, and unrelated conversation. Redact rather than truncate.
- For a public repository, also remove private permalinks, chat titles, customer names, internal hostnames, and excerpts. If what remains is not enough to act on, return `confirmation_required` with the proposed wording.
- Paraphrase instead of quoting.

## Deduplicate

Before creating anything, search open Issues in the target repository for:

- the source permalink or source identifier, when it is safe to search;
- distinctive identifiers (error codes, ticket numbers, deployment names);
- the key terms of the proposed title.

Check recently closed Issues too when the packet may describe a regression. If an open Issue already tracks it, return `duplicate` with its URL and do not comment. If a closed one matches but the problem has recurred, create a new Issue that links the old one.

## Compose

One Issue per independent action. Keep the title outcome-focused and under about 80 characters. Do not prefix it with "Slack" or "LINE".

```md
## Summary
<verified problem or request, and why it matters>

## Evidence
- Observed: <facts, times, errors>
- Source: <minimal safe reference>

## Required action
<the work>

## Acceptance criteria
- [ ] <verifiable result>

## Open questions
- <non-blocking gaps>

<!-- sirius-source: <source>:<stable id hash> -->
```

Mark inferences as inferences. Do not invent acceptance criteria that change the request.

## Title prefix, no labels

Sirius uses no labels. The only state in the title is the `[implement]` prefix, the go-ahead to build.

- `implement_gate: auto`: start the title with `[implement] ` when the packet is an implementation candidate and the acceptance criteria are verifiable. Otherwise leave it off and list what is missing under "Open questions".
- `implement_gate: human`: never add `[implement]`. A person adds it after reading the Issue. The guard hook refuses it from you.

Always pass `-R owner/repo` to `gh issue create`, so the guard can check the project's gate.

Assign only an explicit GitHub login from the packet.

## Create and verify

Create with `gh issue create`, then re-fetch it and confirm the repository, number, state, title, and URL. Never report `created` before this check passes.

## Return exactly one status

```yaml
status: created | duplicate | not_actionable | confirmation_required | blocked
repo: <owner/repo>
issue: <number and URL>          # created, duplicate
reason: <short evidence>         # not_actionable, blocked
confirmation_id: <stable id>     # confirmation_required
question: <one question>
options: [{value: <choice>, evidence: <why>}]
pending_packet: <the unchanged packet>
```

For `confirmation_required`, stop without searching further or composing anything. If the user chooses to skip, the next call returns `not_actionable` with reason `user_skipped`.
