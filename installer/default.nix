{
  pkgs,
  source,
}:
pkgs.writeShellApplication {
  name = "run-installer";
  runtimeInputs = with pkgs; [
    python3
    gum
    git
    git-lfs
    git-crypt
    curl
    nix
    nixos-install-tools
    util-linux
    btrfs-progs
    cryptsetup
    systemd
    gnupg
    pinentry-curses
    age
    pciutils
    usbutils
    yubikey-manager
    libfido2
    acl
    coreutils
    findutils
    psmisc
    shadow
  ];
  runtimeEnv.ICY_INSTALLER_SOURCE = source;
  text = ''
    exec python3 ${./.}/main.py "$@"
  '';
}
