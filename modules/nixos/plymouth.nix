{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.plymouth.enable = lib.mkEnableOption "Plymouth boot splash";

  config = lib.mkIf config.my.nixos.plymouth.enable {
    boot.consoleLogLevel = 3;
    boot.initrd.verbose = true;
    boot.kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
    boot.loader.timeout = lib.mkForce 1;

    stylix.targets.plymouth.enable = false;

    boot.plymouth = {
      enable = true;
      theme = "catppuccin-mocha";
      themePackages = [
        (pkgs.catppuccin-plymouth.override {
          variant = "mocha";
        })
      ];
    };
  };
}
