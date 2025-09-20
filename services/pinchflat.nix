{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.pinchflat;
  inherit (lib) mkIf mkEnableOption mkOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };
in {
  options.agindin.services.pinchflat = {
    enable = mkEnableOption "pinchflat";
    host = mkOption {
      type = types.str;
      default = "videos.gindin.xyz";
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
    name = "pinchflat";
    subnet = "192.168.105.0/24";
    hostAddress = "192.168.105.10";
    localAddress = "192.168.105.11";
    stateVersion = cfg.stateVersion;

    bindMounts = {
      "/var/lib/pinchflat" = {
        hostPath = "/var/lib/pinchflat";
        isReadOnly = false;
      };
    };

    openPorts = [ 8000 ];

    extraConfig = {
      services.pinchflat = {
        enable = true;
        port = 8000;
        mediaDir = "/var/lib/pinchflat/media";
      };
    };
  });
}

