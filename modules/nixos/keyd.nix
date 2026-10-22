{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.nixos.keyd.enable = lib.mkEnableOption "Enable keyd configuration";

  config = lib.mkIf config.my.nixos.keyd.enable {
    services.keyd = {
      enable = true;
      keyboards.defalt = {
        ids = ["*"];
        settings = {
          main = {
            capslock = "overload(wm, esc)";
          };
          shift = {
            capslock = "capslock";
          };
          "wm:M" = {
            d = "layer(wmshift)";
          };
          "wmshift:M-S" = {
          };
        };
      };
    };
  };
}
