{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.pocket-id;
  inherit (lib) mkIf mkOption mkEnableOption types;

  containerLib = import ../lib/container.nix { inherit lib pkgs; };

  dataDir = "/var/lib/pocket-id";
in {
  options.agindin.services.pocket-id = {
    enable = mkEnableOption "pocket-id";
    host = mkOption {
      type = types.str;
      default = "auth.gindin.xyz";
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
    name = "pocket-id";
    subnet = "192.168.103.0/24";
    hostAddress = "192.168.103.10";
    localAddress = "192.168.103.11";
    stateVersion = cfg.stateVersion;

    bindMounts = {
      "${dataDir}" = {
        hostPath = "${dataDir}";
        isReadOnly = false;
      };
    };

    openPorts = [ 80 ];

    extraConfig = {
      services.pocket-id = {
        enable = true;
        dataDir = "${dataDir}";
        settings = {
          APP_URL = "https://${cfg.host}";
          PORT = 80;
          TRUST_PROXY = true;
        };
      };
    };
  });
}

