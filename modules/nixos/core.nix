{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  options.my.nixos.core.enable = lib.mkEnableOption "Core NixOS configuration";

  config = lib.mkIf config.my.nixos.core.enable {
    nix.settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org/"
        "https://icytv.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrURkbJ16ZMNQvspzbCZP16Q="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "icytv.cachix.org-1:epXlDqA5apfoHPIc+Z7Vx6aPN7Tsz2hzik62V5Rs5sQ="
      ];
    };
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
