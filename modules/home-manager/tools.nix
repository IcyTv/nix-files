{pkgs, ...}: {
  stylix.targets.btop.enable = true;

  programs.btop.enable = true;

  home.packages = [
    pkgs.fd
  ];
}
