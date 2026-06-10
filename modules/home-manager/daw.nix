{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.daw.enable = lib.mkEnableOption "Desktop Audio Workstation (Reaper)";

  config = lib.mkIf config.my.hm.daw.enable {
    home.packages = with pkgs; [
      reaper
      helm
    ];

    home.file = {
      ".vst3".source = "${pkgs.helm}/lib/vst3";
      ".lv2".source = "${pkgs.helm}/lib/lv2";
    };
  };
}
