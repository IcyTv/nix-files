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
  security.sudo.enable = true;

  users.motd = ''
    ========================================================================
     Welcome to the Custom NixOS Installer!
     Connect networking with `nmtui`, then run `sudo run-installer`.
     Online installation; review and exact-disk confirmation before erasure.
    ========================================================================
  '';

  icy.internal.core.enable = true;
  icy.internal.installer.enable = true;

  networking.networkmanager.enable = true;

  boot.loader.limine.efiSupport = true;
  boot.kernelPackages = pkgs.linuxPackages;

  system.stateVersion = "25.11";
}
