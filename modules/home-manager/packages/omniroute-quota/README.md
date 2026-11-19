# OmniRoute quota adapter

Dependency-free Node 24 service for the OpenCode quota plugin's `quota-v1`
HTTP source. Listens only on `127.0.0.1:20129`; reads OmniRoute only at
`http://127.0.0.1:20128`. It does not proxy inference, expose management APIs,
track spend/credits, or determine which account will serve the next request.

## Private credential provisioning

Create a **separate management-scope key** manually in the OmniRoute dashboard.
Do not reuse the inference key that OpenCode sends to OmniRoute. Keep the
management key outside Git, Nix expressions, the Nix store, environment values,
command arguments, and shell history.

Prepare a private directory and empty key file:

```sh
install -d -m 700 ~/.config/omniroute
install -m 600 /dev/null ~/.config/omniroute/quota-management.key
```

Run the file creation command only for initial provisioning: it overwrites an
existing file. Use a local editor to place the raw key in that file, without
quotes or a `Bearer` prefix. Do not paste the key into shell commands. Ensure
editor backups also remain private. The adapter rejects symlinks, nonregular
files, foreign ownership, and any group/world permission bits.

Set these **paths**, never the key itself, in the user service environment:

- `OMNIROUTE_QUOTA_KEY_FILE`: absolute path to the private key file above.
- `OMNIROUTE_QUOTA_COMBOS_FILE`: path to the Nix-generated JSON array of allowed
  combo names, for example `["orchestrator"]`. This contains no credentials.

Start the user service only after provisioning. This package does not activate
or start services. Restart after rotating the key or changing the allowlist.

## HTTP contract

Only `GET /combos/<percent-encoded-allowed-name>` is supported. Requests must use
`Host: 127.0.0.1:20129`. Browser `Origin` headers, foreign hosts, other methods,
queries, extra path segments, and unknown combos are rejected. No CORS headers
are emitted. Inbound `Authorization` is ignored, never logged or forwarded.
There is no generic proxy endpoint. Loopback is not authentication against other
local users; returned account-wide quota percentages should not be considered
private from other processes on this machine.

Responses have exactly the root keys `version` and `entries`:

```json
{"version":"quota-v1","entries":[{"name":"Quota","label":"Shared account quota","kind":"value","resultType":"status","value":"Unavailable: metadata refresh pending or failed"}]}
```

Rows contain either `kind: "percent"`, `resultType: "quota"`, and
`percentRemaining`, or `kind: "value"`, `resultType: "status"`, and `value`.
Optional observation/reset timestamps appear only when valid. Strings are
bounded and stripped of control and formatting characters. Responses contain
1–100 rows; truncation emits an explicit status row. Account labels use stable
ordinals sorted by connection ID, not names or emails. Ordinals may shift when
accounts are added or removed. Labels explicitly refer to shared account quota,
not an active route or a guarantee of account availability.

## Cache and routing limits

First request starts lazy metadata fetch and returns unavailable immediately.
Shared metadata TTL is 60 seconds; errors fail closed. Metadata lists are
paginated using `limit=100&offset=...`, require a consistent `total`, and reject
incomplete, repeated, oversized, or unsupported lists. Limits are 512 records
and ten pages per endpoint. Each upstream response is limited to 2 MiB and an
absolute five-second deadline. Redirects are rejected.

Quota cache reads retain the upstream `fetchedAt`; they never become fresh
merely because the adapter read them. Relevant active accounts refresh in the
background only when absent, timestamp-unknown, or older than five minutes.
Two requests may run concurrently. Refresh work deduplicates by account across
combos. Failed refreshes wait at least 60 seconds before retrying. Successful
refreshes wait at least five minutes. Requests return cached/stale rows or
unavailable while work runs. Stale age is visible in each label. Missing
`fetchedAt` remains age-unknown, including after a live fetch; the adapter never
invents an observation timestamp. No scheduled upstream polling occurs.

Nested combos resolve to depth ten; cycles and ambiguous names fail closed.
Targets must be structured objects with `model` and `providerId`, optionally
`connectionId` and/or `allowedConnectionIds`. A null `connectionId` means no
pin. Explicit account pins and allowlists intersect, as do combo
`allowedProviders`. Models may be bare names or qualified with their exact
`${providerId}/` prefix; mismatched prefixes and wildcards fail closed.
Normalized model targets may include `kind: "model"`. Nested references use
`kind: "combo-ref"` and `comboName`. Both shapes accept validated metadata:
`id` and `label` strings and finite numeric `weight` from 0 through 100.
Plain strings and unsupported target filters/tags fail closed, never widening
account selection. Unsupported provider/model mappings produce
unavailable rows. Same account/family/window deduplicates across targets;
different accounts remain separate.

Mappings are deliberately narrow:

- Codex managed `gpt-` models: exact `session` and `weekly` windows with normalized
  total 100. Spark, code-review, reserve, other windows, and unknown models are
  excluded. Missing windows are unavailable, never full.
- Antigravity `gemini-4*` or models containing `argon`: only
  `gemini_4_argon_weekly` or `argon_weekly`; never unrelated Gemini quotas.
- Antigravity `claude-*`/`cloud-*`: `claude_gpt_session` and `claude_gpt_weekly`.
- Other Antigravity `gemini-*`: `gemini_session` and `gemini_weekly`.

Finite provider percentages take precedence, then validated remaining/total or
(total-used)/total. `fractionReported: false` and `quotaSource:
"localUsageHistory"` estimates remain unknown. Provider-reported unlimited is
text, not 100%. Unsupported quota payload shapes also remain unavailable.
Provider quota refresh/OAuth handling stays inside OmniRoute.

Configure the quota plugin to select this HTTP source for each exact combo
model. The plugin's `onlyCurrentModel` setting is global: enabling it also
changes visibility of other configured quota sources. This adapter cannot
provide request-level account routing or guarantee account availability.

## Development

No npm install, dependencies, or lock file are required:

```sh
node --check index.js
node --check quota.js
node --test *.test.js
```

The Nix package runs syntax checks and fixture tests during `checkPhase`.
Tests use fake credentials and an ephemeral loopback HTTP server, not live
OmniRoute or provider APIs. Credential permission tests leave their small
fixtures in the build/test temporary directory for sandbox cleanup.
