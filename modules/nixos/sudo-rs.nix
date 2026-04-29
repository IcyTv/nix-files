{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.sudo-rs.enable = lib.mkEnableOption "Sudo-rs replacement for sudo";

  config = lib.mkIf config.my.nixos.sudo-rs.enable {
    security.sudo-rs = {
      enable = true;
      extraConfig = ''
        Defaults pwfeedback
      '';
    };
  };
}
