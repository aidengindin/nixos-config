{ config, lib, pkgs, unstablePkgs, ... }:
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

  config = mkIf cfg.enable (lib.mkMerge [
    (containerLib.makeContainer {
      name = "pocket-id";
      subnet = "192.168.103.0/24";
      hostAddress = "192.168.103.10";
      localAddress = "192.168.103.11";
      stateVersion = cfg.stateVersion;
      nixpkgs = unstablePkgs.path;

      bindMounts = {
        "${dataDir}" = {
          hostPath = "${dataDir}";
          isReadOnly = false;
        };
      };

      openPorts = [ 1411 ];

      extraConfig = {
        services.pocket-id = {
          enable = true;
          dataDir = "${dataDir}";
          settings = {
            APP_URL = "https://${cfg.host}";
            PORT = 1411;
            TRUST_PROXY = true;
          };
        };
      };
    })
    {
      agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
        domain = cfg.host;
        host = "192.168.103.11";
        port = 1411;
        extraConfig = ''
          header_up Host {host}
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
        '';
      }];
    }
  ]);
}

