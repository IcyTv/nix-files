{
  lib,
  config,
  ...
}: {
  options.my.nixos.podman.enable = lib.mkEnableOption "Podman and related services";

  config = lib.mkIf config.my.nixos.podman.enable {
    assertions = [
      {
        assertion = !config.my.nixos.docker.enable;
        message = "Docker and Podman cannot be enabled at the same time.";
      }
    ];

    virtualisation.podman = {
      enable = true;
      networkSocket.enable = true;
      dockerCompat = true;
    };
  };
}
