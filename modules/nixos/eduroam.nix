{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.nixos.eduroam;

  eduroamProfile = (pkgs.formats.ini {}).generate "eduroam.nmconnection" {
    connection = {
      id = "eduroam";
      uuid = "e0ca8591-5948-3c69-8474-f35bc56aff0d";
      type = "wifi";
      autoconnect = true;
    };

    wifi = {
      mode = "infrastructure";
      ssid = "eduroam";
    };

    wifi-security.key-mgmt = "wpa-eap";

    "802-1x" = {
      eap = "ttls;";
      anonymous-identity = cfg.anonymousIdentity;
      identity = cfg.identity;
      domain-match = cfg.domainMatch;
      ca-cert = "/etc/ssl/certs/ca-certificates.crt";
      phase2-auth = "pap";
      # NetworkManager stores the password in its root-only system profile.
      password-flags = 0;
    };

    ipv4.method = "auto";
    ipv6.method = "auto";
  };
in {
  options.my.nixos.eduroam = {
    enable = lib.mkEnableOption "Eduroam NetworkManager connection profile";

    identity = lib.mkOption {
      type = lib.types.str;
      description = "EAP identity (university username), e.g. \"uyhum@kit.edu\".";
    };

    anonymousIdentity = lib.mkOption {
      type = lib.types.str;
      default = "anonymous@kit.edu";
      description = "EAP anonymous identity used for the outer TTLS tunnel.";
    };

    domainMatch = lib.mkOption {
      type = lib.types.str;
      default = "radius-wlan.scc.kit.edu";
      description = "Expected RADIUS server certificate domain.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /etc/NetworkManager/system-connections 0700 root root -"
      # Seed only once: rebuilds must not overwrite NetworkManager's saved password.
      "C /etc/NetworkManager/system-connections/eduroam.nmconnection 0600 root root - ${eduroamProfile}"
    ];
  };
}
