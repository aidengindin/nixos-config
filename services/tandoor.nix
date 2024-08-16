{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.tandoor;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.tandoor = {
    enable = mkEnableOption "tandoor";
    version = mkOption {
      type = types.str;
      example = "1.5.18";
      description = "Tandoor version tag to pull";
    };
    postgresVersion = mkOption {
      type = types.str;
      example = "15-alpine";
      description = "Postgres container version tag to pull";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      tandoor-secret-key.file = ../secrets/tandoor-secret-key.age;
      tandoor-postgres-password.file = ../secrets/tandoor-postgres-password.age;
    };

    virtualisation.oci-containers.containers = {
      tandoor = {
        image = "vabene1111/recipes:${cfg.version}";
        environment = {
          TZ = "America/New_York";
          REVERSE_PROXY_AUTH = "0";
          DB_ENGINE = "django.db.backends.postgresql";
          POSTGRES_HOST = "tandoor-postgres";
          POSTGRES_USER = "agindin";
          POSTGRES_DB = "tandoor";
          POSTGRES_PORT = "5432";
          PUID = "1000";
          PGID = "1000";
          SECRET_KEY_FILE = "/opt/recipes/secret-key.txt";
          POSTGRES_PASSWORD_FILE = "/opt/recipes/postgres-password.txt";
        };
        volumes = [
          "/docker-volumes/tandoor/staticfiles:/opt/recipes/staticfiles"
          "/docker-volumes/tandoor/mediafiles:/opt/recipes/mediafiles"
          "${config.age.secrets.tandoor-secret-key.path}:/opt/recipes/secret-key.txt"
          "${config.age.secrets.tandoor-postgres-password.path}:/opt/recipes/postgres-password.txt"
        ];
        dependsOn = [
          "tandoor-postgres"
        ];
        extraOptions = [
          "--restart=unless-stopped"
          "--rm=false"
          "--network=reverse-proxy"  # TODO: temporary until I switch everything to nix
        ];
      };

      tandoor-postgres = {
        image = "postgres:${cfg.postgresVersion}";
        environment = {
          TZ = "America/New_York";
          POSTGRES_ROOT_PASSWORD_FILE = "/etc/password.txt";
          POSTGRES_PASSWORD_FILE = "/etc/password.txt";
          POSTGRES_USER = "agindin";
          POSTGRES_DB = "tandoor";
          POSTGRES_PORT = "5432";
          PUID = "1000";
          PGID = "1000";
        };
        volumes = [
          "/docker-volumes/tandoor/postgres:/var/lib/postgresql/data"
          "${config.age.secrets.tandoor-postgres-password.path}:/etc/password.txt"
        ];
        extraOptions = [
          "--restart=unless-stopped"
          "--rm=false"
          "--network=reverse-proxy"  # TODO: temporary until I switch everything to nix
        ];
      };
    };
  };
}