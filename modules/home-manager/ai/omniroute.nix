{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  omniroute = unstable.callPackage ../packages/omniroute {};
  dataDir = "${config.xdg.dataHome}/omniroute";
  target = provider: model: {
    inherit model;
    providerId = provider;
  };
  luna = target "codex" "gpt-6-luna-high";
  sol = target "codex" "gpt-6.1-sol-xhigh";
  astra = target "codex" "gpt-6-astra-max";
  argon = target "antigravity" "gemini-4-argon-high";
  sonnet = target "antigravity" "claude-sonnet-5-5-high";
  opus = target "antigravity" "claude-opus-5-5-high";
  # Target IDs/efforts: pinned open-sse/config/providers/registry/codex/index.ts
  # and open-sse/config/antigravitySharedModels.ts. Confirm live account inventory.
  # Hydrogen intentionally absent: discover its real ID before enabling it.
  # Upstream classifies the entire gemini-4 prefix as Argon (Hydrogen hazard).
  # GPT-OSS is missing from the Claude quota family; do not use it as a fallback.
  combo = name: models: {
    name = "role-${name}";
    inherit models;
    strategy = "priority";
    allowedProviders = ["codex" "antigravity"];
    context_length = 200000;
    config = {
      maxRetries = 0;
      maxGlobalAttempts = 6;
      compressionMode = "off";
      # No auto/thrifty routing: upstream rung budgets are not enforced.
      # Reset cooldown clamp is unwired. Generic Argon aggregation includes
      # unrelated windows; subscription-ladder connection-wide minima can
      # reject another model pool that still has capacity. Not quota guarantees.
    };
  };
  combos = [
    (combo "exploration" [luna])
    (combo "research" [luna])
    (combo "mechanical" [luna sol])
    (combo "implementation" [sol sonnet])
    (combo "architecture" [astra argon opus])
    (combo "review" [argon opus astra])
    (combo "verification" [luna sol])
  ];
  model = name: {
    name = "OmniRoute ${name}";
    capabilities = {
      tools = true;
      input = ["text" "image"];
      output = ["text"];
    };
    # Below every fallback's pinned limits. Leave reasoning to target ID suffixes.
    limit = {
      context = 200000;
      input = 167232;
      output = 32768;
    };
  };
in {
  config = lib.mkIf config.my.hm.ai.enable {
    home.packages = [omniroute];
    systemd.user.services.omniroute = {
      Unit = {
        Description = "OmniRoute local subscription inference and dashboard";
        After = ["network.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${omniroute}/bin/omniroute";
        Environment = [
          "NODE_ENV=production"
          "HOSTNAME=127.0.0.1"
          "OMNIROUTE_HOSTNAME=127.0.0.1"
          "PORT=20128"
          "DASHBOARD_PORT=20128"
          "DATA_DIR=${dataDir}"
          "REQUIRE_API_KEY=true"
          "OMNIROUTE_HEADLESS=0"
          "LIVE_WS_HOST=127.0.0.1"
          "EMBED_WS_PROXY_HOST=127.0.0.1"
          "API_HOST=127.0.0.1"
          # OAuth subscription use can violate provider terms. Credits off is
          # not account billing proof; hard-stop catalog labels are not either.
          "ANTIGRAVITY_CREDITS=off"
          "OMNIROUTE_NO_UPDATE_NOTIFIER=1"
          "NEXT_TELEMETRY_DISABLED=1"
        ];
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 45;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
      Install.WantedBy = ["default.target"];
    };
    # Portable API schema: src/lib/combos/portable.ts + createComboSchema.
    # Import explicitly. Merge skips existing names; never replace a user's DB.
    xdg.configFile."omniroute/role-combos.json".text = builtins.toJSON {
      _meta.version = "omniroute-combos-v1";
      mode = "merge";
      inherit combos;
    };
    programs.opencode.settings.providers.omniroute = {
      name = "OmniRoute (local OAuth subscriptions)";
      package = "@opencode/ai/providers/openai-compatible";
      settings.baseURL = "http://127.0.0.1:20128/v1";
      # No key or auth-file interpolation: create a key and use /connect manually.
      models = lib.listToAttrs (map (entry: lib.nameValuePair entry.name (model entry.name)) combos);
    };
  };
}
