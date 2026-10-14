{
  lib,
  config,
  ...
}: {
  options.my.nixos.virtualbox.enable = lib.mkEnableOption "Enable VirtualBox support";

  config = lib.mkIf config.my.nixos.tools.enable {
    virtualisation.virtualbox.host = {
      enable = true;
      # enableExtensionPack = true;
    };
    # Configure addresses only after VirtualBox has created the host-only interface.
    systemd.services."network-addresses-vboxnet0" = {
      requires = ["vboxnet0.service"];
      after = ["vboxnet0.service"];
    };
    users.extraGroups.vboxusers.members = ["michael"];
  };
}
