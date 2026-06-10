{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home-manager/default.nix
  ];

  my.hm.core.enable = true;
  my.hm.default.enable = true;
  my.hm.daw.enable = true;

  programs.niri = {
    settings.outputs = {
      "DP-3" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
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
          refresh = 60.0;
        };
        position = {
          x = 4480;
          y = 0;
        };
      };
    };
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "DP-3,1920x1080@60,0x0,1"
      "DP-2,2560x1440@239.97,1920x0,1"
      "HDMI-A-1,1920x1080@60,4480x0,1"
    ];
    workspace = [
      "9, monitor:HDMI-A-1"
    ];
  };
}
