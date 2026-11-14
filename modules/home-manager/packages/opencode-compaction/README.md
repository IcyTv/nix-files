# OpenAI context budget (OpenCode V2)

Local server-only plugin. Requires the host's external `@opencode/plugin` V2 SDK;
verified against **2.2.7**. No legacy `@opencode-ai/plugin`, extra runtime dependency,
provider configuration change, or replacement of native automatic compaction.

## User controls

Commands affect only the invoking session, persist in plugin storage across reloads,
and never change another session or its parent. Forks start with default controls,
not the source session's overrides (copied history can still cross a threshold).

```text
/context-budget status
/context-budget hard 600000
/context-budget soft off
/context-budget soft on
/context-budget hard off
/context-budget hard on
/context-budget reset
```

Defaults: advisory on at **240,000 input tokens**; automatic fallback on at
**500,000 input tokens**. Limits are inclusive. Hard counts must be positive safe
integers. Soft and hard switches are independent. `reset` restores defaults and
clears a failure latch; `hard on` and setting a new hard count also explicitly rearm
a failed attempt. Disabling/resetting cannot cancel a control already admitted by
OpenCode. Only user commands change settings. The model gets a no-argument
`context_compact` tool; it uses the executor's session, never a supplied session ID,
and never edits limits. It works even when both automatic controls are off.

**Command acknowledgement:** V2 server command executors return `void`, not display
text. This plugin queues a synthetic status notice with `resume: false`, using the
command's delivery mode. The notice is visible as queued input and enters history
at the next delivery boundary. It does **not wake an idle session** or call
`prompt`/`generate`; an already active execution can consume it normally. This is
not an immediate toast or command stdout. Avoid repeatedly running `status` while
the model is busy if you do not want extra notices in its pending context.

## Accounting and timing

The context hook has no exact token count for the assembled outgoing request.
We use the **latest completed, successful primary assistant request** from
`session.context`, not cumulative `session.tokens`, history totals, or a token
estimate. Stored V2 `TokenUsage.Info` separates non-cached `input`, `cache.read`,
and `cache.write`: add those three exactly once; exclude `output` and `reasoning`.
Compaction/title/generate usage is not primary assistant usage. A newer model
selection invalidates older usage; non-OpenAI usage never triggers these controls.
Until a fresh request completes after a switch/checkpoint, input is unknown.

Evidence: published `@opencode/core@2.2.7`, `src/session/usage.ts` (distributed in
`dist/chunks/skill-4f25tdd0.js`), maps `nonCachedInputTokens` to `tokens.input` and
maps cached reads/writes separately. `@opencode/schema@2.2.7` defines assistant
completion timestamps and separate compaction messages. The SDK's context hook
does not contain usage. `sdk-contract.test.js` validates fixtures against the real
encoded V2 schemas; strict `checkJs` checks the adapter against the real SDK.

The soft advisory is injected once per checkpoint into the next OpenAI primary
model request. It recommends compaction at the next safe milestone **unless the
user asked otherwise**, rather than interrupting ongoing work. No extra model
request is created for the advisory. Switching providers does not repeatedly
reset the advisory. Returning to OpenAI needs fresh OpenAI usage.

Hard checks run before primary model calls and after step-completion events.
`session.compact` only admits a control and returns immediately; OpenCode runs it
at the next safe step boundary, before waiting prompts. This is **not a strict
spend ceiling**: usage lags, a request can already be in flight, and native auto
compaction may run earlier. This plugin does not alter native compaction settings.

Admission/pending/failure gates persist before enqueueing. A server-wide session
lock serializes read/modify/write operations across location instances and module
reloads; different sessions remain independent. Unchanged inspections do not write
storage. This assumes one OpenCode server owns a session, not distributed access
from independent server processes. OpenCode also merges concurrent compaction
controls. Summary requests
do not run the primary context hook. Failed admission or compaction requires an
explicit user rearm, not automatic retries. After success, a fresh primary request
below the hard threshold must rearm automation; oversized fixed instructions cannot
cause an endless compact/continue loop. Old retained assistant usage and the summary
request's own large input do not immediately retrigger compaction.

Global event handlers reject foreign directory/workspace references and check the
session's current directory before touching budget state, including cancellation
events. Events without location metadata are ignored: `session.get` exposes only a
public directory reference and cannot distinguish workspaces at the same directory.
Primary context hooks still check budgets normally, so an unscoped completion event
can delay the hard check until the next primary call. A stale event from a session
moved to another directory is ignored.

A successful native/manual checkpoint also clears an earlier failure latch; it
still needs fresh low-input usage before another automatic attempt.

Cancelled plugin controls also latch until user rearm. Reload recovers completion
and failure from context; a pending admission stays conservatively latched. If a
control was cancelled while the plugin was unloaded (so its cancellation event was
missed), request native `/compact` once to establish a fresh checkpoint. No timer
or automatic retry guesses whether an uncertain admission succeeded.

## Focused checks

```sh
node --test budget.test.js
# With @opencode/plugin@2.2.7 and @types/node installed for development:
node --test sdk-contract.test.js
tsc --allowJs --checkJs --noEmit --strict --target es2023 --module nodenext \
  --skipLibCheck index.js budget.js
```

The Nix derivation installs only source, runs syntax/core tests, and leaves the SDK
external for OpenCode to supply. No activation is needed to build or test it.
