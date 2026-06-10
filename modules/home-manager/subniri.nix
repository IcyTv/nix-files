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
      };
    };
  };
}
