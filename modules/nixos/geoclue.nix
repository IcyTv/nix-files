{
  config,
  lib,
  ...
}: {
  options.my.nixos.geoclue.enable = lib.mkEnableOption "Geolocation support (useful for weather, etc)";

  config = lib.mkIf config.my.nixos.geoclue.enable {
    location.provider = "geoclue2";
    services.geoclue2 = {
      enable = true;
      whitelistedAgents = [
        "de.icytv.Subniri.LocationProvider"
      ];
      appConfig."de.icytv.Subniri.LocationProvider" = {
        isAllowed = true;
        isSystem = true; # Setting this to true means it doesn't need an agent's approval
        users = []; # Empty list means allowed for all users
      };
    };
  };
}
