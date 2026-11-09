{
  config,
  lib,
  pkgs,
  ...
}: {
  options.icy = {
    user.name = lib.mkOption {
      type = lib.types.str;
      default = "michael";
    };
    repository = lib.mkOption {
      type = lib.types.str;
      default = "/home/${config.icy.user.name}/.dotfiles/nix";
    };
    sharedRepository = lib.mkEnableOption "group-managed configuration checkout";
  };
  config = lib.mkIf config.icy.sharedRepository {
    users.groups.configurators = {};
    users.users.${config.icy.user.name}.extraGroups = ["configurators"];
    programs.git = {
      enable = true;
      lfs.enable = true;
      config.safe.directory = config.icy.repository;
    };
    environment.systemPackages = [pkgs.acl pkgs.git-crypt];
    services.pcscd.enable = true;
    hardware.gpgSmartcards.enable = true;
  };
}
