{...}: {
  imports = [
    ../../modules/home-manager/default.nix
  ];

  my.hm.core.enable = true;
  my.hm.default.enable = true;

  programs.niri = {
    settings.outputs = {
      "DP-1" = {
        enable = true;
        focus-at-startup = true;
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
      "HDMI-A-1" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 1920;
          y = 0;
        };
      };
    };
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "DP-1,1920x1080@60,0x0,1"
      "HDMI-A-1,1920x1080@60,1920x0,1"
    ];
    workspace = [
      "9, monitor:HDMI-A-1"
    ];
  };
}
