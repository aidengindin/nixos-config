{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.ryot;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  
  options.agindin.services.ryot = {
    enable = mkEnableOption "ryot";
    mountPath = mkOption {
      type = types.str;
      example = "/var/docker/ryot";
      description = "Path to store persistent data";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.arion.projects.ryot.settings = {
      networks = {
        reverse-proxy = {
          external = true;
          name = "reverse-proxy";
        };
      };
      services = {
        ryot-postgres.service = {
          image = "postgres:16-alpine";
          container_name = "ryot-postgres";
          restart = "unless-stopped";
          environment = {
            POSTGRES_PASSWORD = "postgres";
            POSTGRES_USER = "postgres";
            POSTGRES_DB = "postgres";
          };
          volumes = [{
            type = "bind";
            source = cfg.mountPath;
            target = "/var/lib/postgresql/data";
          }];
          networks = [ "reverse-proxy" ];
        };
        ryot.service = {
          image = "ghcr.io/ignisda/ryot:latest";
          container_name = "ryot";
          restart = "unless-stopped";
          depends_on = [ "ryot-postgres" ];
          environment = {
            TZ = "America/New_York";
            DATABASE_URL = "postgres://postgres:postgres@ryot-postgres:5432/postgres";
            SERVER_INSECURE_COOKIE = "true";
          };
          networks = [ "reverse-proxy" ];
        };
      };
    };
  };
}
