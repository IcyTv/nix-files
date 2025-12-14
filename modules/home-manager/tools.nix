{pkgs, ...}: {
  programs.btop.enable = true;
  programs.fd = {
    enable = true;
    hidden = true;
  };

  home.packages = [
    pkgs.openrgb
    pkgs.yazi
    pkgs.tldr
    pkgs.wikiman
    pkgs.typst
  ];
}
