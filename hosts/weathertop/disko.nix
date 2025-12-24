{ ... }:
{
  disko.devices = {
    disk = {
      nvme0n1 = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            swap = {
              priority = 2;
              size = "16G";
              name = "swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                resumeDevice = true;
              };
            };

            nvme0n1p2 = {
              priority = 3;
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main-pool";
              };
            };
          };
        };
      };
    };

    bcachefs_filesystems = {
      main-pool = {
        type = "bcachefs_filesystem";
        extraFormatArgs = [
          "--compression=lz4"
          "--background_compression=zstd"
          "--noatime"
          "--encoded_extent_max=256k"
          "--btree_node_size=512k"
        ];
        mountOptions = [ "verbose" ];
        subvolumes = {
          "subvolumes/root" = {
            mountpoint = "/";
          };
          "subvolumes/home" = {
            mountpoint = "/home";
          };
          "subvolumes/nix" = {
            mountpoint = "/nix";
          };
          "subvolumes/persist" = {
            mountpoint = "/persist";
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
}

