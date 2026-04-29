{ config, lib, pkgs, ... }: {
  options.my.nixos.limine.enable = lib.mkEnableOption "Limine bootloader";

  config = lib.mkIf config.my.nixos.limine.enable {
    boot.loader.limine = {
      enable = true;
      maxGenerations = 5;
      enrollConfig = true;
      panicOnChecksumMismatch = true;
    };
    boot.loader.efi.canTouchEfiVariables = true;

    environment.systemPackages = [
      pkgs.sbctl
    ];
  };
}