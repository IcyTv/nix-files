{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: let
  m = builtins.fromJSON (builtins.readFile ./install.json);
  pamPkg = config.security.pam.package;

  # Fingerprint is only offered as an auth method for sudo/polkit/swaylock once
  # a real (non-fingerprint) authentication has already succeeded. The gate is
  # a shared pam_timestamp.so freshness check: sudo/polkit open a session on
  # success (fingerprint or password) which refreshes it indefinitely until the
  # screen locks, logs out, or the machine reboots; swaylock only ever reads it.
  fprintGateAuth = timeoutSeconds: fprintdOrder: {
    order = fprintdOrder - 1;
    control = "[success=ignore default=1]";
    modulePath = "${pamPkg}/lib/security/pam_timestamp.so";
    settings.timestamp_timeout = timeoutSeconds;
  };
  fprintGateStamp = unixSessionOrder: {
    order = unixSessionOrder + 5;
    control = "optional";
    modulePath = "${pamPkg}/lib/security/pam_timestamp.so";
  };
  # No realistic sudo/polkit session lasts this long; it's effectively
  # "until the gate is explicitly invalidated", not a real timeout.
  noExpiryTimeout = 60 * 60 * 24 * 7;
  swaylockGraceSeconds = 60 * 60; # 1 hour
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

  services.fprintd.enable = true;
  services.hardware.bolt.enable = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "suspend-then-hibernate";
  };
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  security.pam.services = {
    sudo = {
      fprintAuth = true;
      rules.auth.fprintGate = fprintGateAuth noExpiryTimeout config.security.pam.services.sudo.rules.auth.fprintd.order;
      rules.session.fprintGateStamp = fprintGateStamp config.security.pam.services.sudo.rules.session.unix.order;
    };
    polkit-1 = {
      fprintAuth = true;
      rules.auth.fprintGate = fprintGateAuth noExpiryTimeout config.security.pam.services.polkit-1.rules.auth.fprintd.order;
      rules.session.fprintGateStamp = fprintGateStamp config.security.pam.services.polkit-1.rules.session.unix.order;
    };
    swaylock = {
      fprintAuth = true;
      # Read-only: swaylock never opens a session, so it can't refresh the
      # gate itself. The window is "time since the last real sudo/polkit/login
      # auth", not "time since the last screen unlock" (see memory on this).
      rules.auth.fprintGate = fprintGateAuth swaylockGraceSeconds config.security.pam.services.swaylock.rules.auth.fprintd.order;
    };
    # Invalidate the gate when the login session actually ends (not just a
    # screen lock). Reboot already clears it for free since /run is tmpfs.
    greetd.rules.session.fprintGateInvalidate = {
      order = config.security.pam.services.greetd.rules.session.unix.order + 5;
      control = "optional";
      modulePath = "${pamPkg}/lib/security/pam_exec.so";
      args = ["quiet" "type=close_session" "${pamPkg}/bin/pam_timestamp_check" "-k"];
    };
  };

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
  environment.pathsToLink = ["/share/applications" "/share/xdg-desktop-portal"];
  system.stateVersion = m.stateVersion;
}
