{pkgs, ...}: {
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
}
