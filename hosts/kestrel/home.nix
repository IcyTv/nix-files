{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home-manager/default.nix
  ];

  my.hm.core.enable = true;
  my.hm.default.enable = true;

  programs.niri = {
    settings.outputs = {
    };
  };
}
