{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.ssh.enable = lib.mkEnableOption "SSH client configuration";

  config = lib.mkIf config.my.hm.ssh.enable {
    services.ssh-agent.enable = true;

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      settings = {
        "server-local" = lib.hm.dag.entryBefore ["server"] {
          header = "Match host server exec \"${pkgs.netcat}/bin/nc -z -w 1 192.168.1.28 22\"";
          HostName = "192.168.1.28";
        };

        "server" = {
          HostName = "ssh.icytv.de";
          ForwardAgent = true;
        };

        "seedbox" = {
          HostName = "icytv.cloud.seedboxes.cc";
          Port = 3232;
          User = "icytv";
        };

        "box" = {
          HostName = "91.98.39.22";
          Port = 22;
          User = "michael";
          ForwardAgent = true;
        };
      };
    };
  };
}
