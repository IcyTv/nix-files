# OmniRoute first run

Pinned source: `cheaper-inference/OmniRoute` commit
`094a1aa1c0b2c54a4c4e3065948b3d4e9c1d0165` (3.8.53).
Build includes the dashboard, not the backend-only/headless profile.
Nix owns dependencies and updates. Runtime npm/npx operations and the dashboard
updater are disabled; do not use the upstream global-install/update commands.
SWC native payloads are fully SHA-512-verified and materialized during the build,
then repaired for Nix. This avoids SWC's cache-owner rejection of Nix sandbox
roots without disabling payload integrity verification or adding runtime installs.

## Staged rollout (manual; source build does not activate)

The first source build does **not** activate Home Manager, start or change a
service, import combos, log in, migrate live data, or send inference traffic.
Activation is a separate, explicitly authorized step. Import the new combo names
**before** activation switches OpenCode's defaults. No code performs live migration.

1. Review and build the source without activating it. Keep the current service,
   database, connections, and OpenCode defaults unchanged during preparation.
2. Use the existing dashboard at <http://127.0.0.1:20128>. If no service exists,
   stop and arrange a separately approved bootstrap that leaves OpenCode defaults
   unchanged; do not activate the new defaults before the combos exist. For first
   onboarding, create a strong dashboard password and keep the listener local,
   never behind a public reverse proxy. Inspect `systemctl --user status omniroute`
   and `journalctl --user -u omniroute` if startup fails.
3. Check **every** new name below against the dashboard before importing anything:
   `orchestrator`, `exploration`, `research`, `mechanical`, `implementation`,
   `verification`, `architecture`, `review`, `implementation-deep`,
   `architecture-deep`, `review-deep`, and `cloudflare-free`. Merge **skips** existing
   names; it does not update their definitions. On any collision, stop and report
   it for a reviewed resolution. Do not overwrite the database, replace definitions,
   or delete old combos to force migration. Retain old `role-*` router combos, but
   OpenCode no longer declares `role-*` models. Keeping database combos alone does
   **not** preserve session model compatibility: sessions pinned to old IDs must
   manually reselect a supported model, and select their agent independently.
4. Add or retain **Antigravity** and **Codex** separately through their manual OAuth
   flows. Confirm live inventory and subscription entitlement for the targets
   below **before any separately authorized inference tests**. Static catalog
   presence is not account access, quota, reliability, or billing proof. Do not copy
   OpenCode credentials, enable Google credits, or add paid API-key providers.
   The launcher uses upstream bootstrap for generated secrets. If OAuth client
   configuration needs an override, set it privately in
   `$XDG_DATA_HOME/omniroute/.env` (normally `~/.local/share/omniroute/.env`), never
   in Nix or chat. The optional public OAuth-client warning can appear even when
   the catalog's built-in public defaults work.
5. After the collision check, import the reviewed, secret-free seed from the
   unactivated built Home Manager generation at
   `<generation>/home-files/.config/omniroute/role-combos.json` using the dashboard's
   **merge** mode, or manually create the reviewed new combos. Do not activate to
   obtain this file. The installed seed path remains
   `~/.config/omniroute/role-combos.json` for compatibility; that filename does not
   prefix combo IDs. The portable format
   is `omniroute-combos-v1`, not a settings/credentials backup. Do not rely on the
   currently installed file containing this build's new seed. Confirm all imported
   names and target orders before authorizing activation.
6. Only after the new combos exist, activate Home Manager through the separately
   approved workflow. Activation installs the config and user service, and selects
   `orchestrator` with `omniroute/orchestrator` as the defaults for new sessions.
   If needed, manually create an OmniRoute inference key, run OpenCode `/connect`,
   select **OmniRoute**, and enter the key there. Never put keys in chat or Nix.
   Existing sessions retain agent and model independently: manually select the
   `orchestrator` agent **and separately** use `/models` to select
   `omniroute/orchestrator`. Selecting only the agent does not switch the model.
   Existing direct providers/plugins remain available for manual use, never to
   bypass denials, role boundaries, or authorization.

## Managed routes and budgets

All combos use explicit priority order, `maxRetries = 0`, `maxGlobalAttempts = 6`,
and compression off. Allowed providers derive only from each combo's targets.

