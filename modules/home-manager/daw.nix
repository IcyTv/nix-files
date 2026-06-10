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
      reaper-reapack-extension
    ];

    home.file = {
      ".lv2/Helm.lv2".source = "${pkgs.helm}/lib/lv2/helm.lv2";
    };
  };
}
