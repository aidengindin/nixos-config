{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.calibre;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.calibre = {
    enable = mkEnableOption "calibre";
    version = mkOption {
      # https://hub.docker.com/r/linuxserver/calibre
      type = types.str;
      default = "8.5.0";
      description = "Calibre version tag to pull";
    };
    host = mkOption {
      type = types.str;
      default = "calibre.gindin.xyz";
    };
    serverHost = mkOption {
      type = types.str;
      default = "server.calibre.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.calibre = {
      image = "lscr.io/linuxserver/calibre:${cfg.version}";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
        TITLE = "Calibre";
      };
      volumes = [
        "/docker-volumes/calibre:/config"
      ];
      ports = [
        "8200:8080"
        "8201:8081"
      ];
      extraOptions = [
        "--dns=1.1.1.1"
        "--restart=unless-stopped"
        "--rm=false"
      ];
    };
  };
}
