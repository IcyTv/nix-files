{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.bluetooth.enable = lib.mkEnableOption "Bluetooth support";

  config = lib.mkIf config.my.nixos.bluetooth.enable {
    hardware.bluetooth.enable = true;

    # Unified Remote's Bluetooth backend still expects BlueZ SDP compatibility mode.
    systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.bluez}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf --compat"
    ];

    services.pipewire.wireplumber.extraConfig."11-bleutooth-policy" = {
      "wireplumber.settings" = {
        "bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
  };
}
