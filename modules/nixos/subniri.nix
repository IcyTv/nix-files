{
  config,
  lib,
  ...
}: {
  options.my.nixos.subniri.enable = lib.mkEnableOption "Stylix system theming";

  config = lib.mkIf config.my.nixos.subniri.enable {
    services.subniri.resumeRestart = {
      enable = true;
      users = ["michael"];
    };
  };
}
