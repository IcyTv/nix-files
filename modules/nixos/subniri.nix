{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.subniri.enable = lib.mkEnableOption "Stylix system theming";
  options.my.nixos.subniri.batteryControl.enable =
    lib.mkEnableOption "Subniri power-profile and charge-limit control";

  config = lib.mkMerge [
    (lib.mkIf config.my.nixos.subniri.enable {
      services.subniri.resumeRestart = {
        enable = true;
        users = [config.icy.user.name];
      };
    })
    (lib.mkIf config.my.nixos.subniri.batteryControl.enable {
      services.power-profiles-daemon.enable = true;
      users.groups.subniri-power = {};
      users.users.${config.icy.user.name}.extraGroups = ["subniri-power"];
      services.udev.extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="BAT0", RUN+="${pkgs.coreutils}/bin/chgrp subniri-power /sys%p/charge_control_start_threshold /sys%p/charge_control_end_threshold", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/charge_control_start_threshold /sys%p/charge_control_end_threshold"
      '';
    })
  ];
}
