{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "michael";
  flakeDir = ".dotfiles/nix";
in {
  options.my.nixos.rebuild.enable = lib.mkEnableOption "Custom rebuild script";

  config = lib.mkIf config.my.nixos.rebuild.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "rebuild";
        runtimeInputs = [pkgs.git pkgs.nvd pkgs.alejandra];
        runtimeEnv = {
          FLAKE_PATH = "/home/${user}/${flakeDir}";
        };
        text = builtins.readFile ../../rebuild.sh;
      })
    ];
  };
}
