{ config, lib, unstablePkgs, globalVars, ... }:
let
  cfg = config.agindin.services.pocket-id;
  inherit (lib) mkIf mkOption mkEnableOption types;

  dataDir = "/var/lib/pocket-id";
in {
  options.agindin.services.pocket-id = {
    enable = mkEnableOption "pocket-id";
    domain = mkOption {
      type = types.str;
      default = "auth.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    services.pocket-id = {
      enable = true;
      package = unstablePkgs.pocket-id;
      dataDir = "${dataDir}";
      settings = {
        APP_URL = "https://${cfg.domain}";
        PORT = globalVars.ports.pocket-id;
        TRUST_PROXY = true;
      };
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
      domain = cfg.domain;
      port = globalVars.ports.pocket-id;
      extraConfig = ''
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
      '';
    }];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      dataDir
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      dataDir
    ];
  };
}

