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
  # Always exits 0: this sits on the real-password success path (see
  # fprintGateAuthStamp below), and a transient /run write failure must not
  # turn a correct password into a denial.
  #
  # chown to $PAM_USER explicitly rather than relying on the calling
  # process's uid: sudo's real uid is already the target user (so this is a
  # no-op there), but polkit-1's auth check runs inside polkitd, a daemon
  # that is always root regardless of who's authenticating. Without this the
  # stamp ends up root-owned, and the sticky bit then blocks the user's own
  # unprivileged lock/logout invalidation from ever deleting it.
  fprintGateStampScript = pkgs.writeShellScript "fprint-gate-stamp" ''
    if [ -n "$PAM_USER" ]; then
      f="${fprintGateDir}/$PAM_USER"
      : > "$f" 2>/dev/null || true
      ${pkgs.coreutils}/bin/chown "$PAM_USER" "$f" 2>/dev/null || true
    fi
    exit 0
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
  # sudo -v/polkit checks never open a PAM session (only a real privileged
  # command does), so the stamp can't live in the session phase. Instead,
  # flip the existing "unix" auth rule from plain `sufficient` to a jump that
  # falls through to this stamp-and-succeed line on a correct password, and
  # skips it (going straight to the pre-existing deny) on a wrong one -- the
  # same verified [success=ignore default=1] + sufficient pair already used
  # for fprintGate itself, just gating the password line instead of fprintd.
  fprintGateUnixControl = "[success=ignore default=1]";
  fprintGateAuthStamp = unixAuthOrder: {
    order = unixAuthOrder + 1;
    control = "sufficient";
    modulePath = "${pamPkg}/lib/security/pam_exec.so";
    args = ["quiet" "${fprintGateStampScript}"];
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

    security.pam.services = {
      sudo = {
        fprintAuth = true;
        rules.auth.fprintGate = fprintGateAuth noExpiryMinutes config.security.pam.services.sudo.rules.auth.fprintd.order;
        rules.auth.unix.control = lib.mkForce fprintGateUnixControl;
        rules.auth.fprintGateStamp = fprintGateAuthStamp config.security.pam.services.sudo.rules.auth.unix.order;
      };
      polkit-1 = {
        fprintAuth = true;
        rules.auth.fprintGate = fprintGateAuth noExpiryMinutes config.security.pam.services.polkit-1.rules.auth.fprintd.order;
        rules.auth.unix.control = lib.mkForce fprintGateUnixControl;
        rules.auth.fprintGateStamp = fprintGateAuthStamp config.security.pam.services.polkit-1.rules.auth.unix.order;
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
        args = ["quiet" "type=close_session" "${fprintGateInvalidateScript}"];
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
