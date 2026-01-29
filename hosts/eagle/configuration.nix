{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
    inputs.home-manager.nixosModules.default
    inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
  ];

  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };
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

  boot.loader.limine.secureBoot.enable = true;
  boot.loader.limine.efiSupport = true;

  boot.kernelPackages = pkgs.linuxPackages;

  # hardware.fancontrol.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
  };

  services.udev.packages = [config.boot.kernelPackages.nvidiaPackages.production];
  services.udev.extraRules = ''
    # NS PRO Controller USB
    KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a711", MODE="0660", TAG+="uaccess", GROUP="input"
  '';

  services.xserver.videoDrivers = ["nvidia"];

  boot.initrd.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" "nct6687"];
  boot.extraModprobeConfig = ''
    options bluetooth disable_ertm=1
  '';
  boot.kernelParams = [
    "nouveau.modeset=0"
    "initcall_blacklist=simpledrm_platform_driver_init"
    "video=DP-2:1920x1080@60"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "acpi_enforce_resources=lax"
  ];
  boot.blacklistedKernelModules = ["nouveau" "nct6683"];
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ({
      stdenv,
      lib,
      fetchFromGitHub,
      kernel,
    }:
      stdenv.mkDerivation rec {
        pname = "nct6687d";
        version = "0.0.1";

        src = fetchFromGitHub {
          owner = "Fred78290";
          repo = "nct6687d";
          rev = "2f40c7e3cdbc634912cb569c451a4c0e37a50986"; # Check GitHub for latest hash if needed
          sha256 = "sha256-ivKi4I68Azpzo9eeH4YeEOQmKiG6DQQVJPtCFmUQ7/A="; # You may need to update this hash
        };

        nativeBuildInputs = kernel.moduleBuildDependencies;
        makeFlags = [
          "-C"
          "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
          "M=$(PWD)"
        ];
        buildFlags = ["modules"];
        installPhase = ''
          install -D nct6687.ko $out/lib/modules/${kernel.modDirVersion}/extra/nct6687.ko
        '';
      }) {})
  ];

  boot.loader.limine.extraConfig = "RESOLUTION=2560x1440";
  boot.loader.limine.style.interface.resolution = "2560x1440";

  system.stateVersion = "25.11";
}
