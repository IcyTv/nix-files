{
  pkgs,
  config,
  inputs,
  ...
}: let
  subniri = inputs.subniri.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  home.packages = [
    subniri
  ];

  xdg.dataFile."applications/subniri.desktop" = {
    enable = true;
    text = ''
      [Desktop Entry]
      Name=Niribar
      Exec=${subniri}/bin/subniri
      Type=Application
      Categories=Utility;
    '';
  };

  systemd.user.services.niribar = {
    Unit = {
      Description = "Shell for niri, written using Rust, Gtk and Astal 4";
      Documentation = "https://github.com/IcyTv/niribar";
      PartOf = [
        "tray.target"
        config.wayland.systemd.target
      ];
      After = [
        config.wayland.systemd.target
      ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${subniri}/bin/niribar";
      Restart = "on-failure";
    };

    Install.WantedBy = [
      config.wayland.systemd.target
      "tray.target"
    ];
  };
}
