{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.hm.hyprland.enable = lib.mkEnableOption "Hyprland Wayland compositor home-manager configuration";

  config = lib.mkIf config.my.hm.hyprland.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        input = {
          kb_layout = "us";
          kb_variant = "altgr-intl";
          kb_options = "caps:escape_shifted_capslock";
          accel_profile = "flat";
          follow_mouse = 1;
        };

        general = {
          gaps_in = 2;
          gaps_out = 4;
          border_size = 2;
          layout = "dwindle";
        };

        decoration = {
          rounding = 12;
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        exec-once = [
          "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland"
          "spotify"
          "vesktop"
        ];

        "$mod" = "SUPER";

        bind =
          [
            "$mod, Return, exec, ${
              if config.my.hm.ghostty.enable
              then "ghostty"
              else "kitty"
            }"
            "$mod, Space, exec, anyrun"
            "$mod, B, exec, firefox"
            "$mod, E, exec, thunar"
            "$mod ALT, L, exec, ${pkgs.swaylock}/bin/swaylock"

            "$mod, Q, killactive,"
            "$mod, F, fullscreen,"
            "$mod, V, togglefloating,"

            "$mod, Left, movefocus, l"
            "$mod, Right, movefocus, r"
            "$mod, Up, movefocus, u"
            "$mod, Down, movefocus, d"
            "$mod, H, movefocus, l"
            "$mod, L, movefocus, r"
            "$mod, K, movefocus, u"
            "$mod, J, movefocus, d"

            "$mod CTRL, Left, movewindow, l"
            "$mod CTRL, Right, movewindow, r"
            "$mod CTRL, Up, movewindow, u"
            "$mod CTRL, Down, movewindow, d"
            "$mod CTRL, H, movewindow, l"
            "$mod CTRL, L, movewindow, r"
            "$mod CTRL, K, movewindow, u"
            "$mod CTRL, J, movewindow, d"

            "$mod SHIFT, Left, focusmonitor, l"
            "$mod SHIFT, Right, focusmonitor, r"
            "$mod SHIFT, H, focusmonitor, l"
            "$mod SHIFT, L, focusmonitor, r"

            "$mod ALT, Up, workspace, e-1"
            "$mod ALT, Down, workspace, e+1"
            "$mod ALT, K, workspace, e-1"
            "$mod ALT, J, workspace, e+1"
          ]
          ++ (
            builtins.concatLists (builtins.genList (
                x: let
                  ws = let
                    c = (x + 1) / 10;
                  in
                    builtins.toString (x + 1 - (c * 10));
                in [
                  "$mod, ${ws}, workspace, ${toString (x + 1)}"
                  "$mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}"
                ]
              )
              10)
          );

        bindl = [
          ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01+"
          ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01-"
          ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ", XF86AudioMicMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ];

        windowrulev2 = [
          "float, class:^(firefox)$, title:^(Picture-in-Picture)$"
          "workspace 9 silent, class:^(Spotify)$"
          "workspace 9 silent, class:^(vesktop)$"
          "suppressevent maximize, class:.*"
        ];

        env = [
          "XCURSOR_THEME,WhiteSur-cursors"
          "XCURSOR_SIZE,16"
        ];
      };
    };

    home.packages = [
      pkgs.xwayland-satellite
      pkgs.dex
    ];
  };
}
