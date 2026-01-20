{pkgs, ...}: {
  services.mpris-proxy.enable = true;

  home.packages = [
    pkgs.bluetuith
  ];
}
