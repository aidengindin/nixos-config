{ ... }:
{
  disko.devices = {
    disk = {
      nvme1 = {
        device = "/dev/changeme";
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

            cache_partition = {
              priority = 3;
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main-pool";
                extraFormatArgs = [ "--label=ssd.nvme1" "--group=ssd" ];
              };
            };
          };
        };
      };

      nvme2 =  {
        device = "/dev/changeme";
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

            cache_partition = {
              priority = 2;
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main-pool";
                extraFormatArgs = [ "--label=ssd.nvme2" "--group=ssd" ];
              };
            };
          };
        };
      };

      hdd1 = {
        device = "/dev/changeme";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main-pool";
                extraFormatArgs = [ "--label=hdd.disk1" "--group=hdd" ];
              };
            };
          };
        };
      };

      hdd2 = {
        device = "/dev/changeme";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "main-pool";
                extraFormatArgs = [ "--label=hdd.disk2" "--group=hdd" ];
              };
            };
          };
        };
      };
    };

    # 4. The Bcachefs Pool Definition
    bcachefs_filesystems = {
      main-pool = {
        type = "bcachefs_filesystem";
        extraFormatArgs = [
          "--replicas=2"
          "--metadata_replicas=2"
          
          "--foreground_target=ssd"       # New writes go to SSD (fast tier)
          "--promote_target=ssd"          # Hot data read from HDD moves to SSD
          "--background_target=hdd"       # Cold data moves to HDDs
          
          "--compression=lz4"
          "--background_compression=zstd"
          
          "--encoded_extent_max=1M"       # Larger chunks = better compression for media
          "--btree_node_size=256k"        # Efficient metadata for large filesystems
          "--errors=ro"                   # Remount Read-Only on corruption
        ];
        mountOptions = [ "verbose" "noatime" ];
        subvolumes = {
          "subvolumes/root" = { mountpoint = "/"; };
          "subvolumes/home" = { mountpoint = "/home"; };
          "subvolumes/nix" = { mountpoint = "/nix"; };
          "subvolumes/persist" = { mountpoint = "/persist"; };
          "subvolumes/media" = { mountpoint = "/media"; };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;

  systemd.services.bcachefs-tune = {
    description = "Apply bcachefs performance tuning policies";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      bcachefs fs set-option /nix --compression=zstd
      bcachefs fs set-option /nix --background_compression=zstd

      bcachefs fs set-option /media --background_target=hdd
      bcachefs fs set-option /media --promote_target=hdd
      bcachefs fs set-option /media --data_replicas=2

      mkdir -p /var/lib/postgresql
      bcachefs fs set-option /var/lib/postgresql --background_target=ssd
      bcachefs fs set-option /var/lib/postgresql --promote_target=ssd

      # Immich: Keep the DB fast, but force thumbnails/videos to HDD
      mkdir -p /var/lib/immich/{library,thumbs}
      bcachefs fs set-option /var/lib/immich/library --background_target=hdd
      bcachefs fs set-option /var/lib/immich/library --promote_target=hdd     # Don't cache raw photos on SSD
      bcachefs fs set-option /var/lib/immich/upload  --background_target=hdd
      bcachefs fs set-option /var/lib/immich/upload  --promote_target=hdd     # Don't cache raw photos on SSD
      bcachefs fs set-option /var/lib/immich/thumbs  --background_target=ssd  # Keep thumbs fast!
    '';
  };
}
