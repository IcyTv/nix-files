{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  options.my.nixos.core.enable = lib.mkEnableOption "Core NixOS configuration";

  config = lib.mkIf config.my.nixos.core.enable {
    nix.settings.auto-optimise-store = true;
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };

    nixpkgs.config.allowUnfree = true;

    networking.networkmanager.enable = true;

    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";

    services.xserver.enable = false;
    security.rtkit.enable = true;
    services.openssh.enable = true;

    users.users.michael = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.nushell;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {inherit inputs;};
      backupFileExtension = "bak";
    };
  };
}
