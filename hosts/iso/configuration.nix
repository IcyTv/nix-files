{
  config,
  pkgs,
  inputs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../../modules/nixos/default.nix
  ];

  networking.hostName = "mayfly";
  security.sudo.enable = false;

  users.motd = ''
    ========================================================================
     Welcome to the Custom NixOS Installer!
     Type `run-installer` and press Enter to start the interactive setup.
    ========================================================================
  '';

  my.nixos.core.enable = true;
  my.nixos.installer.enable = true;

  networking.networkmanager.enable = true;

  boot.loader.limine.efiSupport = true;
  boot.kernelPackages = pkgs.linuxPackages;

  system.stateVersion = "25.11";
}
