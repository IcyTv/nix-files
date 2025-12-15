{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    neovim
    kitty
    xdg-utils
    git
    wl-clipboard
  ];

  services.flatpak.enable = true;
}
