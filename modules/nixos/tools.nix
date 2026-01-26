{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    neovim
    kitty
    xdg-utils
    git
    wl-clipboard
    lm_sensors
  ];

  services.gvfs.enable = true;

  services.flatpak.enable = true;
  programs.coolercontrol.enable = true;
}
