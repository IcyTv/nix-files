{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.installer.enable = lib.mkEnableOption "TUI Installer script";

  config = lib.mkIf config.my.nixos.installer.enable {
    environment.systemPackages = [
      pkgs.gum
      pkgs.git
      pkgs.curl
      (pkgs.writeShellApplication {
        name = "run-installer";
        runtimeInputs = [pkgs.gum pkgs.git pkgs.curl pkgs.nixos-install-tools];
        text = builtins.readFile ../../scripts/installer.sh;
      })
    ];
  };
}
