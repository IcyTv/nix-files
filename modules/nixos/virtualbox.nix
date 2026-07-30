{
  lib,
  config,
  ...
}: {
  options.my.nixos.virtualbox.enable = lib.mkEnableOption "Enable VirtualBox support";

  config = lib.mkIf config.my.nixos.tools.enable {
    virtualisation.virtualbox.host = {
      enable = true;
      enableExtensionPack = true;
    };
    users.extraGroups.vboxusers.members = ["michael"];
  };
}
