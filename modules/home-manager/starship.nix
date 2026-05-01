{
  lib,
  config,
  ...
}: {
  options.my.hm.starship.enable = lib.mkEnableOption "Starship prompt configuration";

  config = lib.mkIf config.my.hm.starship.enable {
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
          format = "[\\[$symbol$common_meaning$signal_name$maybe_int\\]]($style)";
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
  };
}
