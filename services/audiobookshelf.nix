{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.audiobookshelf;
  inherit (lib) mkIf mkEnableOption mkOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };
in {
  options.agindin.services.audiobookshelf = {
    enable = mkEnableOption "audiobookshelf";
    host = mkOption {
      type = types.str;
      default = "audiobooks.gindin.xyz";
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
    subnet = "192.168.104.0/24";
    hostAddress = "192.168.104.10";
    localAddress = "192.168.104.11";
    stateVersion = cfg.stateVersion;

    bindMounts = {
      "/var/lib/audiobookshelf" = {
        hostPath = "/var/lib/audiobookshelf";
        isReadOnly = false;
      };
    };

    openPorts = [ 8000 ];

    extraConfig = {
      services.audiobookshelf = {
        enable = true;
        host = "0.0.0.0";
        port = 8000;
        dataDir = "audiobookshelf";  # /var/lib/audiobookshelf
      };
    };
  });
}

