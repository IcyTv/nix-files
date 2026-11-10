{
  config,
  lib,
  pkgs,
  ...
}: let
  driver = pkgs.callPackage ./package.nix {};
in {
  # Enabling fprintd normally enables fingerprint PAM for every service.
  # Keep this daemon-only trial opt-out by default, including future services.
  options.security.pam.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config.fprintAuth = lib.mkDefault false;
    });
  };

  config = {
    services.fprintd = {
      enable = true;
      # Keep the current daemon rather than the older fprintd-tod package.
      package = pkgs.fprintd.override {libfprint = pkgs.libfprint-tod;};
      tod = {
        enable = true;
        inherit driver;
      };
    };

    environment.systemPackages = [driver];
    systemd.tmpfiles.rules = ["d /var/lib/fpdrv 0700 root root -"];

    assertions = [
      {
        assertion = lib.all (service: !service.fprintAuth) (lib.attrValues config.security.pam.services);
        message = "The Kestrel fingerprint daemon trial must not enable fingerprint PAM authentication.";
      }
    ];
  };
}
