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
    inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  networking.hostName = "eagle";

  nixpkgs.config.allowUnfree = true;

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.enable = false;
  security.rtkit.enable = true;

  users.users.michael = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
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

  boot.loader.limine.secureBoot.enable = true;
  boot.loader.limine.efiSupport = true;

  boot.kernelPackages = pkgs.linuxPackages;

  # hardware.fancontrol.enable = true;

  hardware.bluetooth.enable = true;

  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
  };

  services.udev.packages = [config.boot.kernelPackages.nvidiaPackages.production];

  services.xserver.videoDrivers = ["nvidia"];

  boot.initrd.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" "nct6683"];
  boot.kernelParams = [
    "nouveau.modeset=0"
    "initcall_blacklist=simpledrm_platform_driver_init"
    "video=DP-2:1920x1080@60"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "acpi_enforce_resources=lax"
  ];
  boot.blacklistedKernelModules = ["nouveau"];

  boot.loader.limine.extraConfig = "RESOLUTION=2560x1440";
  boot.loader.limine.style.interface.resolution = "2560x1440";

  system.stateVersion = "25.11";
}
