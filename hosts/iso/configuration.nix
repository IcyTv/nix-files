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
    inputs.home-manager.nixosModules.default
  ];

  networking.hostName = "mayfly";
  security.sudo.enable = false;

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

  networking.firewall.allowedTCPPorts = [9512];
  networking.firewall.allowedUDPPorts = [24727 9511 9512];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "bak";

    users = {
      "michael" = import ./home.nix;
    };
  };

  boot.loader.limine.secureBoot.enable = true;
  boot.loader.limine.efiSupport = true;

  boot.kernelPackages = pkgs.linuxPackages;

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

  boot.resumeDevice = "/dev/disk/by-uuid/82a0bbc7-5d26-44a4-b288-711cc2e40a8c";
  boot.initrd.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" "nct6687" "v4l2loopback"];
  boot.extraModprobeConfig = ''
    options bluetooth disable_ertm=1
    options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
  '';
  boot.kernelParams = [
    "nouveau.modeset=0"
    "initcall_blacklist=simpledrm_platform_driver_init"
    "video=DP-2:1920x1080@60"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "acpi_enforce_resources=lax"
    "resume_offset=9563072"
    "mem_sleep_default=deep"
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
          rev = "2f40c7e3cdbc634912cb569c451a4c0e37a50986";
          sha256 = "sha256-ivKi4I68Azpzo9eeH4YeEOQmKiG6DQQVJPtCFmUQ7/A=";
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
    config.boot.kernelPackages.v4l2loopback.out
  ];

  boot.loader.limine.extraConfig = "RESOLUTION=2560x1440";
  boot.loader.limine.style.interface.resolution = "2560x1440";

  system.stateVersion = "25.11";
}