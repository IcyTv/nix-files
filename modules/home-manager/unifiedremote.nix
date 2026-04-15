{pkgs, ...}: {
  home.packages = [pkgs.urserver];

  systemd.user.services.urserver = {
    Unit = {
      Description = "Unified Remote Server";
      After = ["network.target"];
    };
    Service = {
      ExecStart = "${pkgs.urserver}/bin/urserver";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
