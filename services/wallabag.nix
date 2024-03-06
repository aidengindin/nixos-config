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
    age.secrets.wallabag-db-password = {
      file = ../secrets/wallabag-db-password.age;
    };

    system.activationScripts."wallabag-env" = ''
      secret=$(cat "${config.age.secrets.wallabag-db-password.path}")
      envFile="${cfg.mountPath}/wallabag.env"
      echo '${builtins.readFile ./wallabag.env}' > $envFile
      ${pkgs.sd}/bin/sd '@secret@' $secret $envFile
    '';

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
          env_file = [ "${cfg.mountPath}/wallabag.env" ];
          depends_on = [ "wallabag-db" "wallabag-redis" ];
        };

        wallabag-db.service = {
          image = "mariadb";
          container_name = "wallabag-db";
          env_file = [ "${cfg.mountPath}/wallabag.env" ];
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
