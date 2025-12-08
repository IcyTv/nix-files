{pkgs, ...}: {
  stylix.targets.btop.enable = true;

  home.packages = [
    pkgs.btop
    pkgs.fd
  ];
}
