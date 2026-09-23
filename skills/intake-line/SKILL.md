---
name: intake-line
description: Read the LINE chats listed in ~/.sirius/projects/*.yaml in the native macOS LINE app for a frozen time window and turn unresolved requests into deduplicated GitHub Issues through create-issue. Called by the Sirius run skill; requires a Mac session with Computer Use.
user-invocable: false
---

# LINE intake

Read [the intake contract](../../references/intake-contract.md) completely first. This file adds only what is specific to LINE.

## Tools and limits

- Use Computer Use on the native macOS LINE app only. Do not use a browser, DOM scraping, OCR of other apps, a database reader, or the LINE Messaging API.
- This needs a local Mac session. In a cloud routine, return `disabled: no desktop` and leave the checkpoint unchanged.
- If Computer Use access to LINE is not granted, return `unavailable` and leave the checkpoint unchanged.

LINE stays read-only: no sending, reactions, unsending, forwarding, calls, downloads, or typing in a composer.

## Collect

1. Before opening anything, note the unread badge count for each listed chat title. Opening a chat can clear it.
2. Open only the chat rows whose title exactly matches a listed title. If two rows match one title, stop that chat and report the ambiguity.
3. After opening, confirm that the chat header shows the exact title.
4. Scroll up until messages are older than `last_completed_cutoff`, then read forward through `run_cutoff`.
5. Deduplicate by chat title, timestamp, sender, and normalized visible text.
6. In group chats, record the sender of every fact that affects interpretation.

LINE has no reliable permalink. `resume_cursor` is `{chat, timestamp, sender, text_hash}` of the next unprocessed message.

## Packet specifics

Set `source: line`, `conversation` to the chat title, `workspace: null`, and `permalink: null`. For private repositories, the Issue may cite the chat title, sender, and time. For public ones, `create-issue` removes them.

Report the unread counts noted before opening, and which badges may have been cleared.
