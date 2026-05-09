{
  config,
  lib,
  ...
}: {
  options.my.nixos.geoclue.enable = lib.mkEnableOption "Geolocation support (useful for weather, etc)";

  config = lib.mkIf config.my.nixos.geoclue.enable {
    location.provider = "geoclue2";
    services.geoclue2.enable = true;
  };
}
