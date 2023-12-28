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
          depends_on = [ "wallabag-db" "wallabag-redis" ];
        };

        wallabag-db.service = {
          image = "mariadb";
          container_name = "wallabag-db";
          environment = {
            MYSQL_ROOT_PASSWORD = "wallaroot";
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
