{...}: {
  hardware.bluetooth.enable = true;

  services.pipewire.wireplumber.extraConfig."11-bleutooth-policy" = {
    "wireplumber.settings" = {
      "bluetooth.autoswitch-to-headset-profile" = false;
    };
  };
}
