{pkgs, ...}: {
  programs.btop.enable = true;
  programs.fd = {
    enable = true;
    hidden = true;
  };

  home.packages = [
    pkgs.openrgb
    pkgs.tldr
    pkgs.wikiman
    pkgs.typst
    pkgs.wl-gammarelay-rs
    pkgs.lsof
    pkgs.crate2nix
    pkgs.kdePackages.okular
    pkgs.btdu
    pkgs.jq
    pkgs.file
    pkgs._7zz

    pkgs.man-pages
    pkgs.man-pages-posix

    pkgs.zapzap
  ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;

    extraPackages = [
      pkgs.ouch
      pkgs.lazygit
    ];

    settings = {
      mpr = {
        show_hidden = true;
        sort_dir_first = true;
      };

      plugin = {
        prepend_fetchers = [
          {
            id = "git";
            url = "*";
            run = "git";
          }
          {
            id = "git";
            url = "*/";
            run = "git";
          }
        ];
        prepend_previewers = [
          {
            run = "ouch";
            mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
          }
        ];
      };
    };

    keymap = {
      mgr.prepend_keymap = [
        {
          on = ["R" "p" "p"];
          run = "plugin sudo -- paste";
          desc = "sudo paste";
        }
        {
          on = ["R" "P"];
          run = "plugin sudo -- paste --force";
          desc = "sudo paste (force)";
        }
        {
          on = ["R" "r"];
          run = "plugin sudo -- rename";
          desc = "sudo rename";
        }
        {
          on = ["R" "p" "l"];
          run = "plugin sudo -- link";
          desc = "sudo link (absolute path)";
        }
        {
          on = ["R" "p" "r"];
          run = "plugin sudo -- link --relative";
          desc = "sudo link (relative path)";
        }
        {
          on = ["R" "p" "L"];
          run = "plugin sudo -- hardlink";
          desc = "sudo hardlink";
        }
        {
          on = ["R" "a"];
          run = "plugin sudo -- create";
          desc = "sudo create file";
        }
        {
          on = ["R" "d"];
          run = "plugin sudo -- remove";
          desc = "sudo delete file";
        }
        {
          on = ["R" "d"];
          run = "plugin sudo -- remove --permanently";
          desc = "sudo delete file (permanently)";
        }
        {
          on = ["R" "m"];
          run = "plugin sudo -- chmod";
          desc = "sudo chmod";
        }

        {
          on = ["M"];
          run = "plugin mount";
          desc = "mount / unmount";
        }

        {
          on = ["g" "i"];
          run = "plugin lazygit";
          desc = "lazygit";
        }
        {
          on = ["g" "c"];
          run = "plugin vcs-files";
          desc = "Show Git files changed";
        }
      ];
    };

    plugins = with pkgs.yaziPlugins; {
      inherit sudo ouch mount git lazygit vcs-files full-border;
    };

    initLua =
      #lua
      ''
        require("full-border"):setup()
        require("git"):setup()

        -- show disk in status bar
        Status:children_add(function()
            local command = "df -kh .|awk '!/^Filesystem/{printf \" %s FREE \", $(NF-2)}'"
            local info = ui.Span(io.popen(command):read('*a')):fg("green")
            return info
        end, 1500, Header.RIGHT)
      '';
  };
}
