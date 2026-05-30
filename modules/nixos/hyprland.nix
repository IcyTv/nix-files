{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true; # optional
  };
in {
  options.my.nixos.hyprland.enable = lib.mkEnableOption "Hyprland Wayland compositor";

  config = lib.mkIf config.my.nixos.hyprland.enable {
    programs.hyprland = {
      enable = true;

      package = unstable.hyprland;
      portalPackage = unstable.xdg-desktop-portal-hyprland;
    };
  };
}
