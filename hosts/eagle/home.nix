{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/niri.nix
    ../../modules/home-manager/waybar.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/home-manager/nix.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/spotify.nix
    ../../modules/home-manager/anyrun.nix
    ../../modules/home-manager/swww.nix
    ../../modules/home-manager/discord.nix
    ../../modules/home-manager/bluetooth.nix
    ../../modules/home-manager/audio.nix
    ../../modules/home-manager/firefox.nix
    ../../modules/home-manager/ssh.nix
    inputs.nix-index-database.homeModules.nix-index
    inputs.spicetify-nix.homeManagerModules.default
    inputs.nur.modules.homeManager.default
    inputs.agenix.homeManagerModules.default
  ];

  nixpkgs.config.allowUnfree = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "michael";
  home.homeDirectory = "/home/michael";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  fonts.fontconfig.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.fantasque-sans-mono
    pkgs.uutils-coreutils-noprefix
    pkgs.gemini-cli-bin

    inputs.neovim.packages.x86_64-linux.default

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  programs.niri = {
    settings.outputs = {
      "DP-3" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.;
        };
        position = {
          x = 0;
          y = 0;
        };
      };
      "DP-2" = {
        enable = true;
        focus-at-startup = true;
        mode = {
          width = 2560;
          height = 1440;
          refresh = 239.97;
        };
        position = {
          x = 1920;
          y = 0;
        };
      };
      "HDMI-A-1" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.;
        };
        position = {
          x = 4480;
          y = 0;
        };
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = ["gtk"];
      "org.freedesktop.impl.portal.Secret".default = ["gnome-keyring"];
    };
  };
  xdg.mime.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
    };
  };

  # TODO: I'm sure there is a way to extract this, I just don't know how...
  age.identityPaths = ["/home/michael/.dotfiles/nix/secrets/master.key"];

  # TODO: I'm not sure this belongs here. It should go into modules/home-manager/ssh
  age.secrets.mainKey = {
    file = ../../secrets/id_ed25519.age;
    path = "/home/michael/.ssh/id_ed25519";
    mode = "600";
  };

  home.file.".ssh/id_ed25519.pub".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7ZqNhzqRIfH0C9OOuGvJRxQSG1y5HX8RAH6FsF/V3R
  '';

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/michael/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
