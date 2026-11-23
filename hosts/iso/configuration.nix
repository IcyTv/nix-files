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

  # The live store (/nix/.rw-store) is a RAM-backed tmpfs and the image has no disk
  # swap (installation-cd-base sets swapDevices = []). Compressed RAM swap lets the
  # live system degrade instead of thrashing under evaluation/disko memory pressure;
  # the installer builds the full system on the target disk, not here.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  boot.loader.limine.efiSupport = true;
  boot.kernelPackages = pkgs.linuxPackages;

  system.stateVersion = "25.11";
}
