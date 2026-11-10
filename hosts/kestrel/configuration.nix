{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./fingerprint
    ../../installer/hibernation.nix
    ../../modules/nixos/default.nix
  ];

  networking.hostName = "kestrel";

  icy.repository = "/etc/nixos/nix-files";
  icy.sharedRepository = true;
  icy.internal.core.enable = true;

  my.nixos = {
    ananicy.enable = true;
    bluetooth.enable = true;
    console-font.enable = true;
    docker.enable = true;
    geoclue.enable = true;
    greetd.enable = true;
    keyd.enable = true;
    keymap.enable = true;
    limine.enable = true;
    niri.enable = true;
    plymouth.enable = true;
    printing.enable = true;
    rebuild.enable = true;
    stylix.enable = true;
    sudo-rs.enable = true;
    tools.enable = true;
    zsh.enable = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "bak";

    users = {
      "michael" = import ./home.nix;
    };
  };

  boot.loader.limine.secureBoot.enable = false;
  boot.loader.limine.efiSupport = true;

  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [
    "fido2-device=auto"
    "fido2-with-client-pin=yes"
  ];

  boot.supportedFilesystems = ["btrfs"];

  swapDevices = [
    {device = "/swap/swapfile";}
  ];

  boot.resumeDevice = "/dev/mapper/cryptroot";
  boot.kernelParams = ["resume_offset=3248182"];

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "suspend-then-hibernate";
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  security.pam.services.swaylock = {};

  boot.kernelPackages = pkgs.linuxPackages;

  hardware.bluetooth.powerOnBoot = true;

  hardware.graphics.enable = true;

  networking.wireless.userControlled = true;

  networking.networkmanager.ensureProfiles.profiles.eduroam = {
    connection = {
      id = "eduroam";
      type = "wifi";
      autoconnect = false;
    };

    wifi = {
      mode = "infrastructure";
      ssid = "eduroam";
    };

    wifi-security.key-mgmt = "wpa-eap";

    "802-1x" = {
      eap = "ttls;";
      anonymous-identity = "anonymous@kit.edu";
      identity = "uyhum@kit.edu";
      domain-match = "radius-wlan.scc.kit.edu";
      ca-cert = "/etc/ssl/certs/ca-certificates.crt";
      phase2-auth = "pap";
      # Ask on each connection; never persist the password.
      password-flags = 2;
    };

    ipv4.method = "auto";
    ipv6.method = "auto";
  };

  system.stateVersion = "26.05";
}
