{ ... }:
{
  disko.devices = {
    disk = {
      # Secondary disks first (alphabetically) so they're partitioned before the primaries format the RAID

      # HDD 2 - Media Pool member (must be partitioned before hdd1 formats)
      aaa-hdd2 = {
        device = "/dev/disk/by-id/ata-WDC_WD40EFPX-68C6CN0_WD-WX52D95L9YPX";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            hdd-pool-member = {
              size = "100%";
              label = "hdd-pool-member";
              # No content - this partition is formatted as part of hdd1's btrfs raid1
            };
          };
        };
      };

      # NVMe 2 - Swap + SSD Pool member (must be partitioned before nvme1 formats)
      aab-nvme2 = {
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZVKW512HMJP-000L7_S35BNX0K705819";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            swap = {
              priority = 1;
              size = "8G";
              name = "swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                resumeDevice = false;
              };
            };

            ssd-pool-member = {
              priority = 2;
              size = "100%";
              label = "ssd-pool-member";
              # No content - this partition is formatted as part of nvme1's btrfs raid1
            };
          };
        };
      };

      # HDD 1 - Media Pool (primary)
      hdd1 = {
        device = "/dev/disk/by-id/ata-WDC_WD40EFPX-68C6CN0_WD-WX52D95L97SP";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            hdd-pool = {
              size = "100%";
              label = "hdd-pool";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-d"
                  "raid1"
                  "-m"
                  "raid1"
                  "/dev/disk/by-partlabel/hdd-pool-member"
                ];
                subvolumes = {
                  "/media" = {
                    mountpoint = "/media";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
              };
            };
          };
        };
      };

      # NVMe 1 - Boot + Swap + SSD Pool (primary)
      nvme1 = {
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZVKW512HMJP-000L7_S35BNX0K419760";
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
              size = "8G";
              name = "swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                resumeDevice = true;
              };
            };

            ssd-pool = {
              priority = 3;
              size = "100%";
              label = "ssd-pool";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-d"
                  "raid1"
                  "-m"
                  "raid1"
                  "/dev/disk/by-partlabel/ssd-pool-member"
                ];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;
}
