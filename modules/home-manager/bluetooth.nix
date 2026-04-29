{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.bluetooth.enable = lib.mkEnableOption "Bluetooth configuration (bluetuith, mpris)";

  config = lib.mkIf config.my.hm.bluetooth.enable {
    services.mpris-proxy.enable = true;

    home.packages = [
      pkgs.bluetuith
    ];
  };
}
