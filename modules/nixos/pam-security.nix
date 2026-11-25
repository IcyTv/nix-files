{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.icy.internal.pamSecurity;
  pamPkg = config.security.pam.package;

  # Fingerprint is only offered as an auth method for sudo/polkit/frostguard
  # once a real (non-fingerprint) authentication has already succeeded. The
  # gate is a per-user stamp file under /run (tmpfs, so reboot clears it for
  # free). pam_timestamp.so looked like a drop-in fit for this but turned out
  # to scope its own timestamp file to the controlling tty (mirroring sudo's
  # own per-terminal credential cache), so a stamp from one terminal was
  # invisible to any other -- hence this hand-rolled version keyed on
  # $PAM_USER alone.
  #
  # Two independent gates, not one shared one:
  #   - fprintGateDir: sudo/polkit-1. Stamped only by a real sudo/polkit
  #     password auth (never by frostguard); closed both at logout and at
  #     every screen lock, so locking always forces a real re-auth for
  #     privilege escalation.
  #   - lockscreenGateDir: frostguard. Stamped by frostguard itself on any
  #     successful unlock, password or biometric; closed only at logout, not
  #     at lock -- otherwise the gate frostguard depends on would be shut
  #     before frostguard even started probing, and fingerprint/Howdy could
  #     never fire on the lock screen at all. See crates/lockscreen in the
  #     subniri repo for the write side.
  # Sharing one gate between both used to seem like the simpler option, but
  # it made the two consumers' invalidation needs mutually exclusive.
  #
  # Writers run as whatever uid happens to be doing the authenticating:
  # sudo's real uid is the target user, but polkit-1's auth check runs
  # inside polkitd, which on this system is an unprivileged "polkituser",
  # not root -- so no writer here can be assumed to have chown/CAP_CHOWN.
  # Every write chmods its own file to 666 right after creating it (always
  # permitted: you own whatever you just created, regardless of your uid),
  # so any *later* write from a different uid can still truncate it.
  # "Invalidate" therefore can't mean unlink either -- the sticky bit still
  # blocks a non-owner (or non-root) from deleting someone else's file even
  # once it's 666. Instead it's a same-trick second marker file; gate-check
  # requires the stamp to both be fresh *and* newer than that marker.
  fprintGateDir = "/run/fprint-gate";
  lockscreenGateDir = "/run/lockscreen-gate";
  gateDirs = [fprintGateDir lockscreenGateDir];

  worldWritableTouch = pkgs.writeShellScript "fprint-gate-touch" ''
    f="$1"
    : > "$f" 2>/dev/null || exit 0
    ${pkgs.coreutils}/bin/chmod 666 "$f" 2>/dev/null || true
  '';
  mkGateCheck = dir: timeoutMinutes:
    pkgs.writeShellScript "fprint-gate-check" ''
      [ -n "$PAM_USER" ] || exit 1
      stamp="${dir}/$PAM_USER"
      closed="${dir}/$PAM_USER.closed"
      [ -e "$stamp" ] || exit 1
      found=$(${pkgs.findutils}/bin/find "$stamp" -maxdepth 0 -mmin -${toString timeoutMinutes} 2>/dev/null)
      [ -n "$found" ] || exit 1
      if [ -e "$closed" ] && [ "$closed" -nt "$stamp" ]; then
        exit 1
      fi
    '';
  # Always exits 0: this sits on the real-password success path (see
  # fprintGateAuthStamp below), and a transient /run write failure must not
  # turn a correct password into a denial.
  fprintGateStampScript = pkgs.writeShellScript "fprint-gate-stamp" ''
    if [ -n "$PAM_USER" ]; then
      ${worldWritableTouch} "${fprintGateDir}/$PAM_USER"
    fi
    exit 0
  '';
  # Closes every gate at once: a full logout should invalidate frostguard's
  # unlock stamp exactly as much as sudo/polkit-1's, even though only the
  # latter is also closed on every lock (see the comment above).
  invalidateAllGatesScript = pkgs.writeShellScript "fprint-gate-invalidate-all" ''
    [ -n "$PAM_USER" ] || exit 0
    ${lib.concatMapStringsSep "\n" (dir: ''${worldWritableTouch} "${dir}/$PAM_USER.closed"'') gateDirs}
  '';

  mkGateAuth = dir: timeoutMinutes: fprintdOrder: {
    order = fprintdOrder - 1;
    control = "[success=ignore default=1]";
    modulePath = "${pamPkg}/lib/security/pam_exec.so";
    args = ["quiet" "${mkGateCheck dir timeoutMinutes}"];
  };
  fprintGateAuth = mkGateAuth fprintGateDir;
  lockscreenGateAuth = mkGateAuth lockscreenGateDir;
  # sudo -v/polkit checks never open a PAM session (only a real privileged
  # command does), so the stamp can't live in the session phase. Instead,
  # flip the existing "unix" auth rule from plain `sufficient` to a jump that
  # falls through to this stamp-and-succeed line on a correct password, and
  # skips it (going straight to the pre-existing deny) on a wrong one -- the
  # same verified [success=ignore default=1] + sufficient pair reused below
  # for howdy's own confirmation step.
  ignoreThenJump = "[success=ignore default=1]";
  fprintGateAuthStamp = unixAuthOrder: {
    order = unixAuthOrder + 1;
    control = "sufficient";
    modulePath = "${pamPkg}/lib/security/pam_exec.so";
    args = ["quiet" "${fprintGateStampScript}"];
  };

  # A fingerprint touch gives the user a deliberate moment to notice and
  # cancel an unwanted polkit prompt; Howdy's face match doesn't -- it can
  # succeed the instant a face is in frame, with no action and no time to
  # react. PAM itself has no concept of "passive" vs "interactive" auth (a
  # `sufficient` success never tells the caller which module produced it),
  # so this tags Howdy's success explicitly: pam_echo.so prints a fixed
  # marker string through the PAM conversation right after howdy's own line
  # (flipped from plain `sufficient` to the same ignore-then-jump trick
  # above, so its failure still falls through normally). thawth (see
  # crates/polkit-agent/src/conversation.rs) watches for this exact string
  # and, on seeing it, holds the already-successful result behind an
  # explicit "Authorize" button instead of reporting it straight to polkit.
  howdyConfirmMarker = "subniri:howdy";
  howdyConfirmMarkerFile = pkgs.writeText "thawth-howdy-confirm-marker" howdyConfirmMarker;
in {
  options.icy.internal.pamSecurity = {
    enable = lib.mkEnableOption "the fingerprint/facial-recognition PAM gate for sudo, polkit-1, and frostguard";

    fingerprint.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wire fprintd into sudo/polkit-1/frostguard, each gated behind a stamp
        left by a prior real (password) authentication. Disable on hosts
        with no fingerprint reader.
      '';
    };

    # No realistic sudo/polkit session lasts this long; it's effectively
    # "until the gate is explicitly invalidated", not a real timeout.
    noExpiryMinutes = lib.mkOption {
      type = lib.types.int;
      default = 7 * 24 * 60;
      description = "How long the real-auth stamp stays valid for sudo/polkit-1.";
    };

    lockscreenGraceMinutes = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "How long frostguard's own unlock stamp stays valid before a password is required again.";
    };

    howdy = {
      enable = lib.mkEnableOption ''
        Howdy facial recognition as a gated fast path on polkit-1 and
        frostguard, reusing the same real-auth stamp as fingerprint. Never
        wired into sudo -- that path should always keep the moment of
        friction a fingerprint/password forces, not a frictionless camera
        glance
      '';

      videoDevice = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/dev/video2";
        description = ''
          The IR-capable camera device node for Howdy to use, as identified
          by running `linux-enable-ir-emitter configure`.
        '';
      };
    };
  };

  # services.fprintd.enable/services.howdy.enable both default their PAM
  # auth (fprintAuth/howdy.enable) to true for every PAM service (login, su,
  # sshd, greetd, ...), not just the ones configured below. Force both off
  # everywhere by default so only sudo/polkit-1/frostguard (which get the
  # gate) end up with them.
  options.security.pam.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config.fprintAuth = lib.mkDefault false;
      config.howdy.enable = lib.mkDefault false;
    });
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.howdy.enable || cfg.howdy.videoDevice != null;
          message = "icy.internal.pamSecurity.howdy.enable requires icy.internal.pamSecurity.howdy.videoDevice to be set.";
        }
      ];

      # Sticky + world-writable, like /tmp: any user may create/delete
      # their own "$username" entry, but not another user's.
      systemd.tmpfiles.rules = map (dir: "d ${dir} 1777 root root -") gateDirs;

      # Invalidate every gate when the login session actually ends (not
      # just a screen lock -- see the comment on gateDirs above for why
      # lockscreenGateDir specifically is *not* also closed on every lock).
      # Reboot already clears both for free since /run is tmpfs.
      security.pam.services.greetd.rules.session.fprintGateInvalidate = {
        order = config.security.pam.services.greetd.rules.session.unix.order + 5;
        control = "optional";
        modulePath = "${pamPkg}/lib/security/pam_exec.so";
        args = ["quiet" "type=close_session" "${invalidateAllGatesScript}"];
      };
    })

    (lib.mkIf (cfg.enable && cfg.fingerprint.enable) {
      services.fprintd.enable = true;

      security.pam.services = {
        sudo = {
          fprintAuth = true;
          rules.auth.fprintGate = fprintGateAuth cfg.noExpiryMinutes config.security.pam.services.sudo.rules.auth.fprintd.order;
          rules.auth.unix.control = lib.mkForce ignoreThenJump;
          rules.auth.fprintGateStamp = fprintGateAuthStamp config.security.pam.services.sudo.rules.auth.unix.order;
        };
        polkit-1 = {
          fprintAuth = true;
          rules.auth.fprintGate = fprintGateAuth cfg.noExpiryMinutes config.security.pam.services.polkit-1.rules.auth.fprintd.order;
          rules.auth.unix.control = lib.mkForce ignoreThenJump;
          rules.auth.fprintGateStamp = fprintGateAuthStamp config.security.pam.services.polkit-1.rules.auth.unix.order;
        };
        frostguard = {
          fprintAuth = true;
          # frostguard's own gate (see gateDirs above): stamped by
          # frostguard itself on any successful unlock, so the window is
          # "time since the last unlock of any kind", not "time since the
          # last real sudo/polkit/login auth".
          rules.auth.fprintGate = lockscreenGateAuth cfg.lockscreenGraceMinutes config.security.pam.services.frostguard.rules.auth.fprintd.order;
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.howdy.enable) {
      # IR support that howdy's face recognition relies on; kept alongside
      # it rather than split out since the two are a matched pair.
      services.linux-enable-ir-emitter.enable = true;
      services.howdy = {
        enable = true;
        settings.video.device_path = cfg.howdy.videoDevice;
      };

      # polkit-agent-helper@.service (where polkit-1's PAM stack, and so
      # pam_howdy, actually runs) ships from nixpkgs with PrivateDevices=yes
      # and DeviceAllow restricted to /dev/null -- unlike fprintd, which is a
      # separate root daemon reached over D-Bus, howdy has no daemon of its
      # own and opens the camera device directly from inside whatever
      # process is running the PAM stack. Without this, every polkit-1
      # Howdy attempt fails with "not possible to open camera at configured
      # path", regardless of which agent (GNOME's, thawth, ...) asked for
      # it, since both are just clients of this same shared helper.
      # BindPaths re-exposes the one device node into its otherwise-private
      # /dev; DeviceAllow grants the matching cgroup permission -- neither
      # alone is sufficient, and everything else about the service stays as
      # hardened as upstream ships it.
      systemd.services."polkit-agent-helper@".serviceConfig = {
        BindPaths = [cfg.howdy.videoDevice];
        DeviceAllow = ["${cfg.howdy.videoDevice} rw"];
      };

      # Same gate as fprintd, reusing the same stamp -- howdy is just
      # another fast path offered only after a real auth already happened
      # once, never an alternative to one.
      #
      # Ordered ahead of fprintd (order - 3, leaving room for its own gate
      # at - 4 below it, and the confirmation marker at - 2 right above
      # it): a camera glance needs no touch, so give it first try and fall
      # back to the fingerprint reader -- then password -- only if no face
      # is recognized in time. Relative offset from fprintd's own order,
      # per nixpkgs' own warning on this option: never hardcode an
      # absolute value, a nixpkgs update could silently reorder the
      # built-in rules.
      security.pam.services = {
        polkit-1 = {
          howdy.enable = true;
          # Flipped from plain `sufficient`: a bare face match is never
          # reported to polkit on its own, see howdyConfirmMarker above.
          howdy.control = ignoreThenJump;
          rules.auth.howdy.order = lib.mkForce (config.security.pam.services.polkit-1.rules.auth.fprintd.order - 3);
          rules.auth.howdyConfirm = {
            order = config.security.pam.services.polkit-1.rules.auth.howdy.order + 1;
            control = "sufficient";
            modulePath = "${pamPkg}/lib/security/pam_echo.so";
            args = ["file=${howdyConfirmMarkerFile}"];
          };
          # Skips 2, not the usual 1: a closed gate must also skip past
          # howdyConfirm right below howdy, or pam_echo (which always
          # "succeeds") would run unconditionally and report a face match
          # that never actually happened.
          rules.auth.howdyGate =
            (fprintGateAuth cfg.noExpiryMinutes config.security.pam.services.polkit-1.rules.auth.howdy.order)
            // {
              control = "[success=ignore default=2]";
            };
        };
        frostguard = {
          howdy.enable = true;
          howdy.control = "sufficient";
          rules.auth.howdy.order = lib.mkForce (config.security.pam.services.frostguard.rules.auth.fprintd.order - 2);
          rules.auth.howdyGate = lockscreenGateAuth cfg.lockscreenGraceMinutes config.security.pam.services.frostguard.rules.auth.howdy.order;
        };
      };
    })
  ];
}
