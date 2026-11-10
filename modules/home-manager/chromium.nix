{
  config,
  lib,
  ...
}: {
  options.my.hm.chromium.enable = lib.mkEnableOption "Chromium configuration";

  config = lib.mkIf config.my.hm.chromium.enable {
    programs.chromium.enable = true;
  };
}
