{pkgs, ...}: {
  home.packages = [
    pkgs.alejandra
    pkgs.nvd
  ];
}
