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
      configType = "lua";

      package = null;
      portalPackage = null;

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
          layout = "scrolling";
        };

        scrolling = {
          column_width = 0.666667;
          explicit_column_widths = "0.333333, 0.500000, 0.666667, 1.000000";
          focus_fit_method = 1;
          fullscreen_on_one_column = true;
          direction = "right";
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
        ];

        windowrule = [
          "float on, match:class ^(firefox)$ match:title ^(Picture-in-Picture)$"

          "maximize on, match:class ^(kitty)$"
          "maximize on, match:class ^(com.mitchellh.ghostty)$"
          "maximize on, match:class ^(firefox-yes)$"

          "monitor HDMI-A-1, match:class ^(Spotify)$"
          "monitor HDMI-A-1, match:class ^(discord)$"

          "float on, match:class ^(steam)$, match:title ^(notificationtoasts)"
          "no_initial_focus on, match:class ^(steam)$, match:title ^(notificationtoasts)"
          "no_screen_share on, match:class ^(steam)$, match:title ^(notificationtoasts)"
          "move (monitor_w-window_w-8) 8, match:class ^(steam)$, match:title ^(notificationtoasts)"
        ];

        layerrule = [
          "order -1, match:namespace ^(swww-daemon)$"
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
            "$mod, M, fullscreen, 1"

            # Column Focus (Traps focus within layout)
            "$mod, H, layoutmsg, focus l"
            "$mod, L, layoutmsg, focus r"
            "$mod, Left, layoutmsg, focus l"
            "$mod, Right, layoutmsg, focus r"

            # Window Focus (Up/Down within stack)
            "$mod, K, movefocus, u"
            "$mod, J, movefocus, d"
            "$mod, Up, movefocus, u"
            "$mod, Down, movefocus, d"

            # Moving Columns & Windows
            "$mod CTRL, H, layoutmsg, swapcol l"
            "$mod CTRL, L, layoutmsg, swapcol r"
            "$mod CTRL, Left, layoutmsg, swapcol l"
            "$mod CTRL, Right, layoutmsg, swapcol r"
            "$mod CTRL, J, movewindow, d"
            "$mod CTRL, K, movewindow, u"

            # Expel/Consume logic
            "$mod, BracketLeft, movewindow, l"
            "$mod, BracketRight, movewindow, r"
            "$mod SHIFT, BracketRight, layoutmsg, promote"

            # Column Resizing & Presets
            "$mod, Plus, layoutmsg, colresize +0.1"
            "$mod, Minus, layoutmsg, colresize -0.1"
            "$mod, R, layoutmsg, colresize +conf"
            "$mod SHIFT, R, layoutmsg, colresize -conf"

            # Centering/Fit Control
            "$mod, C, layoutmsg, togglefit"
            "$mod CTRL, C, layoutmsg, fit visible"

            # Monitor Focus Movement
            "$mod SHIFT, H, focusmonitor, l"
            "$mod SHIFT, L, focusmonitor, r"
            "$mod SHIFT, Left, focusmonitor, l"
            "$mod SHIFT, Right, focusmonitor, r"

            # System Actions

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

        bindel = [
          ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01+"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.01-"
        ];
        bindl = [
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ];

        bindm = [
          "$mod,mouse:272,movewindow"
          "$mod,mouse:273,resizewindow"
        ];

        # windowrulev2 = [
        #   "float, class:^(firefox)$, title:^(Picture-in-Picture)$"
        #   "workspace 9 silent, class:^(Spotify)$"
        #   "workspace 9 silent, class:^(vesktop)$"
        #   "suppressevent maximize, class:.*"
        # ];

        env = [
          "XCURSOR_THEME,WhiteSur-cursors"
          "XCURSOR_SIZE,16"
          "HYPRCURSOR_SIZE,16"
        ];
      };
    };

    home.packages = [
      pkgs.xwayland-satellite
      pkgs.dex
    ];
  };
}
