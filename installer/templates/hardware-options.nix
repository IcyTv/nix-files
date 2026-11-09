{lib, ...}: let
  m = builtins.fromJSON (builtins.readFile ./install.json);
in {
  # Explicit wizard choices override nixos-generate-config's mkDefault detection.
  hardware.cpu.amd.updateMicrocode = m.hardware.cpu == "amd";
  hardware.cpu.intel.updateMicrocode = m.hardware.cpu == "intel";
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.graphics.enable = lib.mkDefault true;
  services.xserver.videoDrivers = lib.mkIf (m.hardware.gpu == "nvidia") ["nvidia"];
  hardware.nvidia.open = lib.mkIf (m.hardware.gpu == "nvidia") (lib.mkDefault true);
  virtualisation.virtualbox.guest.enable = lib.mkDefault (m.hardware.vm == "oracle");
  services.qemuGuest.enable = lib.mkDefault (m.hardware.vm == "kvm");
  services.upower.enable = lib.mkDefault m.hardware.laptop;
}
