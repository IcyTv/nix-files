{
  pkgs,
  lib,
  ...
}: {
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "server-local" = lib.hm.dag.entryBefore ["server"] {
        match = "host myserver exec \"${pkgs.netcat}/bin/nc -z -w 1 192.168.1.28 22\"";
        hostname = "192.168.1.28";
      };

      "server" = {
        hostname = "ssh.icytv.de";
        forwardAgent = true;
      };

      "seedbox" = {
        hostname = "icytv.cloud.seedboxes.cc";
        port = 3232;
        user = "icytv";
      };
    };
  };
}
