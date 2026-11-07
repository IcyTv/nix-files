{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.nushell.enable = lib.mkEnableOption "Nushell configuration";

  config = lib.mkIf config.my.hm.nushell.enable {
    programs.pay-respects = {
      enable = true;
      # Home Manager generates `_PR_SHELL: nushell`, but the executable is `nu`.
      enableNushellIntegration = false;
    };

    programs.nushell = {
      extraConfig =
        ''
          def --wrapped niri [...rest] {
              if ($rest | is-empty) and ("WAYLAND_DISPLAY" in $env) {
                  print "🚨 Prevented accidental nested Niri launch!"
                  print "💡 Did you mean \"niri msg ...\" or \"niri --help\"?"
                  print "   (To intentionally force a nested launch, run: ^niri)"
                  error make {msg: "Nested launch prevented"}
              } else {
                  ^niri ...$rest
              }
          }
        ''
        + lib.optionalString config.programs.pay-respects.enable ''
          source ${
            pkgs.runCommand "pay-respects-nushell-config.nu" {} ''
              ${lib.getExe config.programs.pay-respects.package} nu ${lib.escapeShellArgs config.programs.pay-respects.options} > "$out"

              # Backport upstream's SQLite history fix until nixpkgs ships it.
              # Derive the alias from the generated function to preserve custom options.
              alias=$(sed -n '1s/^def --env \([^ ]*\) \[\] {$/\1/p' "$out")
              test -n "$alias"
              substituteInPlace "$out" \
                --replace-fail 'let command = (history | last).command' ${lib.escapeShellArg ''
                let entries = (history | where { |entry| ($entry.command | str trim) != '__pr_alias__' })
                if ($entries | is-empty) { return }
                let command = ($entries | last).command
              ''} \
                --replace-fail '__pr_alias__' "$alias"
            ''
          }
        '';
      enable = true;
      plugins = with pkgs.nushellPlugins; [
        skim
        query
        gstat
      ];
      settings = {
        show_banner = false;
        edit_mode = "vi";
        history = {
          isolation = true;
          sync_on_enter = false;
          file_format = "sqlite";
        };
        completions = {
          case_sensitive = false;
          quick = true;
          partial = true;
          algorithm = "fuzzy";
          external = {
            enable = true;
            max_results = 100;
          };
        };
      };

      shellAliases = {
        nix-shell = "nix-shell --command nu";
      };
    };

    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
    };
  };
}
