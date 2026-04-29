{ config, lib, pkgs, ... }: {
  options.my.nixos.console-font.enable = lib.mkEnableOption "Custom console font";

  config = lib.mkIf config.my.nixos.console-font.enable {
    console = {
      packages = [pkgs.terminus_font];
      font = "ter-v16n";
    };
  };
}