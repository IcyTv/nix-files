{...}: {
  catppuccin.waybar.enable = true;
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 17px;
        min-height: 0;
        border: none;
        border-radius: 0;
      }

      window#waybar {
        background-color: @mantle;
      }
    '';

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
