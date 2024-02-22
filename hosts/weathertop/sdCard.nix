# stolen from https://github.com/seanybaggins/nix-home/blob/main/flake.nix

{ config, lib, pkgs, ... }:

{
  config = {
    fileSystems."/run/media/deck/mmcblk0" = {
      device = "/dev/disk/by-uuid/2b2a161b-0fef-43a5-8023-9795fd31d5fb";
      # fsTtype = "btrfs";
      options = [ "compress=zstd" "noatime" ];
    };
  };
}

