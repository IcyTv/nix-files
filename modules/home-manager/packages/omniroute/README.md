# OmniRoute first run

Pinned source: `cheaper-inference/OmniRoute` commit
`094a1aa1c0b2c54a4c4e3065948b3d4e9c1d0165` (3.8.53).
Build includes the dashboard, not the backend-only/headless profile.
Nix owns dependencies and updates. Runtime npm/npx operations and the dashboard
updater are disabled; do not use the upstream global-install/update commands.
SWC native payloads are fully SHA-512-verified and materialized during the build,
then repaired for Nix. This avoids SWC's cache-owner rejection of Nix sandbox
roots without disabling payload integrity verification or adding runtime installs.

## Setup (manual, after reviewing/building this change)

1. Apply Home Manager through your usual activation workflow. This installs and
   starts `omniroute.service` for your user. No activation or login is performed
   by this migration. Inspect `systemctl --user status omniroute` and
   `journalctl --user -u omniroute` if startup fails.
2. Open <http://127.0.0.1:20128>. Complete onboarding and create a strong dashboard
   password. Keep the listener local; do not publish it through a reverse proxy.
3. Add **Antigravity** and **Codex** separately using their OAuth login flows.
   Do not add paid API-key providers, copy OpenCode credentials, or enable Google
   credits. The launcher uses upstream bootstrap for generated secrets. If your
   OAuth client configuration needs an override, set it privately in
   `$XDG_DATA_HOME/omniroute/.env` (normally `~/.local/share/omniroute/.env`),
   never in Nix. The bootstrap warning about optional public OAuth client
   credentials can appear even when the catalog's built-in public defaults work.
4. Confirm both connections' live model inventory and subscription entitlement
   **before inference**. Expected IDs: Codex `gpt-6-luna-high`,
   `gpt-6.1-sol-xhigh`, `gpt-6-astra-max`; Antigravity `gemini-4-argon-high`,
   `claude-sonnet-5-5-high`, `claude-opus-5-5-high`. Static catalog presence is not
   evidence that your account can use a model. Hydrogen is intentionally absent
   until its actual inventory ID and quota family are confirmed.
5. In the dashboard's Combos import UI, import
   `~/.config/omniroute/role-combos.json` using **merge**. This is a secret-free
   `omniroute-combos-v1` portable file, not a full settings/credentials backup.
   Merge skips names already present; it does **not** update existing definitions.
   Review and update existing combos manually when changing this seed. Never use
   replace mode or delete the database to apply a configuration update.
6. Create an inference API key in OmniRoute. In OpenCode run `/connect`, select
   the configured **OmniRoute** provider, and enter that key manually. Use
   `/models` to select `omniroute/role-implementation` if an existing session
   retains its previous model. No key is embedded or copied by Nix. Existing
   direct providers/plugins remain available as a manual escape hatch.

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

The seed uses explicit PRIORITY targets only from the Antigravity and Codex OAuth
providers. It contains no paid/metered targets and no auto/thrifty ladder. This
does not guarantee correct quota accounting, free usage, or provider approval.
Google credits are off. OAuth subscription routing may violate provider terms.
Catalog hard-stop labels are not evidence of account billing behavior.

At this pin, `gemini-4*` is classified as Argon (a Hydrogen hazard); GPT-OSS is
missing from the Claude quota family; generic Argon aggregation includes
unrelated windows; subscription-ladder connection-wide minima can reject a
different pool with remaining capacity; auto/thrifty rung budgets are not
enforced; and the reset cooldown clamp is unwired. These are documented, not
fixed here. Review live inventories and quota reports skeptically.
