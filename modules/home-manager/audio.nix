{ pkgs, config, lib, ... }: {
  options.my.hm.audio.enable = lib.mkEnableOption "Audio tools (pavucontrol)";

  config = lib.mkIf config.my.hm.audio.enable {
    home.packages = [
      pkgs.pavucontrol
    ];
  };
}