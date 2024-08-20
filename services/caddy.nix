{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.caddy;
  inherit (lib) mkIf mkEnableOption;

  mkStrIf = cond: str: if cond then str else "";

  myServices = config.agindin.services;
  enableFreshrss = myServices.freshrss.enable;
  enableTandoor = myServices.tandoor.enable;
  enableCalibre = myServices.calibre.enable;
in
{
  options.agindin.services.caddy = {
    enable = mkEnableOption "Enable Caddy reverse proxy";
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = "aiden+letsencrypt@aidengindin.com";
      extraConfig = mkStrIf enableFreshrss ''
        freshrss.gindin.xyz {
          reverse_proxy 192.168.100.11:80
        }

      '' + mkStrIf enableTandoor ''
        tandoor.gindin.xyz {
          reverse_proxy 127.0.0.1:8300
        }

      '' + mkStrIf enableCalibre ''
        calibre.gindin.xyz {
          reverse_proxy 127.0.0.1:8200
        }
        server.calibre.gindin.xyz {
          reverse_proxy 127.0.0.1:8201
        }

      '';
    };

    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
