{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
  ];

  networking.hostName = "kestrel";

  my.nixos = {
    core.enable = true;
    ananicy.enable = true;
    bluetooth.enable = true;
    console-font.enable = true;
    docker.enable = true;
    geoclue.enable = true;
    greetd.enable = true;
    keyd.enable = true;
    keymap.enable = true;
    limine.enable = true;
    niri.enable = true;
    plymouth.enable = true;
    printing.enable = true;
    rebuild.enable = true;
    stylix.enable = true;
    sudo-rs.enable = true;
    tools.enable = true;
    zsh.enable = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "bak";

    users = {
      "michael" = import ./home.nix;
    };
  };

  boot.loader.limine.secureBoot.enable = false;
  boot.loader.limine.efiSupport = true;

  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "fido2-device=auto"
    "fido2-with-client-pin=yes"
  ];

  boot.supportedFilesystems = ["btrfs"];

  swapDevices = [
    { device = "/swap/swapfile"; }
  ];

  boot.kernelPackages = pkgs.linuxPackages;

  hardware.bluetooth.powerOnBoot = true;

  hardware.graphics.enable = true;

  system.stateVersion = "26.05";
}
