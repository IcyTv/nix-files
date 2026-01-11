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
  ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };
}
