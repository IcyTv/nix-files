{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: {
  options.my.hm.zsh.enable = lib.mkEnableOption "Zsh shell configuration and CLI tools";

  config = lib.mkIf config.my.hm.zsh.enable {
    home.shellAliases = {
      cd = "z";
      sysfailed = "systenctl list-units --failed";
      man = "batman";
      cat = "bat";
      bathelp = "bat --plain --language=help";
      # TODO: This isn't great. Surely we can just send a signal or something...
      logout = "sudo systemctl restart greetd";
    };

    programs.zsh = {
      enable = true;
      enableCompletion = false;
      autosuggestion = {
        enable = true;
        strategy = [
          "completion"
          "match_prev_cmd"
          "history"
        ];
      };
      syntaxHighlighting.enable = true;

      historySubstringSearch = {
        enable = true;

        searchUpKey = ["^[[A" "^[OA"];
        searchDownKey = ["^[[B" "^[OB"];
      };

      history.size = 10000;

      plugins = [
        {
          name = "zsh-autocomplete";
          file = "zsh-autocomplete.plugin.zsh";
          src = pkgs.zsh-autocomplete;
        }
        {
          name = "forgit";
          file = "forgit.plugin.zsh";
          src = pkgs.zsh-forgit;
        }
      ];
      shellGlobalAliases = {
        "-h" = "-h 2>&1 | bathelp";
        "--help" = "--help 2>&1 | bathelp";
      };
      shellAliases = {
        ls = "eza --color=auto";
        la = "eza -a";
        ll = "eza -alhF";
        l = "eza";
        lt = "eza -T --git-ignore";
        lT = "eza -T";
        nix-shell = "nix-shell --run zsh";
      };

      initContent = lib.mkOrder 1500 ''
        fastfetch
      '';
    };

    programs.eza = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      icons = "always";
      colors = "auto";
    };

    programs.ripgrep = {
      enable = true;
      arguments = ["--sort=path"];
    };
    programs.ripgrep-all.enable = true;

    programs.bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batdiff
        batman
        prettybat
      ];
    };

    programs.zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.pay-respects = {
      enable = true;
      enableNushellIntegration = true;
    };

    programs.fastfetch = {
      enable = true;
      settings = {
        modules = [
          "title"
          "separator"
          "os"
          "host"
          "kernel"
          "uptime"
          "packages"
          "shell"
          "display"
          "de"
          "wm"
          "wmtheme"
          "theme"
          "icons"
          "font"
          "cursor"
          "terminal"
          "terminalfont"
          "cpu"
          "gpu"
          "memory"
          "swap"
          "disk"
          "localip"
          "battery"
          "poweradapter"
          "break"
          "colors"
        ];
        display.key.type = "both";
      };
    };

    programs.nix-index = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableNushellIntegration = false;
    };

    programs.zellij.enable = true;

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
  };
}
