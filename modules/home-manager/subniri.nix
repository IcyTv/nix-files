{
  config,
  lib,
  ...
}: {
  options.my.hm.subniri.enable = lib.mkEnableOption "Subniri integration";

  config = lib.mkIf config.my.hm.subniri.enable {
    services.subniri = {
      enable = true;
      settings = {
        nightlight = {
          enable = true;
          dawn = "07:00";
          dusk = "22:30";
          night = {
            temperature = 1800;
            brightness = 0.7;
          };
        };

        spotify = {
          enable = true;
          clientId = "a41e9bfa24b649508c8987b0e2ce09d6";
        };

        systemMenu.widgets = [
          "wifi"
          "bluetooth"
          "speaker"
          "microphone"
          "vpn"
          "nightlight"
        ];
      };
    };
  };
}
