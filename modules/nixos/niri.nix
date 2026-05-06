{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  # pkgs-unstable = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
in {
  options.my.nixos.niri.enable = lib.mkEnableOption "Niri Wayland compositor";

  config = lib.mkIf config.my.nixos.niri.enable {
    programs.niri = {
      enable = true;
      package = pkgs.niri;
    };
  };
}
