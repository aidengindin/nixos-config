{ config, lib, pkgs, ... }:

let
  cfg = config.agindin.services.immich;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.immich = {
    enable = mkEnableOption "immich";
    version = mkOption {
      # https://github.com/immich-app/immich/releases
      type = types.str;
      default = "v1.133.0";
      description = "Immich version tag to pull.";
    };
    uploadLocation = mkOption {
      type = types.path;
      default = /srv/immich/upload;
      description = "Path on the host where uploaded media will be stored.";
    };
    dataLocation = mkOption {
      type = types.path;
      default = /var/lib/immich;
      description = "Path on the host where the model cache, database, etc. will be stored.";
    };
    subnet = mkOption {
      type = types.str;
      default = "172.100.10.0/24";
      description = "Subnet for the Immich Docker network to use";
    };
    ip = mkOption {
      type = types.str;
      default = "172.100.10.10";
      description = "IP address for the Immich container";
    };
    host = mkOption {
      type = types.str;
      default = "immich.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
        immich-db-password.file = ../secrets/immich-db-password.age;
    };

    systemd.services = {
      create-immich-network = {
        description = "Create Docker network for Immich containers";
        serviceConfig.type = "oneshot";
        wantedBy = [ "multi-user.target" ];
        after = [ "docker.service" ];
        script = ''
          if ! ${pkgs.docker}/bin/docker network inspect immich-network &>/dev/null; then
            echo "immich-network does not exist. Creating..."
            if ${pkgs.docker}/bin/docker network create --subnet=${cfg.subnet} immich-network; then
              echo "Network created with subnet ${cfg.subnet}"
            else
              echo "Failed to create network."
              exit 1
            fi
          else
            echo "immich-network already exists. Skipping creation."
          fi
        '';
      };

      docker-immich-server.after = [ "create-immich-network.service" ];
      docker-tandoor-machine-learning.after = [ "create-immich-network.service" ];
      docker-immich-redis.after = [ "create-immich-network.service" ];
      docker-immich-database.after = [ "create-immich-network.service" ];
    };

    virtualisation.oci-containers.containers = {
      immich-server = {
        image = "ghcr.io/immich-app/immich-server:${cfg.version}";
        volumes = [
          "${toString cfg.uploadLocation}:/usr/src/app/upload"
          "${config.age.secrets.immich-db-password.path}:/etc/password.txt"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environment = {
          IMMICH_VERSION = cfg.version;
          # UPLOAD_LOCATION = "./library";
          DB_HOSTNAME = "immich-database";
          DB_PORT = "5432";
          DB_USERNAME = "immich";
          DB_PASSWORD_FILE = "/etc/password.txt";
          DB_DATABASE_NAME = "immich";
          REDIS_HOSTNAME = "immich-redis";
          REDIS_PORT = "6379";
          IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
        };
        ports = [ "2283:3001" ];
        dependsOn = [ "immich-redis" "immich-database" ];
        extraOptions = [
            "--rm=false"
            "--restart=always"
            "--network=immich-network"
            "--ip=${cfg.ip}"
        ];
      };

      "immich-machine-learning" = {
        image = "ghcr.io/immich-app/immich-machine-learning:${cfg.version}";
        volumes = [
          "${toString cfg.dataLocation}/model-cache:/cache"
        ];
        environment = {
          IMMICH_VERSION = cfg.version;
        };
        extraOptions = [
            "--rm=false"
            "--restart=always"
            "--network=immich-network"
        ];
      };

      "immich-redis" = {
        image = "docker.io/redis:6.2-alpine@sha256:2d1463258f2764328496376f5d965f20c6a67f66ea2b06dc42af351f75248792";
        extraOptions = [
            "--rm=false"
            "--restart=always"
            "--network=immich-network"
        ];
      };

      "immich-database" = {
        image = "docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0";
        environment = {
          POSTGRES_PASSWORD_FILE = "/etc/password.txt";
          POSTGRES_USER = "immich";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        volumes = [
          "${toString cfg.dataLocation}/db:/var/lib/postgresql/data"
          "${config.age.secrets.immich-db-password.path}:/etc/password.txt"
        ];
        # command = [
        cmd = [
          # "postgres"
          "-c" "shared_preload_libraries=vectors.so"
          "-c" "search_path=\"$$user\", public, vectors"
          "-c" "logging_collector=on"
          "-c" "max_wal_size=2GB"
          "-c" "shared_buffers=512MB"
          "-c" "wal_compression=on"
        ];
        extraOptions = [
            "--rm=false"
            "--restart=always"
            "--network=immich-network"
        ];
      };
    };
  };
}
