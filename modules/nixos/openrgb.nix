{ config, lib, pkgs, ... }: let
  no-rgb = pkgs.writeScriptBin "no-rgb" ''
    #!/bin/sh
    NUM_DEVICES=$(${pkgs.openrgb}/bin/openrgb --noautoconnect --list-devices | grep -E '^[0-9]+: ' | wc -l)

    for i in $(seq 0 $(($NUM_DEVICES - 1))); do
      ${pkgs.openrgb}/bin/openrgb --noautoconnect --device $i --mode static --color 000000
    done
  '';
in {
  options.my.nixos.openrgb.enable = lib.mkEnableOption "OpenRGB (disable RGB)";

  config = lib.mkIf config.my.nixos.openrgb.enable {
    services.udev.packages = [pkgs.openrgb];
    boot.kernelModules = ["i2c-dev"];
    hardware.i2c.enable = true;

    systemd.services.no-rgb = {
      description = "Disable all RGB";
      serviceConfig = {
        ExecStart = "${no-rgb}/bin/no-rgb";
        Type = "oneshot";
      };
      wantedBy = ["multi-user.target"];
    };
  };
}