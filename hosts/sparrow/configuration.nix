{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
    inputs.home-manager.nixosModules.default
  ];

  networking.hostName = "sparrow";

  my.nixos.core.enable = true;
  my.nixos.ananicy.enable = true;
  my.nixos.bluetooth.enable = true;
  my.nixos.console-font.enable = true;
  my.nixos.games.enable = true;
  my.nixos.greetd.enable = true;
  my.nixos.keymap.enable = true;
  my.nixos.limine.enable = true;
  my.nixos.niri.enable = true;
  my.nixos.openrgb.enable = true;
  my.nixos.plymouth.enable = true;
  my.nixos.printing.enable = true;
  my.nixos.rebuild.enable = true;
  my.nixos.stylix.enable = true;
  my.nixos.sudo-rs.enable = true;
  my.nixos.tools.enable = true;
  my.nixos.zsh.enable = true;

  services.xserver.videoDrivers = ["nouveau"];

  environment.sessionVariables = {
    NIRI_BACKEND = "vulkan";
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

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 24 * 1024;
    }
  ];

  boot.loader.limine.efiSupport = true;

  boot.kernelPackages = pkgs.linuxPackages;

  hardware.graphics.enable = true;

  boot.blacklistedKernelModules = ["nvvidia" "nvidia_drm" "nvidia_modesett"];

  boot.loader.limine.extraConfig = "RESOLUTION=1920x1080";
  boot.loader.limine.style.interface.resolution = "1920x1080";

  system.stateVersion = "25.11";
}
