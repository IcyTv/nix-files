{
  config,
  lib,
  ...
}: let
  agyTiers = {
    fast = {
      model = "google-agy/gemini-3.8-flash";
      readOnly = true;
      costRatio = 1;
      steps = 30;
    };
    medium = {
      model = "google-agy/claude-sonnet-5-5";
      costRatio = 5;
      steps = 50;
    };
    heavy = {
      model = "google-agy/claude-opus-5-5";
      costRatio = 20;
      steps = 120;
    };
  };
  # Match common direct, absolute-path, and command-wrapper spellings.
  # These checks are guardrails, not a shell sandbox or an exhaustive parser.
  commandPatterns = command: ["${command} *" "*/${command} *" "* ${command} *"];
  approvalCommands = [
    "sudo"
    "doas"
    "su"
    "git reset"
    "git restore"
    "git checkout"
    "git clean"
    "git push"
    "git branch -D"
    "git stash drop"
    "git stash clear"
    # Git accepts global flags before its subcommand, such as -C <directory>.
    "git * reset"
    "git * restore"
    "git * checkout"
    "git * clean"
    "git * push"
    "git * branch -D"
    "git * stash drop"
    "git * stash clear"
  ];
in {
  config = lib.mkIf config.my.hm.ai.enable {
    programs.opencode.settings = {
      plugins = ["opencode-model-router@2.9.1"];

      # The router's read-only fast tier denies tools by default. Grant only
      # lazy skill loading; keep shell, edits, Code Mode, and delegation denied.
      agents.fast.permissions = [
        # Host config rules are appended after the router's read-only policy.
        # Do not let shared shell approval rules widen fast to shell access.
        {
          action = "shell";
          resource = "*";
          effect = "deny";
        }
        {
          action = "skill";
          resource = "*";
          effect = "allow";
        }
      ];

      # Policy denies survive agent-level permission overrides and approvals.
      policies = map (pattern: {
        action = "tool.use";
        resource = "shell:${pattern}";
        effect = "deny";
      }) (commandPatterns "rm");

      permissions = map (pattern: {
        action = "shell";
        resource = pattern;
        effect = "ask";
      }) (lib.concatMap commandPatterns approvalCommands);
    };

    # Upstream currently hardcodes ~/.config rather than XDG_CONFIG_HOME.
    home.file.".config/opencode/opencode-model-router.overrides.jsonc".text = builtins.toJSON {
      activePreset = "hybrid-agy-openai";
      activeMode = "normal";
      delegateInstructions = "keep";
      presets = {
        hybrid-agy-openai = {
          inherit (agyTiers) fast;
          medium = {
            model = "openai/gpt-6.1-sol-fast";
            variant = "xhigh";
            costRatio = 5;
            steps = 50;
          };
          heavy = {
            model = "openai/gpt-6-astra-fast";
            variant = "max";
            costRatio = 20;
            steps = 120;
          };
        };
        google-agy = agyTiers;
      };
      # Chains contain preset names, not provider IDs. Do not fall through to
      # upstream providers or the OpenCode catalog (which also has paid models).
      # This controls routing instructions, not provider access permissions.
      fallback.presets = {
        hybrid-agy-openai = {
          openai = ["google-agy"];
          google-agy = [];
        };
        google-agy.google-agy = [];
      };
    };
  };
}
