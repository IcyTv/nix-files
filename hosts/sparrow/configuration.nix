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
  ];

  networking.hostName = "sparrow";

  my.nixos = {
    core.enable = true;
    ananicy.enable = true;
    bluetooth.enable = true;
    console-font.enable = true;
    games.enable = true;
    geoclue.enable = true;
    greetd.enable = true;
    keymap.enable = true;
    limine.enable = true;
    niri.enable = true;
    openrgb.enable = true;
    plymouth.enable = true;
    printing.enable = true;
    rebuild.enable = true;
    stylix.enable = true;
    sudo-rs.enable = true;
    tools.enable = true;
    zsh.enable = true;
  };

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
