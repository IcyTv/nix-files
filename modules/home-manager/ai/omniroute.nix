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
  lunaLow = target "codex" "gpt-6-luna-low";
  lunaMedium = target "codex" "gpt-6-luna-medium";
  solMedium = target "codex" "gpt-6.1-sol-medium";
  solDeep = target "codex" "gpt-6.1-sol-xhigh";
  astraHigh = target "codex" "gpt-6-astra-high";
  astraDeep = target "codex" "gpt-6-astra-max";
  flash = target "antigravity" "gemini-3.8-flash-medium";
  argon = target "antigravity" "gemini-4-argon-high";
  sonnetMedium = target "antigravity" "claude-sonnet-5-5-medium";
  sonnetHigh = target "antigravity" "claude-sonnet-5-5-high";
  opus = target "antigravity" "claude-opus-5-5-high";
  cloudflare = target "cloudflare-ai" "@cf/zai-org/glm-4.7-flash";
  # Target IDs/efforts: pinned open-sse/config/providers/registry/codex/index.ts
  # and open-sse/config/antigravitySharedModels.ts. Confirm live account inventory.
  # Hydrogen intentionally absent: discover its real ID before enabling it.
  # Upstream classifies the entire gemini-4 prefix as Argon (Hydrogen hazard).
  # GPT-OSS is missing from the Claude quota family; do not use it as a fallback.
  coreProfile = {
    capabilities = {
      tools = true;
      input = ["text" "image"];
      output = ["text"];
    };
    # Context follows the pinned route floor; input reserves configured output.
    # Not public API or account proof. Target ID suffixes select reasoning effort.
    limit = {
      context = 872000;
      input = 839232;
      output = 32768;
    };
  };
  cloudflareProfile = {
    capabilities = {
      # Cloudflare advertises function calling; the pinned OmniRoute registry
      # lacks toolCalling. End-to-end gateway tool delivery remains untested.
      tools = true;
      input = ["text"];
      output = ["text"];
    };
    # Configured budgets, not published model maxima.
    limit = {
      context = 131072;
      input = 122880;
      output = 8192;
    };
  };
  combo = profile: name: models: {
    inherit name models;
    strategy = "priority";
    allowedProviders = lib.unique (map (entry: entry.providerId) models);
    context_length = profile.limit.context;
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
  coreCombo = combo coreProfile;
  coreCombos = [
    (coreCombo "orchestrator" [solMedium sonnetMedium])
    (coreCombo "exploration" [flash lunaMedium])
    (coreCombo "research" [flash lunaMedium])
    (coreCombo "mechanical" [lunaLow solMedium])
    (coreCombo "implementation" [solMedium sonnetMedium])
    (coreCombo "verification" [lunaLow solMedium])
    (coreCombo "architecture" [astraHigh argon opus])
    (coreCombo "review" [argon opus astraHigh])
    (coreCombo "implementation-deep" [solDeep sonnetHigh])
    (coreCombo "architecture-deep" [astraDeep argon opus])
    (coreCombo "review-deep" [astraDeep opus argon])
  ];
  # Manual-only free route; never a native role default or subscription fallback.
  combos = coreCombos ++ [(combo cloudflareProfile "cloudflare-free" [cloudflare])];
  model = profile: name: {name = "OmniRoute ${name}";} // profile;
in {
  config = lib.mkIf config.my.hm.ai.enable {
    home.packages = [omniroute];
    systemd.user.services.omniroute = {
      Unit = {
        Description = "OmniRoute local inference routes and dashboard";
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
      name = "OmniRoute (local routes)";
      package = "@opencode/ai/providers/openai-compatible";
      settings.baseURL = "http://127.0.0.1:20128/v1";
      # No key or auth-file interpolation: create a key and use /connect manually.
      models =
        lib.listToAttrs (map (entry: lib.nameValuePair entry.name (model coreProfile entry.name)) coreCombos)
        // {cloudflare-free = model cloudflareProfile "cloudflare-free";};
    };
  };
}
