{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.unifiedremote.enable = lib.mkEnableOption "Unified Remote server";

  config = lib.mkIf config.my.hm.unifiedremote.enable {
    home.packages = [pkgs.urserver];

    systemd.user.services.urserver = {
      Unit = {
        Description = "Unified Remote Server";
        After = ["network.target"];
      };
      Service = {
        Type = "forking";
        ExecStart = "${pkgs.urserver}/bin/urserver --daemon --pidfile=urserver.pid";
        ExecStop = "kill -TERM $(cat urserver.pid)";
        PIDFile = "urserver.pid";
        Restart = "on-failure";
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
