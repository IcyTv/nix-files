{pkgs, ...}: {
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
}
