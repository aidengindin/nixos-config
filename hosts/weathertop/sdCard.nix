# stolen from https://github.com/appsforartists/device-config/blob/master/modules/sd-card.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.agindin.jovian.sdCard;
in
{
  options.sdCard = {
    btrfsOptions = lib.mkOption {
      # from https://gitlab.com/popsulfr/steamos-btrfs/
      default = [
        "noatime"
        "lazytime"
        "compress-force=zstd"
        "space_cache=v2"
        "autodefrag"
        "subvol=@"
        "ssd_spread"
      ];
      description = ''
        The mount options for a btrfs SD card.
      '';
    };
  };

  config = {
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]p[0-9]", ENV{ID_FS_USAGE}=="filesystem", RUN{program}+="${ pkgs.systemd }/bin/systemd-mount -o ${ lib.concatStringsSep "," cfg.btrfsOptions } --no-block --automount=yes --collect $devnode /run/media/mmcblk0p1"
    '';
  };
}

