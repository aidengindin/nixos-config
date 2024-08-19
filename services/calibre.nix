{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.calibre;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.calibre = {
    enable = mkEnableOption "calibre";
    version = mkOption {
      type = types.str;
      example = "v7.16.0-ls296";
      description = "Calibre version tag to pull";
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
      extraOptions = [
        "--dns=1.1.1.1"
        "--restart=unless-stopped"
        "--rm=false"
        "-p 0.0.0.0:8200:8080"
        "-p 0.0.0.0:8201:8081"
        # "--network=reverse-proxy"  # TODO: temporary until I switch everything to nix
      ];
    };
  };
}
