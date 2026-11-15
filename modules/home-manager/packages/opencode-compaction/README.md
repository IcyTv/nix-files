# OpenAI and OmniRoute context budgets (OpenCode V2)

Local server-only plugin. Requires the host's external `@opencode/plugin` V2 SDK;
verified against **2.2.7**. No legacy `@opencode-ai/plugin`, extra runtime dependency,
provider configuration change, or replacement of native automatic compaction.

## Route policies

| Active route | Advisory input threshold | Plugin automatic fallback by default | Voluntary tool |
| --- | --- | --- | --- |
| Direct `openai`, any model | 240,000 | On at 500,000 | Yes |
| `omniroute`, exact managed core IDs below | 500,000 | **Off** | Yes |
| Other `omniroute` models, including legacy `role-*` combos | None | None; budget controls inactive | Yes |
| Other providers | None | None; budget controls inactive | No |

Managed OmniRoute IDs are exactly `orchestrator`, `exploration`, `research`,
`mechanical`, `implementation`, `verification`, `architecture`, `review`,
`implementation-deep`, `architecture-deep`, and `review-deep`. Their separately
configured metadata is **872,000 context / 839,232 input / 32,768 output**. This
plugin does not change that metadata or infer an upstream model's capacity.
Old `role-*` combos have only 200,000 configured context; they are not large-core
routes. `cloudflare-free` remains a separate 131,072-context route, not a managed
large-core route. There is no Copilot policy entry.

At 500,000 completed input tokens, managed OmniRoute gets advice to preserve a
handoff and **call `context_compact` voluntarily at a safe milestone**. The plugin
never automatically queues compaction there unless the user explicitly enables
hard fallback. Native automatic compaction and capacity protection stay unchanged
for every route; these policies are not context guarantees or billing caps.

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

Limits are inclusive and count **input**, including cache, not output. Hard counts
must be positive safe integers. Soft and hard switches are independent. `hard N`
sets a count but does not enable fallback; use `hard on` to opt in on OmniRoute core.
Explicit session toggles and hard counts survive provider/model switches. Without
an explicit override, defaults follow the active route policy above. On unmanaged
routes, status reports no managed budget and controls remain inactive; saved
explicit controls still apply if the session returns to a managed route.

`reset` clears explicit overrides, restores the **current route's** defaults, and
clears a failure latch. `hard on` and setting a new hard count also explicitly
rearm a failed attempt. Disabling/resetting cannot cancel a control already
admitted by OpenCode. Only user commands change settings. The model gets a strict,
no-argument `context_compact` tool; it uses the executor's session, never a supplied
session ID or parent, and never edits limits. It works on all OpenAI and OmniRoute
requests, even smaller/unknown OmniRoute routes and when both controls are off.

Old stored OpenAI settings have no explicit-override markers. Nondefault hard
counts and disabled soft/hard switches remain explicit choices. Old default
`hard: true` is **not** treated as an OmniRoute opt-in: it cannot be distinguished
from an old explicit `hard on`. Such sessions retain direct OpenAI's default on,
but must issue `hard on` again to opt in on OmniRoute. New explicit on/off commands
are marked and survive switches even when equal to current defaults. Read-only
inspection does not force a storage migration or rewrite.

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
selection invalidates older usage. The current provider **and exact model ID** must
match the measured request, both in request hooks and event observers. Until a
fresh request completes after a switch/checkpoint, input is unknown. Unmanaged
routes never trigger advisory or automatic fallback, even with saved overrides.

Request hooks supply the exact resolved model. Outside a request hook, only an
explicit `session.get().model` pin proves policy; the plugin reads it **after**
awaiting history so a switch during that read cannot reuse the old pin. Without a
pin, OpenCode may select a current agent model or its default instead. The plugin
does not duplicate that resolver or treat historical assistant/model-switch
messages as current selection. Event checks therefore fail closed for automation,
and command status says **Current policy unproven** instead of claiming the old
route's defaults are active. Settings remain saved, and request-hook checks still
work once OpenCode supplies the resolved model. History-only observations may
supply fresh-usage evidence for the voluntary retry safety gate, never policy.

Evidence: published `@opencode/core@2.2.7`, `src/session/usage.ts` (distributed in
`dist/chunks/skill-4f25tdd0.js`), maps `nonCachedInputTokens` to `tokens.input` and
maps cached reads/writes separately. The OmniRoute OpenAI-compatible chat path in
`@opencode/ai@2.2.7`, `dist/protocols/openai-compatible-chat.js`, reuses
`openai-chat.js`; its `mapUsage` derives non-cached input by subtracting cache reads
and writes from `prompt_tokens`. Thus stored `input + cache.read + cache.write`
reconstructs inclusive prompt input once. Do **not** add cache again to raw gateway
`prompt_tokens`. `@opencode/schema@2.2.7` defines assistant completion timestamps
and separate compaction messages. The SDK's context hook
does not contain usage. `sdk-contract.test.js` validates fixtures against the real
encoded V2 schemas; strict `checkJs` checks the adapter against the real SDK.

The soft advisory is injected once per checkpoint into the next eligible primary
model request, using that route's threshold. It recommends compaction at the next
safe milestone **unless the user asked otherwise**, rather than interrupting
ongoing work. No extra model request is created for the advisory. Switching
providers/models does not repeatedly reset the advisory. Returning to a route
needs fresh usage matching that provider and model.

Enabled hard checks run before primary model calls and after step-completion events.
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
explicit user rearm, not automatic retries. After success, fresh low-input primary
usage must rearm the attempt gate. This also permits later voluntary compactions
on unmanaged OmniRoute routes: all tool-eligible routes can rearm below the saved
hard count (500,000 by default). On unmanaged routes, that count is **only a retry
safety threshold**, not a budget, capacity claim, advisory, or automatic fallback.
When current selection is unproven, only voluntary retry evidence may use history;
usage must still be newer than the checkpoint/switch and match the latest measured
route. Fresh high input, failure, cancellation, and pending controls keep retry
blocked. Oversized fixed instructions cannot cause an endless compact/continue
loop. Old retained assistant usage and the summary request's own large input do
not immediately retrigger compaction.

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
