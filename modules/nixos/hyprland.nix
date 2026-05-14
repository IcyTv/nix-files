{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.hyprland.enable = lib.mkEnableOption "Hyprland Wayland compositor";

  config = lib.mkIf config.my.nixos.hyprland.enable {
    programs.hyprland = {
      enable = true;
    };
  };
}
