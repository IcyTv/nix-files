{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.gammastep.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.gammastep.enable {
    services.gammastep = {
      enable = true;
      dawnTime = "6:00-7:45";
      duskTime = "21:30-22:15";
      tray = true;
      temperature = {
        day = 6500;
        night = 2000;
      };
      settings = {
        general = {
          adjustment-method = "wayland";
          brightness-day = 1.0;
          brightness-night = 0.7;
        };
      };
    };

    xdg.configFile."autostart/gammastep-indicator.desktop".text = ''
      [Desktop Entry]
      Type = Application
      Name = Gammastep Indicator
      Exec = ${pkgs.gammastep}/bin/gammastep-indicator
      Hidden = true
    '';
  };
}
