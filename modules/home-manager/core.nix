{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  options.icy.internal.core.enable = lib.mkEnableOption "Core Home Manager configuration";
  options.my.hm.default.enable = lib.mkEnableOption "Enable all default Home Manager modules";

  config = lib.mkMerge [
    (
      lib.mkIf config.icy.internal.core.enable {
        home = {
          username = config.icy.user.name;
          homeDirectory = "/home/${config.icy.user.name}";
          stateVersion = "25.11";
        };

        fonts.fontconfig.enable = true;

        home.packages = [
          pkgs.nerd-fonts.jetbrains-mono
          pkgs.nerd-fonts.fantasque-sans-mono
          pkgs.uutils-coreutils-noprefix
          pkgs.gemini-cli-bin
          pkgs.github-copilot-cli

          (inputs.neovim.lib.makeNeovimWithLanguages
            {
              pkgs = pkgs.extend (_final: prev: {
                inherit (inputs.nixpkgs-unstable.legacyPackages.x86_64-linux) opencode;
                vimPlugins =
                  prev.vimPlugins
                  // {
                    inherit (inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.vimPlugins) opencode-nvim;
                  };
              });
              system = "x86_64-linux";
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
            enable = lib.mkForce true;
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
            setSessionVariables = false;
          };
        };

        gtk.gtk4.theme = lib.mkForce null;

        age = lib.mkIf config.icy.personalSecrets {
          identityPaths = ["${config.home.homeDirectory}/.keys/age-master.key"];

          secrets.mainKey = {
            file = ../../secrets/id_ed25519.age;
            path = "${config.home.homeDirectory}/.ssh/id_ed25519";
            mode = "600";
          };

          secrets.github-token = {
            file = ../../secrets/github-token.age;
          };
        };

        nix.extraOptions = lib.mkIf config.icy.personalSecrets ''
          !include /run/user/1000/agenix/github-token
        '';

        home.file = lib.mkIf config.icy.personalSecrets {
          ".ssh/id_ed25519.pub".text = ''
            ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7ZqNhzqRIfH0C9OOuGvJRxQSG1y5HX8RAH6FsF/V3R
          '';
        };

        xdg.configFile."nixpkgs/config.nix".text = ''
          {allowUnfree = true;}
        '';

        home.sessionVariables = {
          EDITOR = "nvim";
          VISUAL = "nvim";
          NIXOS_OZONE_WL = "1";
          ELECTRON_OZONE_PLATFORM_HINT = "wayland";
        };

        programs.home-manager.enable = true;
      }
    )
    (lib.mkIf config.my.hm.default.enable {
      my.hm = lib.genAttrs [
        "ai"
        "anyrun"
        "audio"
        "bluetooth"
        "discord"
        "firefox"
        "games"
        "git"
        "kitty"
        "ghostty"
        "niri"
        "nix"
        "nushell"
        "obs"
        "spotify"
        "ssh"
        "starship"
        "stylix"
        "subniri"
        "swww"
        "tools"
        "unifiedremote"
        "yazi"
        "zsh"
      ] (_: {enable = lib.mkDefault true;});
    })
  ];
}
