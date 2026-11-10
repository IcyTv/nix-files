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

  icy.internal.core.enable = true;
  my.hm.default.enable = true;

  programs.git.signing.key = "0542E68C4DB7F8FBCA58B89E80C0D762AAB2A00F!";

  programs.niri = {
    settings.outputs = {
    };
  };
}
