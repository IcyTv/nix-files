{
  config,
  lib,
  ...
}: {
  options.my.hm.subniri.enable = lib.mkEnableOption "Subniri integration";

  config = lib.mkIf config.my.hm.subniri.enable {
    services.subniri.enable = true;
  };
}
