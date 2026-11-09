{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.rebuild.enable = lib.mkEnableOption "Custom rebuild script";

  config = lib.mkIf config.my.nixos.rebuild.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "rebuild";
        runtimeInputs = [pkgs.git pkgs.nvd pkgs.alejandra];
        runtimeEnv = {
          FLAKE_PATH = config.icy.repository;
        };
        text = builtins.readFile ../../rebuild.sh;
      })
    ];
  };
}
