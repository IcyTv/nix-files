{pkgs, ...}: let
  niri-taskbar = pkgs.rustPlatform.buildRustPackage rec {
    pname = "niri-taskbar";
    version = "0.3.0";

    src = pkgs.fetchFromGitHub {
      owner = "onlca";
      repo = "niri-taskbar";
      rev = "fix/update-niri-ipc";
      hash = "sha256-D8kLAaKT4NDdT3TTxNCX8NtvGyLTxFCmPcTjtwZD6nc=";
    };

    cargoHash = "sha256-lzzNAO/3P+9ZXuDSekGumvz7uawRAqVONgwXNonOpjg=";

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.gtk3];

    installPhase = ''
      mkdir -p $out/lib
      cp target/x86_64-unknown-linux-gnu/release/libniri_taskbar.so $out/lib/
    '';
  };
  player-script = pkgs.writeShellApplication {
    name = "playerctl-waybar-script";

    runtimeInputs = [pkgs.playerctl];

    text = ''
      PLAYERCTL_OUT=$(playerctl status || echo "No players found")
      TITLE=$(playerctl metadata --format='{{ title }}' || echo "None")
      if [[ "$PLAYERCTL_OUT" == "No players found" ]]; then
        echo -n ' No players active'
      elif [[ "$PLAYERCTL_OUT" == "Playing" ]]; then
        echo -n " $TITLE"
      elif [[ "$PLAYERCTL_OUT" == "Paused" ]]; then
        echo -n " $TITLE"
      elif [[ "$PLAYERCTL_OUT" == "Stopped" ]]; then
        echo -n " $TITLE"
      else
        echo -n " Error executing playerctl"
      fi
    '';
  };
in {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style =
      /*
      css
      */
      ''
        @define-color pink @base07;
        @define-color mauve @base0E;
        @define-color base @base00;
        @define-color text @base05;
        @define-color sky @base0D;

        * {
          font-size: 17px;
          min-height: 0;
          border: none;
          border-radius: 0;
        }

        window#waybar {
          background-color: transparent;
          transition-property: background-color;
          transition-duration: 0.5s;
        }

        window#waybar.hidden {
          opacity: 0.5;
        }

        .niri-taskbar {
          border-radius: 4px;
          margin: 2px;
          margin-left: 8px;
        }

        .niri-taskbar button {
          border-radius: 4px;
          padding: 2px;
        }

        .niri-taskbar button.active {
          background-color: @pink;
        }

        .niri-taskbar button:hover {
          background-color: @mauve;
        }

        #memory,
        #custom-power,
        #custom-music,
        #wireplumber,
        #network,
        #clock,
        #bluetooth,
        #tray {
          border-radius: 4px;
          margin: 6px 3px;
          padding: 6px 12px;
          background-color: @base;
          color: @text;
        }

        #custom-power {
          margin-right: 6px;
        }

        .niri-taskbar {
          margin-left: 5px;
          color: @sky;
        }

        #custom-music {
          background-color: @subtext1;
        }

        #memory {
          background-color: @peach;
        }

        #wireplumber {
          background-color: @yellow;
        }

        #bluetooth {
          background-color: @blue;
        }

        #network {
          padding-right: 17px;
          background-color: @teal;
        }

        #clock {
          background-color: @mauve;
        }

        #custom-power {
          background-color: @flamingo;
        }

        tooltip {
          border-radius: 8px;
          padding: 15px;
          background-color: @surface0;
        }

        tooltip label {
          padding: 5px;
          background-color: @surface0;
          color: @text;
        }
      '';

    settings.main = {
      layer = "top";
      position = "top";

      modules-left = [
        "cffi/niri-taskbar"
      ];

      modules-center = [
        "custom/music"
      ];

      modules-right = [
        "clock"
        "tray"
        "memory"
        "wireplumber"
        "bluetooth"
        "custom/power"
      ];

      "cffi/niri-taskbar" = {
        module_path = "${niri-taskbar}/lib/libniri_taskbar.so";
      };

      "custom/music" = {
        format = "{}";
        interval = 5;
        tooltip = false;
        on-click = "playerctl play-pause";
        max-length = 50;
        exec = "${player-script}/bin/playerctl-waybar-script";
      };

      "custom/power" = {
        format = "⏻";
        tooltip = false;
        on-click = "wlogout";
      };

      wireplumber = {
        format = "{icon} {volume}%";
        format-muted = "";
        format-icons = {
          default = ["" "" ""];
        };
        on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
      };
    };
  };

  programs.wlogout.enable = true;

  home.packages = [
    pkgs.playerctl
  ];
}
