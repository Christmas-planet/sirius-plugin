---
name: intake-slack
description: Read the Slack channels listed in ~/.sirius/projects/*.yaml for a frozen time window and turn unresolved requests into deduplicated GitHub Issues through create-issue. Called by the Sirius run skill; also usable alone for one project.
user-invocable: false
---

# Slack intake

Read [the intake contract](../../references/intake-contract.md) completely first. It defines scope, checkpoints, confirmations, candidate rules, and the action packet. This file adds only what is specific to Slack.

## Tools

1. Prefer a connected Slack connector or MCP server (search and read tools for channels and threads).
2. If no connector reaches a listed workspace, report that workspace as `unavailable`. Do not switch to desktop screen control unless the operator's own skills for it are installed and the user asked for it.

Slack stays read-only: no posting, reactions, edits, or marking as read.

## Collect

For each `{workspace, channel}` in the frozen table:

1. Read channel history for `last_completed_cutoff < ts <= run_cutoff`, oldest first, following every page cursor.
2. For each message with replies, read the full thread.
3. Catch new replies under older parents: also read history for the previous 30 days and open every thread whose `latest_reply` falls inside the window. When the tool exposes search, a search limited to the channel and the window finds the same replies. Evaluate only the replies inside the window as new; use the older messages as context.
4. Deduplicate by permalink, or by channel ID plus `ts`.
5. Evaluate candidates in order so the scan can stop exactly at a confirmation.

Use channel search for strong identifiers (error codes, ticket numbers, repository URLs) only inside the listed channels.

`resume_cursor` is `{workspace, channel, ts}` of the next unprocessed message.

## Packet specifics

Set `source: slack`, `workspace` to the workspace ID, `conversation` to the channel ID, and `permalink` when the tool returns one. `create-issue` decides whether the permalink may appear in the Issue, depending on repository visibility.