| Combo | Targets in priority order |
| --- | --- |
| `orchestrator` | `codex/gpt-6.1-sol-medium` → `antigravity/claude-sonnet-5-5-medium` |
| `exploration`, `research` | `antigravity/gemini-3.8-flash-medium` → `codex/gpt-6-luna-medium` |
| `mechanical`, `verification` | `codex/gpt-6-luna-low` → `codex/gpt-6.1-sol-medium` |
| `implementation` | `codex/gpt-6.1-sol-medium` → `antigravity/claude-sonnet-5-5-medium` |
| `architecture` | `codex/gpt-6-astra-high` → `antigravity/gemini-4-argon-high` → `antigravity/claude-opus-5-5-high` |
| `review` | `antigravity/gemini-4-argon-high` → `antigravity/claude-opus-5-5-high` → `codex/gpt-6-astra-high` |
| `implementation-deep` | `codex/gpt-6.1-sol-xhigh` → `antigravity/claude-sonnet-5-5-high` |
| `architecture-deep` | `codex/gpt-6-astra-max` → `antigravity/gemini-4-argon-high` → `antigravity/claude-opus-5-5-high` |
| `review-deep` | `codex/gpt-6-astra-max` → `antigravity/claude-opus-5-5-high` → `antigravity/gemini-4-argon-high` |
| `cloudflare-free` | `cloudflare-ai/@cf/zai-org/glm-4.7-flash` only |

Core routes advertise tools, text/image input, text output, and an OmniRoute
`context_length` of **872,000**. OpenCode budgets are context **872,000**, input
**839,232**, output **32,768**. These reflect the pinned route floor and configured
output reserve, not public API limits, account entitlement, or successful testing.
The local **500,000-token policy** is separate from these model budgets: OmniRoute
compaction remains advisory and model-called, not a plugin-enforced hard boundary.
Direct-provider policy remains unchanged; see the compaction package documentation
for its implementation details.

Balanced roles are the default. Choose `implementer-deep`, `architect-deep`, or
`reviewer-deep` only with a stated task-specific reason that normal effort is
insufficient or complexity requires it. No automatic error-driven escalation,
model overrides, or permission changes accompany these roles. Genuine budget stops
continue the same session and role. At this pin, Codex `reasoningPolicy` gives the
target ID's effort suffix precedence over request effort; native variants are not
an override for these routes.

Flash and Cloudflare routes remain untested here. No configured route is quota or
reliability proof. Hydrogen stays absent pending its real inventory ID and quota
family. No Groq, OpenRouter, or Gemini API provider is added.

### Optional Cloudflare Free route (manual only)

`cloudflare-free` advertises tools with text-only input/output, context **131,072**,
input **122,880**, and output **8,192**. These are configured budgets, not published
maxima. [Cloudflare's model documentation](https://developers.cloudflare.com/workers-ai/models/glm-4.7-flash/)
advertises function calling, but the pinned OmniRoute registry lacks a `toolCalling`
flag; end-to-end gateway tool delivery remains untested. No native role, default,
or core fallback selects Cloudflare. Its Free
allowance is **10,000 Neurons/day**, not unlimited usage. Do not enable a paid
upgrade. Account and token setup is manual only, through private provider setup;
never put keys in chat or configuration. This source change does not authenticate
or test the route.

### Existing Copilot connection (deferred)

Preserve the already connected GitHub Copilot account. No Copilot model entry or
traffic is enabled here. Defer `github/auto` to separately authorized discovery and
tests, and policy/privacy/budget acceptance. Consider only Free/Student Auto; do
not assume paid plans, quotas, routing, or entitlement from the connection alone.

## Runtime data

`DATA_DIR` is Home Manager's `xdg.dataHome` plus `/omniroute`. It holds SQLite,
OAuth tokens, `server.env` (generated JWT/storage/key-signing secrets), and a
Nix-output-specific symlink runtime tree, so same-commit package fixes get a new
runtime directory. The service uses umask 0077. Back up
SQLite and its encryption secrets together. Never delete or regenerate secrets
to repair an existing encrypted database. Old runtime directories are not
automatically removed or replaced; interrupted staging directories may remain.

The `omniroute` executable is a foreground launcher, not upstream's interactive
CLI. The dashboard handles login, combos, keys, and quota inspection.

## Accepted upstream limitations

Core roles use explicit PRIORITY targets only from Antigravity and Codex OAuth.
The separate manual-only Cloudflare route is restricted to the configured Free
model; its presence does not enforce account billing. There is no auto/thrifty
ladder. None of this guarantees correct quota accounting, free usage, or provider
approval. Google credits are off. OAuth subscription routing may violate provider
terms. Catalog hard-stop labels are not evidence of account billing behavior.

At this pin, `gemini-4*` is classified as Argon (a Hydrogen hazard); GPT-OSS is
missing from the Claude quota family; generic Argon aggregation includes
unrelated windows; subscription-ladder connection-wide minima can reject a
different pool with remaining capacity; auto/thrifty rung budgets are not
enforced; and the reset cooldown clamp is unwired. These are documented, not
fixed here. Review live inventories and quota reports skeptically.
