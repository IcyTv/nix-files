{
  config,
  pkgs,
  ...
}: let
  niriLoginConfig = pkgs.writeText "niri-login.kdl" ''
    hotkey-overlay {
      skip-at-startup
    }

    output "HDMI-A-1" {
      off
    }
    output "DP-3" {
      off
    }
    output "DP-2" {
      mode "2560x1440@239.970"
      position x=0 y=0
      transform "normal"
    }
    spawn-at-startup "sh" "-c" "foot -f monospace:size=20 --fullscreen --title tuigreet -e tuigreet --cmd niri-session; ${pkgs.niri}/bin/niri msg action quit"

    window-rule {
      match app-id="foot"
      open-fullscreen true
      border { off; }
      draw-border-with-background false
    }

    cursor {
      hide-when-typing
      hide-after-inactive-ms 1
    }

    animations {
      off
    }

    layout {
        gaps 0
        default-column-width { proportion 1.0; }
        focus-ring { off; }
    }
  '';
in {
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.niri}/bin/niri --config ${niriLoginConfig}";
        user = "greeter";
      };
    };
  };

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font";
      };
    };
  };

  environment.systemPackages = [
    pkgs.tuigreet
  ];
}
