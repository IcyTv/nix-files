{
  lib,
  pkgs,
  ...
}: {
  programs.niri.settings = {
    prefer-no-csd = true;
    input = {
      keyboard.xkb = {
        layout = "us";
        variant = "altgr-intl";
        options = "caps:escape_shifted_capslock";
      };
      mouse.accel-profile = "flat";
      focus-follows-mouse = {
        enable = true;
        max-scroll-amount = "10%";
      };
    };

    gestures.hot-corners.enable = false;

    cursor = {
      theme = "WhiteSur-cursors";
      size = 16;
      hide-after-inactive-ms = 1000000;
    };

    layout = {
      gaps = 4;
      center-focused-column = "never";
      background-color = "transparent";
      always-center-single-column = true;
      empty-workspace-above-first = true;

      preset-column-widths = [
        {proportion = 1. / 3.;}
        {proportion = 1. / 2.;}
        {proportion = 2. / 3.;}
        {proportion = 1.;}
      ];
      default-column-width.proportion = 2. / 3.;

      focus-ring = {
        enable = true;
        width = 2;
        active.color = "#b4befe";
        inactive.color = "#585b70";
      };

      border.enable = false;
      shadow.enable = false;
    };

    hotkey-overlay.skip-at-startup = true;
    spawn-at-startup = [
      {
        sh = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri";
      }
    ];
    screenshot-path = "~/Pictures/Screenshots/screenshot-%Y%m%d-%H-%M-%S.png";

    window-rules = [
      {
        matches = [
          {
            app-id = "firefox$";
            title = "^Picture-in-Picture$";
          }
        ];
        open-floating = true;
      }
      {
        geometry-corner-radius = {
          bottom-left = 12.;
          bottom-right = 12.;
          top-left = 12.;
          top-right = 12.;
        };
        clip-to-geometry = true;
      }
    ];
    layer-rules = [
      {
        matches = [
          {namespace = "^swww-daemon$";}
        ];
        place-within-backdrop = true;
      }
    ];

    binds =
      {
        "Mod+Shift+Slash".action.show-hotkey-overlay = {};

        "Mod+Return".action.spawn = ["kitty"];
        "Mod+Space".action.spawn = ["walker"];
        "Mod+B".action.spawn = ["firefox"];
        "Mod+E".action.spawn = ["thunar"];
        "Mod+Alt+L".action.spawn = ["swaylock"];

        "XF86AudioRaiseVolume" = {
          action.spawn = [
            "wpctl"
            "set-volume"
            "@DEFAULT_AUDIO_SINK@"
            "0.01+"
          ];
          allow-when-locked = true;
        };
        "XF86AudioLowerVolume" = {
          action.spawn = [
            "wpctl"
            "set-volume"
            "@DEFAULT_AUDIO_SINK@"
            "0.01-"
          ];
          allow-when-locked = true;
        };
        "XF86AudioMute" = {
          action.spawn = [
            "wpctl"
            "set-mute"
            "@DEFAULT_AUDIO_SINK@"
            "toggle"
          ];
          allow-when-locked = true;
        };
        "XF86AudioMicMute" = {
          action.spawn = [
            "wpctl"
            "set-mute"
            "@DEFAULT_AUDIO_SOURCE@"
            "toggle"
          ];
          allow-when-locked = true;
        };
        "XF86AudioNext" = {
          action.spawn = [
            "playerctl"
            "next"
          ];
          allow-when-locked = true;
        };
        "XF86AudioPrev" = {
          action.spawn = [
            "playerctl"
            "previous"
          ];
          allow-when-locked = true;
        };
        "XF86AudioPlay" = {
          action.spawn = [
            "playerctl"
            "play-pause"
          ];
          allow-when-locked = true;
        };

        "Mod+O".action.toggle-overview = {};
        "Mod+Q" = {
          action.close-window = {};
          repeat = false;
        };

        "Mod+Left".action.focus-column-left = {};
        "Mod+Right".action.focus-column-right = {};
        "Mod+H".action.focus-column-left = {};
        "Mod+L".action.focus-column-right = {};

        "Mod+Ctrl+Left".action.move-column-left-or-to-monitor-left = {};
        "Mod+Ctrl+Right".action.move-column-right-or-to-monitor-right = {};
        "Mod+Ctrl+H".action.move-column-left-or-to-monitor-left = {};
        "Mod+Ctrl+L".action.move-column-right-or-to-monitor-right = {};

        "Mod+Down".action.focus-window-or-workspace-down = {};
        "Mod+Up".action.focus-window-or-workspace-up = {};
        "Mod+J".action.focus-window-or-workspace-down = {};
        "Mod+K".action.focus-window-or-workspace-up = {};

        "Mod+Ctrl+Down".action.move-window-down-or-to-workspace-down = {};
        "Mod+Ctrl+Up".action.move-window-down-or-to-workspace-down = {};
        "Mod+Ctrl+J".action.move-window-up-or-to-workspace-up = {};
        "Mod+Ctrl+K".action.move-window-up-or-to-workspace-up = {};

        "Mod+Shift+Left".action.focus-monitor-left = {};
        "Mod+Shift+Down".action.focus-monitor-down = {};
        "Mod+Shift+Up".action.focus-monitor-up = {};
        "Mod+Shift+Right".action.focus-monitor-right = {};
        "Mod+Shift+H".action.focus-monitor-left = {};
        "Mod+Shift+J".action.focus-monitor-down = {};
        "Mod+Shift+K".action.focus-monitor-up = {};
        "Mod+Shift+L".action.focus-monitor-right = {};

        "Mod+BracketLeft".action.consume-or-expel-window-left = {};
        "Mod+BracketRight".action.consume-or-expel-window-right = {};

        "Mod+R".action.switch-preset-column-width = {};
        "Mod+Shift+R".action.switch-preset-column-width-back = {};
        "Mod+M".action.maximize-column = {};
        "Mod+F".action.fullscreen-window = {};

        "Mod+C".action.center-column = {};
        "Mod+Ctrl+C".action.center-visible-columns = {};

        "Mod+Minus".action.set-column-width = "-10%";
        "Mod+Plus".action.set-column-width = "+10%";

        "Mod+V".action.toggle-window-floating = {};
        "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = {};

        "Mod+W".action.toggle-column-tabbed-display = {};

        "Print".action.screenshot = {};
        "Ctrl+Print".action.screenshot-screen = {};
        "Alt+Print".action.screenshot-window = {};

        "Mod+Escape" = {
          allow-inhibiting = false;
          action.toggle-keyboard-shortcuts-inhibit = {};
        };
        "Ctrl+Alt+Delete".action.quit = {};

        "Mod+Shift+P".action.power-off-monitors = {};
      }
      // (lib.listToAttrs (
        builtins.concatMap (i: [
          {
            name = "Mod+${toString i}";
            value = {
              action.focus-workspace = i;
            };
          }
          {
            name = "Mod+Shift+${toString i}";
            value = {
              action.move-window-to-workspace = i;
            };
          }
        ]) (lib.range 1 9)
      ));
  };

  home.packages = [
    pkgs.xwayland-satellite
  ];
}
