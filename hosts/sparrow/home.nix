{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home-manager/default.nix
    inputs.nix-index-database.homeModules.nix-index
    inputs.spicetify-nix.homeManagerModules.default
    inputs.agenix.homeManagerModules.default
    inputs.nixcord.homeModules.nixcord
    inputs.subniri.homeModules.subniri
  ];

  my.hm.core.enable = true;

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
  my.hm.stylix.enable = true;
  my.hm.subniri.enable = true;
  my.hm.swww.enable = true;
  my.hm.tools.enable = true;
  my.hm.unifiedremote.enable = true;
  my.hm.yazi.enable = true;
  my.hm.zsh.enable = true;

  programs.niri = {
    settings.outputs = {
      "DP-1" = {
        enable = true;
        focus-at-startup = true;
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
      "HDMI-A-1" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.;
        };
        position = {
          x = 1920;
          y = 0;
        };
      };
    };
  };
}
