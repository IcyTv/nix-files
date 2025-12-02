{
  config,
  pkgs,
  ...
}: let
  niriLoginConfig = pkgs.writeText "niri-login.kdl" ''
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
    spawn-at-startup "foot" "-f" "monospace:size=20" "--fullscreen" "-e" "tuigreet" "--cmd" "niri-session"

    window-rule {
      match app-id="foot"
      open-fullscreen true
      border { off; }
      draw-border-with-background false
    }

    cursor {
      hide-when-typing
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

  environment.systemPackages = [
    pkgs.tuigreet
    pkgs.foot
  ];
}
