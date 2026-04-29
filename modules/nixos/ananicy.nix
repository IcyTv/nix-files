{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.ananicy.enable = lib.mkEnableOption "Ananicy auto nice daemon";

  config = lib.mkIf config.my.nixos.ananicy.enable {
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
  };
}
