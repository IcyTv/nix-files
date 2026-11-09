{
  config,
  lib,
  pkgs,
  ...
}: let
  check = pkgs.writeShellScript "check-btrfs-resume" ''
    set -eu
    actual=$(${pkgs.btrfs-progs}/bin/btrfs inspect-internal map-swapfile -r /swap/swapfile)
    booted=""
    for arg in $(cat /proc/cmdline); do
      case "$arg" in resume_offset=*) booted="''${arg#resume_offset=}" ;; esac
    done
    if [ -z "$booted" ] || [ "$actual" != "$booted" ]; then
      echo 'Refusing hibernation: swapfile offset differs from booted resume configuration. Refresh offset, rebuild and reboot.' >&2
      exit 1
    fi
  '';
in {
  # Old boot generations must not hibernate into a recreated/relocated swapfile.
  systemd.services =
    lib.mkIf (config.boot.resumeDevice != "")
    (lib.genAttrs ["systemd-hibernate" "systemd-hybrid-sleep" "systemd-suspend-then-hibernate"]
      (_: {serviceConfig.ExecStartPre = [check];}));
}
