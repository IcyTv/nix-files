{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.tools.enable = lib.mkEnableOption "Basic system tools and flatpak";

  config = lib.mkIf config.my.nixos.tools.enable {
    environment.systemPackages = with pkgs; [
      neovim
      kitty
      xdg-utils
      git
      wl-clipboard
      lm_sensors
      inxi
      unar
    ];

    services.gvfs.enable = true;

    services.flatpak.enable = true;
    programs.coolercontrol.enable = true;

    virtualisation.waydroid.enable = true;
  };
}
