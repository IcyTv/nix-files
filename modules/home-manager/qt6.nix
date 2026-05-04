{pkgs, ...}: {
  qt.enable = true;

  home.packages = [
    pkgs.qt6.qtsvg
    pkgs.hicolor-icon-theme
  ];
}
