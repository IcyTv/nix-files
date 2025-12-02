{...}: {
  catppuccin.waybar.enable = true;
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.main = {
      layer = "top";
      position = "top";

      modules-left = [
        "cffi/niri-taskbar"
      ];

      modules-center = [
        "custom/music"
      ];

      modules-right = [
        "clock"
        "tray"
        "bluetooth"
      ];
    };
  };
}
