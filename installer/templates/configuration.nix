{
  inputs,
  lib,
  pkgs,
  ...
}: let
  m = builtins.fromJSON (builtins.readFile ./install.json);
in {
  imports = [
    ../../modules/nixos/default.nix
    ../../installer/hibernation.nix
    ./hardware-configuration.nix
    ./hardware-options.nix
    ./disk-config.nix
    (builtins.fromJSON (builtins.readFile ./system-options.json))
    (builtins.fromJSON (builtins.readFile ./resume.json))
  ];
  icy = {
    internal.core.enable = true;
    user.name = m.username;
    repository = "/etc/nixos/nix-files";
    sharedRepository = true;
  };
  networking.hostName = m.hostname;
  time.timeZone = lib.mkForce m.timezone;
  i18n.defaultLocale = lib.mkForce m.locale;
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages;
  boot.initrd.systemd.enable = true;
  users.users.root.hashedPassword = "!";
  users.users.${m.username}.uid = 1000;
  security.sudo.enable = lib.mkDefault true;
  home-manager.users.${m.username} = import ./home.nix;
  environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];
  system.stateVersion = m.stateVersion;
}
