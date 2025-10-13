{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.tandoor;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.tandoor = {
    enable = mkEnableOption "tandoor";
    version = mkOption {
      # https://hub.docker.com/r/vabene1111/recipes/tags
      type = types.str;
      default = "2.3.2";
      description = "Tandoor version tag to pull";
    };
    postgresVersion = mkOption {
      type = types.str;
      default = "15-alpine";
      description = "Postgres container version tag to pull";
    };
    subnet = mkOption {
      type = types.str;
      default = "172.100.0.0/24";
      description = "Subnet for the Tandoor Docker network to use";
    };
    ip = mkOption {
      type = types.str;
      default = "172.100.0.10";
      description = "IP address for the Tandoor container";
    };
    host = mkOption {
      type = types.str;
      default = "tandoor.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      tandoor-secret-key.file = ../secrets/tandoor-secret-key.age;
      tandoor-postgres-password.file = ../secrets/tandoor-postgres-password.age;
    };

    systemd.services = {
      create-tandoor-network = {
        description = "Create Docker network for Tandoor containers";
        serviceConfig.type = "oneshot";
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" ];
        script = ''
          if ! ${pkgs.docker}/bin/docker network inspect tandoor-network &>/dev/null; then
            echo "tandoor-network does not exist. Creating..."
            if ${pkgs.docker}/bin/docker network create --subnet=${cfg.subnet} tandoor-network; then
              echo "Network created with subnet ${cfg.subnet}"
            else
              echo "Failed to create network."
              exit 1
            fi
          else
            echo "tandoor-network already exists. Skipping creation."
          fi
        '';
      };

      docker-tandoor.after = [ "create-tandoor-network.service" ];
      docker-tandoor-postgres.after = [ "create-tandoor-network.service" ];
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
          TANDOOR_PORT = "8080";
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
        ports = [
          "8300:8080"
        ];
        extraOptions = [
          "--restart=unless-stopped"
          "--rm=false"
          "--network=tandoor-network"
          "--ip=${cfg.ip}"
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
          "--network=tandoor-network"
        ];
      };
    };
  };
}
