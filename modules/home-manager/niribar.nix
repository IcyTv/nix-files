{
  pkgs,
  config,
  inputs,
  ...
}: let
  niribar = inputs.niribar.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  home.packages = [
    niribar
  ];

  xdg.dataFile."applications/niribar.desktop" = {
    enable = true;
    text = ''
      [Desktop Entry]
      Name=Niribar
      Exec=${niribar}/bin/niribar
      Type=Application
      Categories=Utility;
    '';
  };

  systemd.user.services.niribar = {
    Unit = {
      Description = "Bar for niri, written using Rust, Gtk and Astal 4";
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
      ExecStart = "${niribar}/bin/niribar";
      Restart = "on-failure";
    };

    Install.WantedBy = [
      config.wayland.systemd.target
      "tray.target"
    ];
  };
}
