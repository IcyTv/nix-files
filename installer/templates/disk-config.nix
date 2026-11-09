{lib, ...}: let
  m = builtins.fromJSON (builtins.readFile ./install.json);
  storage = builtins.fromJSON (builtins.readFile ./storage.json);
  btrfs = {
    type = "btrfs";
    extraArgs = ["-f"];
    subvolumes = {
      "/root" = {
        mountpoint = "/";
        mountOptions = ["compress=zstd:3" "noatime"];
      };
      "/home" = {
        mountpoint = "/home";
        mountOptions = ["compress=zstd:3" "noatime"];
      };
      "/nix" = {
        mountpoint = "/nix";
        mountOptions = ["compress=zstd:3" "noatime"];
      };
      "/swap" =
        {mountpoint = "/swap";}
        // lib.optionalAttrs (m.swapGiB > 0) {
          swap.swapfile.size = "${toString m.swapGiB}G";
        };
    };
  };
in {
  disko.devices.disk.main = {
    type = "disk";
    device = m.disk;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          uuid = storage.partitionUUIDs.efi;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        root = {
          uuid = storage.partitionUUIDs.root;
          size = "100%";
          content =
            if m.encrypted
            then {
              type = "luks";
              name = storage.mapper;
              extraFormatArgs = ["--type" "luks2"];
              # Runtime-only root-private file; never created in or copied to the store.
              passwordFile = "/run/icy-installer/luks-password";
              content = btrfs;
            }
            else btrfs;
        };
      };
    };
  };
  boot.initrd.luks.devices = lib.mkIf (m.encrypted && m.fido2) {
    ${storage.mapper}.crypttabExtraOpts = ["fido2-device=auto" "token-timeout=10s"];
  };
}
