{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.obs.enable = lib.mkEnableOption "OBS Studio";

  config = lib.mkIf config.my.hm.obs.enable {
    programs.obs-studio = {
      enable = true;
      plugins = [
        pkgs.obs-studio-plugins.wlrobs
      ];
    };
  };
}
