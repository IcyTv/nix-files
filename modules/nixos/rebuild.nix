{pkgs, ...}: let
  user = "michael";
  flakeDir = ".dotfiles/nix";
in {
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
}
