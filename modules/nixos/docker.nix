{
  lib,
  config,
  ...
}: {
  options.my.nixos.docker.enable = lib.mkEnableOption "Docker and related services";

  config = lib.mkIf config.my.nixos.docker.enable {
    virtualisation.docker = {
      enable = true;
      # TODO: Make this optional, based on if the disk is actually btrfs...
      storageDriver = "btrfs";
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };
}
