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
    virtualisation.arion.projects.ryot.settings.services = {
      postgres.service = {
        image = "postgres:16-alpine";
        container_name = "ryot-postgres";
        restart = "unless-stopped";
        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "postgres";
        };
        volumes = [{
          source = cfg.mountPath;
          target = "/var/lib/postgresql/data";
        }];
      };
      ryot.service = {
        image = "ghcr.io/ignisda/ryot:latest";
        container_name = "ryot";
        restart = "unless-stopped";
        environment = {
          TZ = "America/New_York";
          DATABASE_URL = "postgres://postgres:postgres@postgres:5432/postgres";
        };
      };
    };
  };
}
