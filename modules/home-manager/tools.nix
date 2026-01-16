{pkgs, ...}: {
  programs.btop.enable = true;
  programs.fd = {
    enable = true;
    hidden = true;
  };

  home.packages = [
    pkgs.openrgb
    pkgs.tldr
    pkgs.wikiman
    pkgs.typst
    pkgs.wl-gammarelay-rs
    pkgs.lsof
    pkgs.crate2nix
    pkgs.kdePackages.okular
    pkgs.btdu
    pkgs.jq
    pkgs.file

    pkgs.man-pages
    pkgs.man-pages-posix

    pkgs.zapzap
  ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };
}
