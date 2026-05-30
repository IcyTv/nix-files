{
  pkgs,
  config,
  lib,
  ...
}: let
  random-wallpaper = pkgs.writeShellApplication rec {
    name = "random-wallpaper";
    runtimeInputs = [pkgs.awww pkgs.uutils-coreutils-noprefix pkgs.fd];

    text = ''
      WALLPAPER_DIR="$HOME/.dotfiles/nix/wallpapers"

      if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Directory not found: $WALLPAPER_DIR" >&2
        exit 1
      fi

      wallpaper=$(fd . "$WALLPAPER_DIR" -d 1 -t f | shuf -n 1)

      if [ -n "$wallpaper" ]; then
        awww img "$wallpaper"
      else
        echo "No files found in $WALLPAPER_DIR" >&2
        exit 1
      fi
    '';
  };
in {
  options.my.hm.swww.enable = lib.mkEnableOption "SWWW wallpaper daemon and random wallpaper script";

  config = lib.mkIf config.my.hm.swww.enable {
    services.awww.enable = true;

    # home.file."Pictures/wallpapers" = {
    #   source = ./wallpapers;
    #   recursive = false;
    # };

    home.packages = [random-wallpaper];

    systemd.user.services.random-wallpaper = {
      Unit = {
        Description = "Change awww to random wallpaper";
        After = ["graphical-session.target" "awww.service"];
        Requires = ["awww.service"];
      };

      Service = {
        ExecStart = "${random-wallpaper}/bin/random-wallpaper";
        Type = "oneshot";
      };

      Install = {
        WantedBy = ["awww.service"];
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
  };
}
