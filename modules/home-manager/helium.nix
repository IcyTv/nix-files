{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
in {
  imports = [inputs.helium-flake.homeModules.default];

  options.my.hm.helium.enable = lib.mkEnableOption "Helium configuration";

  config = lib.mkIf config.my.hm.helium.enable {
    warnings = lib.optional config.my.hm.firefox.enable "Helium and Firefox are both enabled, which can cause conflicts when selecting a default browser";

    programs.helium = {
      enable = true;
    };
  };
}
