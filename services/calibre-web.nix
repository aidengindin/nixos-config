{ config, lib, pkgs, globalVars, ... }:
let
  cfg = config.agindin.services.calibre-web;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.calibre-web = {
    enable = mkEnableOption "calibre-web";

    domain = mkOption {
      type = types.str;
      default = "books.gindin.xyz";
      description = "Domain name for the calibre-web instance";
    };

    calibreLibrary = mkOption {
      type = types.str;
      default = "/media/books";
      description = "Path to the Calibre library (containing metadata.db)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/calibre-web";
      description = "Directory for calibre-web configuration and database";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers = {
      calibre-web = {
        image = "ghcr.io/crocodilestick/calibre-web-automated:latest";
        volumes = [
          "${cfg.dataDir}:/config"
          "${cfg.calibreLibrary}:/calibre-library"
        ];
        environment = {
          PUID = "1000";
          PGID = "991";  # media group
          TZ = "America/New_York";
          OAUTHLIB_RELAX_TOKEN_SCOPE = "1";
        };
        ports = [ "${toString globalVars.ports.calibre-web}:8083" ];
        extraOptions = [
          "--rm=false"
          "--restart=always"
        ];
      };
    };

    # Create directories with appropriate permissions
    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0755 1000 1000 -"
      "d '${cfg.calibreLibrary}' 0775 1000 ${if config.users.groups ? media then "media" else "1000"} -"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      cfg.dataDir
    ];

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [{
      domain = cfg.domain;
      port = globalVars.ports.calibre-web;
    }];
  };
}
