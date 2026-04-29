{
  config,
  lib,
  ...
}: {
  options.my.nixos.disko = {
    enable = lib.mkEnableOption "Disko declarative partitioning (Btrfs)";

    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda";
      description = "The block device to partition (e.g. /dev/sda, /dev/nvme0n1)";
    };
  };

  config = lib.mkIf config.my.nixos.disko.enable {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = config.my.nixos.disko.device;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP";
                start = "1M";
                end = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = ["umask=0077"];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"]; # Override existing partition
                  # Subvolumes to match your current setup
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = ["compress=zstd:3" "ssd" "discard=async" "space_cache=v2" "relatime"];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = ["compress=zstd:3" "ssd" "discard=async" "space_cache=v2" "relatime"];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["compress=zstd:3" "ssd" "discard=async" "space_cache=v2" "noatime"];
                    };
                    "/swap" = {
                      mountpoint = "/swap";
                      mountOptions = ["compress=zstd:3" "ssd" "discard=async" "space_cache=v2" "noatime"];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
