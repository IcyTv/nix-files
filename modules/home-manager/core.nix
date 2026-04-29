{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  options.my.hm.core.enable = lib.mkEnableOption "Core Home Manager configuration";

  config = lib.mkIf config.my.hm.core.enable {
    home.username = "michael";
    home.homeDirectory = "/home/michael";
    home.stateVersion = "25.11";

    fonts.fontconfig.enable = true;

    home.packages = [
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.nerd-fonts.fantasque-sans-mono
      pkgs.uutils-coreutils-noprefix
      pkgs.gemini-cli-bin
      pkgs.github-copilot-cli

      (inputs.neovim.lib.x86_64-linux.makeNeovimWithLanguages
        {
          pkgs = pkgs.extend (final: prev: {
            opencode = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.opencode;
            vimPlugins =
              prev.vimPlugins
              // {
                opencode-nvim = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.vimPlugins.opencode-nvim;
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
    xdg.portal = {
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
    xdg.mime.enable = true;
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = "firefox.desktop";
      };
    };
    xdg.userDirs = {
      enable = true;
    };

    age.identityPaths = ["/home/michael/.dotfiles/nix/secrets/master.key"];

    age.secrets.mainKey = {
      file = ../../secrets/id_ed25519.age;
      path = "/home/michael/.ssh/id_ed25519";
      mode = "600";
    };

    age.secrets.github-token = {
      file = ../../secrets/github-token.age;
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
  };
}
