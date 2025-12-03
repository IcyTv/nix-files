{
  pkgs,
  lib,
  ...
}: {
  home.shellAliases = {
    ls = "eza --color=auto";
    la = "eza -a";
    ll = "eza -alhF";
    l = "eza";
    lt = "eza -T --git-ignore";
    lT = "eza -T";
    "l." = "eza -A | egrep '^\\.''";
    "cd.." = "cd ..";
    cd = "z";
    sysfailed = "systenctl list-units --failed";
    man = "batman";
    cat = "bat";
    bathelp = "bat --plain --language=help";
    nix-shell = "nix-shell --run zsh";
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

    initContent = lib.mkOrder 1500 ''
      fastfetch
    '';
  };

  catppuccin.zsh-syntax-highlighting.enable = true;

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

  catppuccin.starship.enable = true;
  programs.starship = {
    enable = true;
    settings = {
      ## FIRST LINE/ROW: Info & Status

      # First param ─┌
      username = {
        format = " [╭─$user]($style)@";
        style_user = "bold red";
        style_root = "bold red";
        show_always = true;
      };

      # Second param
      hostname = {
        format = "[$hostname]($style) in ";
        style = "bold dimmed red";
        trim_at = "-";
        ssh_only = false;
        disabled = false;
      };

      # Third param
      directory = {
        style = "purple";
        truncation_length = 0;
        truncate_to_repo = true;
        truncation_symbol = "repo: ";
      };

      # Before all the version info (python, nodejs, php, etc.)
      git_status = {
        style = "white";
        ahead = "⇡\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        behind = "⇣\${count}";
        deleted = "x";
      };

      # Last param in the first line/row
      cmd_duration = {
        min_time = 1;
        format = "took [$duration]($style)";
        disabled = false;
      };

      ## SECOND LINE/ROW: Prompt

      # Prompt: optional param 1
      time = {
        format = "  $time($style)\n";
        time_format = "%T";
        style = "bright-white";
        disabled = true;
      };

      # Prompt: param 2 └─
      character = {
        success_symbol = " [╰─λ](bold red)";
        error_symbol = " [×](bold red)";
      };

      # SYMBOLS
      status = {
        symbol = "";
        not_executable_symbol = "";
        sigint_symbol = "";
        signal_symbol = "󱐋";
        format = "[\\\\[$symbol$status_common_meaning$status_signal_name$status_maybe_int\\\\]]($style)";
        map_symbol = true;
        disabled = false;
        style = "bold red";
      };

      aws.symbol = "  ";
      conda.symbol = " ";
      dart.symbol = " ";

      docker_context = {
        symbol = " ";
        format = "via [$symbol$context]($style) ";
        style = "blue bold";
        only_with_files = true;
        detect_files = [
          "docker-compose.yml"
          "docker-compose.yaml"
          "Dockerfile"
        ];
        detect_folders = [];
        disabled = false;
      };

      elixir.symbol = " ";
      elm.symbol = " ";
      git_branch.symbol = " ";
      golang.symbol = " ";
      hg_branch.symbol = " ";
      java.symbol = " ";
      julia.symbol = " ";
      haskell.symbol = "λ ";
      memory_usage.symbol = " ";
      nim.symbol = " ";
      nix_shell.symbol = " ";
      package.symbol = " ";
      perl.symbol = " ";
      php.symbol = " ";

      python = {
        symbol = " ";
        # Escaping note: \${} prevents Nix interpolation. \\(\\) handles the parens.
        format = "via [\${symbol}python (\${version} )(\\(\${virtualenv}\\) )]($style)";
        style = "bold yellow";
        pyenv_prefix = "venv ";
        python_binary = [
          "./venv/bin/python"
          "python"
          "python3"
          "python2"
        ];
        detect_extensions = ["py"];
        version_format = "v\${raw}";
      };

      ruby.symbol = " ";
      rust.symbol = " ";
      scala.symbol = " ";
      shlvl.symbol = " ";
      swift.symbol = "ﯣ ";

      nodejs = {
        format = "via [ Node.js $version](bold green) ";
        detect_files = [
          "package.json"
          ".node-version"
        ];
        detect_folders = ["node_modules"];
      };
    };
  };

  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.zellij = {
    enable = true;
    enableZshIntegration = true;
    exitShellOnExit = true;
  };
  catppuccin.zellij.enable = true;
}
