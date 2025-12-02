{pkgs, ...}: let
  random-wallpaper = pkgs.writeShellApplication rec {
    name = "random-wallpaper";
    runtimeInputs = [pkgs.swww pkgs.uutils-coreutils-noprefix pkgs.fd];

    text = ''
      WALLPAPER_DIR="$HOME/Pictures/wallpapers"

      if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Directory not found: $WALLPAPER_DIR" >&2
        exit 1
      fi

      wallpaper=$(fd . "$WALLPAPER_DIR" -d 1 -t f | shuf -n 1)

      if [ -n "$wallpaper" ]; then
        swww img "$wallpaper"
      else
        echo "No files found in $WALLPAPER_DIR" >&2
        exit 1
      fi
    '';
  };
in {
  services.swww.enable = true;

  home.file."Pictures/wallpapers" = {
    source = ./wallpapers;
    recursive = false;
  };

  home.packages = [random-wallpaper];

  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Change swww to random wallpaper";
      After = ["graphical-session.target" "swww.service"];
      Requires = ["swww.service"];
    };

    Service = {
      ExecStart = "${random-wallpaper}/bin/random-wallpaper";
      Type = "oneshot";
    };

    Install = {
      WantedBy = ["swww.service"];
    };
  };

  systemd.user.timers.random-wallpaper = {
    Unit = {
      Description = "Change wallpaper every 15 minutes";
    };

    Timer = {
      OnUnitActiveSec = "15m";
      OnBootSec = "15m";
      Unit = "random-wallpaper.service";
    };

    Install.WantedBy = ["timers.target"];
  };
}
