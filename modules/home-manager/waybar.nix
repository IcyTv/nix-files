{
  config,
  pkgs,
  ...
}: let
  niri-taskbar = pkgs.rustPlatform.buildRustPackage rec {
    pname = "niri-taskbar";
    version = "0.3.0";

    src = pkgs.fetchFromGitHub {
      owner = "LawnGnome";
      repo = "niri-taskbar";
      rev = "v0.3.0+niri.25.08";
      hash = "sha256-Gbzh4OTkvtP9F/bfDUyA14NH2DMDdr3i6oFoFwinEAg=";
    };

    cargoHash = "sha256-Ql9iqbbS3DY7o5/PR96c2t4VXKoS1kjZ9k3SfhNdbzE=";

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.gtk3];

    installPhase = ''
      mkdir -p $out/lib
      cp target/x86_64-unknown-linux-gnu/release/libniri_taskbar.so $out/lib/
    '';
  };
in {
  catppuccin.waybar.enable = true;
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 17px;
        min-height: 0;
        border: none;
        border-radius: 0;
      }

      window#waybar {
        background-color: @mantle;
        transition-property: background-color;
        transition-duration: 0.5s;
      }

      window#waybar.hidden {
        opacity: 0.5;
      }

      #memory.
      #custom-power,
      #wireplumber,
      #network,
      #clock,
      #tray {
        border-radius: 4px;
        margin: 6px 3px;
        padding: 6px 12px;
        background-color: @base;
        color: @mantle;
      }

      #custom-power {
        margin-right: 6px;
      }

      .niri-taskbar {
        margin-left: 5px;
        color: @sky;
      }

      #memory {
        color: @peach;
      }

      #wireplumber {
        background-color: @yellow;
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
        "bluetooth"
      ];

      "cffi/niri-taskbar" = {
        module_path = "${niri-taskbar}/lib/libniri_taskbar.so";
      };
    };
  };
}
