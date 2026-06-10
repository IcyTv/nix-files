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
      ".vst3/Helm.vst3".source = "${pkgs.helm}/lib/vst3/Helm.vst3";
      ".lv2/Helm.lv2".source = "${pkgs.helm}/lib/lv2/Helm.lv2";
    };
  };
}
