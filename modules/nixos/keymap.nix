{ config, lib, pkgs, ... }: {
  options.my.nixos.keymap.enable = lib.mkEnableOption "Custom keymap (us altgr-intl)";

  config = lib.mkIf config.my.nixos.keymap.enable {
    services.xserver.xkb = {
      layout = "us";
      variant = "altgr-intl";
      options = "caps:escape_shifted_capslock";
    };

    console.useXkbConfig = true;
  };
}