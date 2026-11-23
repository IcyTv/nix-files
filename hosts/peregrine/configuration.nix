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
  # a per-user stamp file under /run (tmpfs, so reboot clears it for free):
  # sudo/polkit touch it when a session opens (fingerprint or password, once
  # already open) and swaylock only ever reads it. pam_timestamp.so looked
  # like a drop-in fit for this but turned out to scope its own timestamp
  # file to the controlling tty (mirroring sudo's own per-terminal credential
  # cache), so a stamp from one terminal was invisible to any other -- hence
  # this hand-rolled version keyed on $PAM_USER alone.
  fprintGateDir = "/run/fprint-gate";
  fprintGateCheck = timeoutMinutes:
    pkgs.writeShellScript "fprint-gate-check" ''
      [ -n "$PAM_USER" ] || exit 1
      found=$(${pkgs.findutils}/bin/find ${fprintGateDir} -maxdepth 1 -name "$PAM_USER" -mmin -${toString timeoutMinutes} 2>/dev/null)
      [ -n "$found" ]
    '';
  fprintGateStampScript = pkgs.writeShellScript "fprint-gate-stamp" ''
    [ -n "$PAM_USER" ] || exit 0
    : > "${fprintGateDir}/$PAM_USER"
  '';
  fprintGateInvalidateScript = pkgs.writeShellScript "fprint-gate-invalidate" ''
    [ -n "$PAM_USER" ] || exit 0
    ${pkgs.coreutils}/bin/rm -f "${fprintGateDir}/$PAM_USER"
  '';

  fprintGateAuth = timeoutMinutes: fprintdOrder: {
    order = fprintdOrder - 1;
    control = "[success=ignore default=1]";
    modulePath = "${pamPkg}/lib/security/pam_exec.so";
    args = ["quiet" "${fprintGateCheck timeoutMinutes}"];
  };
  fprintGateStamp = unixSessionOrder: {
    order = unixSessionOrder + 5;
    control = "optional";
    modulePath = "${pamPkg}/lib/security/pam_exec.so";
    # seteuid: the file must be owned by the target user, not root, so the
    # user's own unprivileged lock/logout hooks can delete it later despite
    # the sticky bit on fprintGateDir.
    args = ["quiet" "seteuid" "${fprintGateStampScript}"];
  };
  # No realistic sudo/polkit session lasts this long; it's effectively
  # "until the gate is explicitly invalidated", not a real timeout.
  noExpiryMinutes = 7 * 24 * 60;
  swaylockGraceMinutes = 60;
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

  # services.fprintd.enable defaults fprintAuth to true for every PAM service
  # (login, su, sshd, greetd, ...), not just the ones we explicitly configure
  # below. Force it off everywhere by default so only sudo/polkit-1/swaylock
  # (which get the gate) and whatever explicitly opts in end up with it.
  options.security.pam.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config.fprintAuth = lib.mkDefault false;
    });
  };

  config = {
    icy = {
      internal.core.enable = true;
      user.name = m.username;
      repository = "/etc/nixos/nix-files";
      sharedRepository = true;
    };

    services.fprintd.enable = true;
    services.hardware.bolt.enable = true;
    services.fwupd.enable = true;

    # Sticky + world-writable, like /tmp: any user may create/delete their
    # own "$username" entry, but not another user's.
    systemd.tmpfiles.rules = ["d ${fprintGateDir} 1777 root root -"];

    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
      HandleLidSwitchDocked = "suspend-then-hibernate";
    };
    systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

    security.pam.services = {
      sudo = {
        fprintAuth = true;
        rules.auth.fprintGate = fprintGateAuth noExpiryMinutes config.security.pam.services.sudo.rules.auth.fprintd.order;
        rules.session.fprintGateStamp = fprintGateStamp config.security.pam.services.sudo.rules.session.unix.order;
      };
      polkit-1 = {
        fprintAuth = true;
        rules.auth.fprintGate = fprintGateAuth noExpiryMinutes config.security.pam.services.polkit-1.rules.auth.fprintd.order;
        rules.session.fprintGateStamp = fprintGateStamp config.security.pam.services.polkit-1.rules.session.unix.order;
      };
      swaylock = {
        fprintAuth = true;
        # Read-only: swaylock never opens a session, so it can't refresh the
        # gate itself. The window is "time since the last real sudo/polkit/login
        # auth", not "time since the last screen unlock" (see memory on this).
        rules.auth.fprintGate = fprintGateAuth swaylockGraceMinutes config.security.pam.services.swaylock.rules.auth.fprintd.order;
      };
      # Invalidate the gate when the login session actually ends (not just a
      # screen lock). Reboot already clears it for free since /run is tmpfs.
      greetd.rules.session.fprintGateInvalidate = {
        order = config.security.pam.services.greetd.rules.session.unix.order + 5;
        control = "optional";
        modulePath = "${pamPkg}/lib/security/pam_exec.so";
        args = ["quiet" "type=close_session" "seteuid" "${fprintGateInvalidateScript}"];
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
  };
}
