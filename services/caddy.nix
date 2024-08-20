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
    users.users.caddy = {
      isSystemUser = true;
      group = "caddy";
      description = "Caddy reverse proxy user";
      home = "/var/lib/caddy";
      createHome = true;
      openssh.authorizedKeys.keys = [];
    };

    age.secrets.cloudflare-api-key = {  # TODO: create this secret
      file = ../secrets/lorien-caddy-cloudflare-api-key.age;  # TODO: make this configurable
      owner = "caddy";
    };

    services.caddy = {
      enable = true;
      email = "aiden+letsencrypt@aidengindin.com";
      extraConfig = ''
        {
          acme_dns cloudflare {env.CLOUDFLARE_API_KEY}
        }

        ${mkStrIf enableFreshrss ''
          freshrss.gindin.xyz {
            reverse_proxy 192.168.100.11:80
          }
        ''}

        ${mkStrIf enableTandoor ''
          tandoor.gindin.xyz {
            reverse_proxy 127.0.0.1:8300
          }
        ''}

        ${mkStrIf enableCalibre ''
          calibre.gindin.xyz {
            reverse_proxy 127.0.0.1:8200
          }
          server.calibre.gindin.xyz {
            reverse_proxy 127.0.0.1:8201
          }
        ''};
      '';
    };

    systemd.services.caddy.environment = {
      CLOUDFLARE_API_KEY = "\\$CREDENTIALS_DIRECTORY/cloudflare-api-key";
    };

    systemd.services.caddy.serviceConfig = {
      LoadCredential = [
        "cloudflare-api-key:${config.age.secrets.cloudflare-api-key.path}"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
