{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/stylix.nix
    ../../modules/nixos/tools.nix
    ../../modules/nixos/keymap.nix
    ../../modules/nixos/console-font.nix
    ../../modules/nixos/zsh.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/rebuild.nix
    ../../modules/nixos/limine.nix
    ../../modules/nixos/plymouth.nix
    ../../modules/nixos/sudo-rs.nix
    ../../modules/nixos/ananicy.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/printing.nix
    ../../modules/nixos/openrgb.nix
    inputs.home-manager.nixosModules.default
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  networking.hostName = "sparrow";

  nixpkgs.config.allowUnfree = true;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.enable = false;
  services.xserver.videoDrivers = ["nouveau"];
  security.rtkit.enable = true;

  environment.sessionVariables = {
    NIRI_BACKEND = "vulkan";
  };

  users.users.michael = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.nushell;
  };

  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "bak";

    users = {
      "michael" = import ./home.nix;
    };
  };

  programs.niri = {
    enable = true;
    package = pkgs.niri;
  };

  services.openssh.enable = true;

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = ["-L"];
    dates = "06:00";
    randomizedDelaySec = "45min";
  };

  # boot.loader.limine.secureBoot.enable = true;
  boot.loader.limine.efiSupport = true;

  boot.kernelPackages = pkgs.linuxPackages;

  # hardware.fancontrol.enable = true;

  hardware.bluetooth.enable = true;

  hardware.graphics.enable = true;

  boot.blacklistedKernelModules = ["nvvidia" "nvidia_drm" "nvidia_modesett"];

  boot.loader.limine.extraConfig = "RESOLUTION=1920x1080";
  boot.loader.limine.style.interface.resolution = "1920x1080";

  system.stateVersion = "25.11";
}
