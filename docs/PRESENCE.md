# Presence: what the chat shows while the agent works

Measured against the user's own `claude` (haiku, `--include-partial-messages`), timed from the
moment the message is sent. Reproduce with:

    .build/debug/Nook --engine-test <folder> --say='…' --model=haiku --auto-allow

which prints `FIRST PRESENCE` (anything at all to look at) and `FIRST REPLY TOKEN` (all Nook used
to show), then a `presence:` summary line.

| turn (haiku, one Read + one Bash)        | first anything | first reply token |
|------------------------------------------|---------------:|------------------:|
| before: only `text_delta` was rendered   |          6.82s |             6.82s |
| after: thinking and tool rows stream too |      **1.98s** |             6.82s |

The stream already carried all of it: `content_block_start {thinking}` at ~1.9s, the `tool_use`
block and its `input_json_delta`s from ~2.7s, the tool result at ~3.8s. Nook dropped every one of
those events and waited for the reply.

## What the CLI actually sends

- `thinking_delta.thinking` is normally **empty**: the reasoning text is withheld. The size is
  reported instead, as `estimated_tokens` on the delta and as `system/thinking_tokens` events, so
  the thinking row shows a token count when it has no text to show. Ignore `signature_delta`.
- A `tool_use` block starts with an empty `input`; the argument arrives as `input_json_delta`
  fragments that cut anywhere, including mid-string and mid-escape (`PartialJSON`).
- The result comes back on a `user` event as `tool_use_result`, whose shape depends on the tool:
  `{stdout, stderr, interrupted}`, `{file: {numLines…}}`, `{numFiles, numLines, filenames}`,
  `{filePath, structuredPatch}`, … `ToolReport` summarises each into one line; failure is the
  `is_error` flag on the `tool_result` block.
- Tools can run in parallel: two `content_block_start`s before either result. Rows are keyed by
  tool id, not by order.

## Type-ahead

Verified live: a user message written to stdin **while a turn is running is accepted**. The CLI
folds it into the running turn and the model reads it at its next step — in one test, a message
sent at 2.5s during a `sleep 5` reached the model at 7.3s and changed the reply. Nothing is lost
and no second turn is started.

So Nook sends type-ahead immediately, and the log marks it "sent mid-turn; the agent reads it at
its next step" rather than pretending it arrived instantly.

The one exception is an open permission question: the CLI is not reading stdin then. Those
messages wait in `AgentSession.queue`, shown as a pill under the log with a ✕ that cancels them,
and go the moment the question is answered (verified with `--meanwhile` plus `--allow-after`).
