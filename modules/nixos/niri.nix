{ config, lib, pkgs, ... }: {
  options.my.nixos.niri.enable = lib.mkEnableOption "Niri Wayland compositor";

  config = lib.mkIf config.my.nixos.niri.enable {
    programs.niri = {
      enable = true;
      package = pkgs.niri;
    };
  };
}