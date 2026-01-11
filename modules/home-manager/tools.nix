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
    pkgs.opencode
  ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };
}
