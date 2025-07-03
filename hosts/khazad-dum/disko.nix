{ config ? {}, pkgs ? import <nixpkgs> {}, ... }:
{
  disko.devices = {
    disk = {
      nvme0n1 = {
        device = "/dev/nvme0n1"; # TODO: Replace with by-id path when available
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
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                extraOpenArgs = [
                  "--allow-discards"
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                content = {
                  type = "btrfs";
                  extraArgs = [ "-L" "nixos" "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = [ "subvol=root" "compress=zstd" "noatime" "ssd" ];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = [ "subvol=home" "compress=zstd" "noatime" "ssd" ];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "subvol=nix" "compress=zstd" "noatime" "ssd" ];
                    };
                    "/persist" = {
                      mountpoint = "/persist";
                      mountOptions = [ "subvol=persist" "compress=zstd" "noatime" "ssd" ];
                    };
                    "/swap" = {
                      mountpoint = "/swap";
                      mountOptions = [ "subvol=swap" "noatime" "ssd" ];
                      swap.swapfile.size = "16G";
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
  
  fileSystems."/persist".neededForBoot = true;
}

