{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.watchyourlan;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  imports = [ ./arion.nix ];
  
  options.agindin.services.watchyourlan = {
    enable = mkEnableOption "watchyourlan";
    interface = mkOption types.str;
  };

  config = mkIf cfg.enable {
    virtualisation.arion.projects.watchyourlan.services = {
      node-bootstrap.service = {
        image = "aceberg/node-bootstrap";
        restart = "unless-stopped";
        ports = [ "8850:8850" ];
      };
      watchyourlan.service = {
        image = "aceberg/watchyourlan";
        network_mode = "host";
        restart = "unless-stopped";
        command = "-n http://100.99.184.63:8850"; # TODO: fix this
        depends_on = [ "node-bootstrap" ];
        volumes = [ "~/docker-volumes/watchyourlan:/data" ];
        environment = {
          TZ = "America/New_York";
          IFACE = "enp1s0";  # TODO: parameterize this
          THEME = "darkly";
        };
      };
    };
  };
}
