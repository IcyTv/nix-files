{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  options.my.hm.core.enable = lib.mkEnableOption "Core Home Manager configuration";
  options.my.hm.default.enable = lib.mkEnableOption "Enable all default Home Manager modules";

  config = lib.mkMerge [
    (
      lib.mkIf config.my.hm.core.enable {
        home = {
          username = "michael";
          homeDirectory = "/home/michael";
          stateVersion = "25.11";
        };

        fonts.fontconfig.enable = true;

        home.packages = [
          pkgs.nerd-fonts.jetbrains-mono
          pkgs.nerd-fonts.fantasque-sans-mono
          pkgs.uutils-coreutils-noprefix
          pkgs.gemini-cli-bin
          pkgs.github-copilot-cli

          (inputs.neovim.lib.x86_64-linux.makeNeovimWithLanguages
            {
              pkgs = pkgs.extend (_final: prev: {
                inherit (inputs.nixpkgs-unstable.legacyPackages.x86_64-linux) opencode;
                vimPlugins =
                  prev.vimPlugins
                  // {
                    inherit (inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.vimPlugins) opencode-nvim;
                  };
              });
              languages.nix.enable = true;
              languages.shell.enable = true;
              extraConfig = {
                plugins.opencode.package = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.vimPlugins.opencode-nvim;
              };
            })
        ];

        services.gnome-keyring.enable = true;
        xdg = {
          portal = {
            enable = true;
            xdgOpenUsePortal = true;
            extraPortals = [
              pkgs.xdg-desktop-portal-gtk
              pkgs.xdg-desktop-portal-gnome
              pkgs.gnome-keyring
            ];
            configPackages = [
              pkgs.xdg-desktop-portal-gtk
              pkgs.xdg-desktop-portal-gnome
              pkgs.gnome-keyring
            ];
            config = {
              common.default = ["gtk"];
              "org.freedesktop.impl.portal.Secret".default = ["gnome-keyring"];
              "org.freedesktop.impl.portal.ScreenCast".default = [
                "gnome"
              ];
            };
          };
          mime.enable = true;
          mimeApps = {
            enable = true;
            defaultApplications = {
              "x-scheme-handler/http" = "firefox.desktop";
            };
          };
          userDirs = {
            enable = true;
          };
        };

        age = {
          identityPaths = ["/home/michael/.dotfiles/nix/secrets/master.key"];

          secrets.mainKey = {
            file = ../../secrets/id_ed25519.age;
            path = "/home/michael/.ssh/id_ed25519";
            mode = "600";
          };

          secrets.github-token = {
            file = ../../secrets/github-token.age;
          };
        };

        nix.extraOptions = ''
          !include /run/user/1000/agenix/github-token
        '';

        home.file.".ssh/id_ed25519.pub".text = ''
          ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7ZqNhzqRIfH0C9OOuGvJRxQSG1y5HX8RAH6FsF/V3R
        '';

        xdg.configFile."nixpkgs/config.nix".text = ''
          {allowUnfree = true;}
        '';

        home.sessionVariables = {
          EDITOR = "nvim";
          NIXOS_OZONE_WL = "1";
          ELECTRON_OZONE_PLATFORM_HINT = "wayland";
        };

        programs.home-manager.enable = true;
      }
    )
    (lib.mkIf config.my.hm.default.enable {
      my.hm.ai.enable = true;
      my.hm.anyrun.enable = true;
      my.hm.audio.enable = true;
      my.hm.bluetooth.enable = true;
      my.hm.discord.enable = true;
      my.hm.firefox.enable = true;
      my.hm.games.enable = true;
      my.hm.git.enable = true;
      my.hm.kitty.enable = true;
      my.hm.niri.enable = true;
      my.hm.nix.enable = true;
      my.hm.nushell.enable = true;
      my.hm.obs.enable = true;
      my.hm.spotify.enable = true;
      my.hm.ssh.enable = true;
      my.hm.starship.enable = true;
      my.hm.stylix.enable = true;
      my.hm.subniri.enable = true;
      my.hm.swww.enable = true;
      my.hm.tools.enable = true;
      my.hm.unifiedremote.enable = true;
      my.hm.yazi.enable = true;
      my.hm.zsh.enable = true;
    })
  ];
}
