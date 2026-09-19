{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  options.my.nixos.tools.enable = lib.mkEnableOption "Basic system tools and flatpak";

  config = lib.mkIf config.my.nixos.tools.enable {
    environment.systemPackages = with pkgs; [
      neovim
      xdg-utils
      git
      wl-clipboard
      lm_sensors
      inxi
      unar
      piper
      pipewire.jack
      yubikey-manager
    ];

    services.gvfs.enable = true;
    services.logiops.enable = true;
    services.pcscd.enable = true;

    hardware.gpgSmartcards.enable = true;

    services.udev.packages = [
      pkgs.yubikey-personalization
    ];

    services.flatpak.enable = true;
    programs.coolercontrol.enable = true;

    virtualisation.waydroid.enable = true;

    services.upower.enable = true;
    services.solaar.enable = true;
    services.ratbagd = {
      enable = true;
      package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libratbag;
    };
  };
}
