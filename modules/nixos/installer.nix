{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  options.icy.internal.installer.enable = lib.mkEnableOption "TUI Installer script";

  config = lib.mkIf config.icy.internal.installer.enable {
    services.pcscd.enable = true;
    hardware.gpgSmartcards.enable = true;
    services.udev.packages = [pkgs.yubikey-personalization];
    environment.systemPackages = [
      pkgs.gum
      pkgs.git
      pkgs.curl
      pkgs.git-crypt
      pkgs.util-linux
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.installer
    ];
  };
}
