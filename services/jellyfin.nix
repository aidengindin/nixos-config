{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.jellyfin;
  inherit (lib) mkIf mkEnableOption mkOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };
in {
  options.agindin.services.jellyfin = {
    enable = mkEnableOption "jellyfin";
    host = mkOption {
      type = types.str;
      default = "media.gindin.xyz";
    };
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
    stateVersion = mkOption {
      type = types.str;
      default = "25.05";
    };
  };

  config = mkIf cfg.enable (containerLib.makeContainer {
    name = "audiobookshelf";
    subnet = "192.168.106.0/24";
    hostAddress = "192.168.106.10";
    localAddress = "192.168.106.11";
    stateVersion = cfg.stateVersion;

    bindMounts = {
      "/var/lib/jellyfin" = {
        hostPath = "/var/lib/jellyfin";
        isReadOnly = false;
      };
    };

    openPorts = [ 8096 ];

    extraConfig = {
      services.jellyfin = {
        enable = true;
        dataDir = "/var/lib/jellyfin";
      };
    };
  });
}

