{
  inputs,
  lib,
  pkgs,
  config,
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

  config = {
    icy = {
      internal.core.enable = true;
      user.name = m.username;
      repository = "/etc/nixos/nix-files";
      sharedRepository = true;
    };

    icy.internal.pamSecurity = {
      enable = true;
      howdy = {
        enable = true;
        videoDevice = "/dev/video2"; # confirmed IR-capable node
      };
    };

    services.hardware.bolt.enable = true;
    services.fwupd.enable = true;

    # logind treats the system as "docked" whenever more than one display is
    # connected (e.g. an external monitor through the dock's DP output), not
    # just when a real docking-station sysfs entry is present -- so this
    # covers any dock that exposes a working display, not only the current
    # one. Closing the lid while docked should just let the external
    # monitor(s) keep running; only fall back to suspending when truly
    # undocked.
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
      HandleLidSwitchDocked = "ignore";
    };
    systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

    networking.hostName = m.hostname;
    time.timeZone = lib.mkForce m.timezone;
    i18n.defaultLocale = lib.mkForce m.locale;
    boot.loader.limine = {
      enable = true;
      efiSupport = true;
    };
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.limine.secureBoot.enable = true;
    boot.kernelPackages = pkgs.linuxPackages;
    boot.initrd.systemd.enable = true;
    users.users.root.hashedPassword = "!";
    users.users.${m.username}.uid = 1000;
    home-manager.users.${m.username} = import ./home.nix;
    # polkitd is a system daemon; it only scans environment.systemPackages'
    # /share/polkit-1/actions, never a per-user home-manager profile. Without
    # this, bitwarden-desktop's bundled com.bitwarden.Bitwarden.policy (in
    # home.nix's home.packages) is invisible to it, and "Unlock with system
    # authentication" in the app can never actually authorize.
    environment.systemPackages = [pkgs.bitwarden-desktop];
    environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];
    system.stateVersion = m.stateVersion;
  };
}
