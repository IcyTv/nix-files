{ pkgs, config, lib, ... }: {
  options.my.hm.nushell.enable = lib.mkEnableOption "Nushell configuration";

  config = lib.mkIf config.my.hm.nushell.enable {
    programs.nushell = {
      extraConfig = ''
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
      '';
      enable = true;
      plugins = with pkgs.nushellPlugins; [
        skim
        query
        gstat
        highlight
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