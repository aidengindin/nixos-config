{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.wallabag;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.wallabag = {
    enable = mkEnableOption "wallabag";
    mountPath = mkOption {
      type = types.str;
      example = "/var/docker/wallabag";
      description = "Path to store persistent data";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.arion.projects.wallabag.settings = {
      networks = {
        reverse-proxy = {
          external = true;
          name = "reverse-proxy";
        };
      };
      services = {
        wallabag.service = {
          image = "wallabag/wallabag";
          container_name = "wallabag";
          restart = "unless-stopped";
          networks = [ "reverse-proxy" ];
          volumes = [{
            type = "bind";
            source = "${cfg.mountPath}/images";
            target = "/var/www/wallabag/web/assets/images";
          }];
          healthcheck = {
            test = [ "CMD" "wget" "--no-verbose" "--tries=1" "--spider" "http://localhost" ];
            interval = "1m";
            timeout = "3s";
          };
          environment = {
            MYSQL_ROOT_PASSWORD = "wallaroot";
            SYMFONY__ENV__DATABASE_DRIVER = "pdo_mysql";
            SYMFONY__ENV__DATABASE_HOST = "wallabag-db";
            SYMFONY__ENV__DATABASE_PORT = 3306;
            SYMFONY__ENV__DATABASE_NAME = "wallabag";
            SYMFONY__ENV__DATABASE_USER = "wallabag";
            SYMFONY__ENV__DATABASE_PASSWORD = "wallapass";
            SYMFONY__ENV__DATABASE_CHARSET = "utf8mb4";
            SYMFONY__ENV__DATABASE_TABLE_PREFIX = "wallabag_";
            SYMFONY__ENV__MAILER_DSN = "smtp://127.0.0.1";
            SYMFONY__ENV__FROM_EMAIL = "wallabag@wallabag.box";
            SYMFONY__ENV__DOMAIN_NAME = "http://wallabag.box";
            SYMFONY__ENV__SERVER_NAME = "Your wallabag instance:";
            SYMFONY__ENV__REDIS_HOST = "wallabag-redis";
          };
          depends_on = [ "wallabag-db" "wallabag-redis" ];
        };

        wallabag-db.service = {
          image = "mariadb";
          container_name = "wallabag-db";
          environment = {
            MYSQL_ROOT_PASSWORD = "wallaroot";
            MYSQL_DATABASE = "wallabag";
            MYSQL_USER = "wallabag";
            MYSQL_PASSWORD = "wallapass";
          };
          volumes = [{
            type = "bind";
            source = "${cfg.mountPath}/db";
            target = "/var/lib/mysql";
          }];
          restart = "unless-stopped";
          networks = [ "reverse-proxy" ];
          healthcheck = {
            test = [ "CMD" "mysqladmin" "ping" "-h" ];
            interval = "20s";
            timeout = "3s";
          };
        };

        wallabag-redis.service = {
          image = "redis:alpine";
          container_name = "wallabag-redis";
          restart = "unless-stopped";
          networks = [ "reverse-proxy" ];
          healthcheck = {
            test = [ "CMD" "redis-cli" "ping" ];
            interval = "20s";
            timeout = "3s";
          };
        };
      };
    };
  };
}
