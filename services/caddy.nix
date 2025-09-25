{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.services.caddy;
  inherit (lib) mkIf mkEnableOption mkOption types mkMerge;

  # helper function to conditionally insert strings
  mkStrIf = cond: str: if cond then str else "";

  # makes accessing these options less tedious
  myServices = config.agindin.services;
  freshrss = myServices.freshrss;
  immich = myServices.immich;
  miniflux = myServices.miniflux;
  tandoor = myServices.tandoor;
  calibre = myServices.calibre;
  memos = myServices.memos;
  openwebui = myServices.openwebui;
  searxng = myServices.searxng;
  pocket-id = myServices.pocket-id;
  audiobookshelf = myServices.audiobookshelf;

  overlay = final: prev: {
    caddy-cloudflare = unstablePkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.1"
      ];
      hash = "sha256-j+xUy8OAjEo+bdMOkQ1kVqDnEkzKGTBIbMDVL7YDwDY=";
    };
  };
in
{
  options.agindin.services.caddy = {
    enable = mkEnableOption "Enable Caddy reverse proxy";
    cloudflareApiKeyFile = mkOption {
      type = types.path;
      default =  ../secrets/lorien-caddy-cloudflare-api-key.age;
      description = "Path to age-encrypted file containing Cloudflare API token";
    };
  };


  config = mkMerge [
    { nixpkgs.overlays = [ overlay ]; }
    (mkIf cfg.enable {
  
      users.users.caddy = {
        isSystemUser = true;
        group = "caddy";
        description = "Caddy reverse proxy user";
        home = "/var/lib/caddy";
        createHome = true;
        openssh.authorizedKeys.keys = [];
      };
  
      age.secrets.cloudflare-api-key = {
        file = cfg.cloudflareApiKeyFile;
        owner = "caddy";
        group = "caddy";
        mode = "0440";
      };
  
      services.caddy = {
        enable = true;
        package = pkgs.caddy-cloudflare;
        email = "aiden+letsencrypt@aidengindin.com";
        globalConfig = ''
          acme_dns cloudflare {env.CLOUDFLARE_API_KEY}
        '';
        extraConfig = let
          tlsSetup = ''
            tls {
              dns cloudflare {env.CLOUDFLARE_API_KEY}
            }
          '';
        in ''
          ${mkStrIf freshrss.enable ''
          ${freshrss.host} {
            reverse_proxy 192.168.100.11:80
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf miniflux.enable ''
          ${miniflux.host} {
            reverse_proxy 192.168.102.11:8080
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf immich.enable ''
          ${immich.host} {
            reverse_proxy ${immich.ip}:2283
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf tandoor.enable ''
          ${tandoor.host} {
            reverse_proxy ${tandoor.ip}:8080
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf calibre.enable ''
          ${calibre.host} {
            reverse_proxy 127.0.0.1:8200
            ${tlsSetup}
          }
          ${calibre.serverHost} {
            reverse_proxy 127.0.0.1:8201
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf memos.enable ''
          ${memos.host} {
            reverse_proxy 127.0.0.1:5230
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf openwebui.enable ''
          ${openwebui.host} {
            reverse_proxy ${openwebui.ip}:8080
            ${tlsSetup}
          }
          ''}
  
          ${mkStrIf searxng.enable ''
          ${searxng.host} {
            reverse_proxy 127.0.0.1:8888
            ${tlsSetup}
          }
          ''}

          ${mkStrIf pocket-id.enable ''
          ${pocket-id.host} {
            reverse_proxy 192.168.103.11:1411 {
              header_up Host {host}
              header_up X-Real-IP {remote_host}
              header_up X-Forwarded-For {remote_host}
              header_up X-Forwarded-Proto {scheme}
              header_up X-Forwarded-Host {host}
            }
            ${tlsSetup}
          }
          ''}

          ${mkStrIf audiobookshelf.enable ''
          ${audiobookshelf.host} {
            reverse_proxy 192.168.104.11:8000
            ${tlsSetup}
          }
          ''}
        '';
      };
  
      systemd = {
        services.caddy = {
          serviceConfig = {
            EnvironmentFile = "${config.age.secrets.cloudflare-api-key.path}";
            AmbientCapabilities = "cap_net_bind_service";
            CapabilityBoundingSet = "cap_net_bind_service";
            NoNewPrivileges = true;
          };
        };
      };
  
      networking.firewall.allowedTCPPorts = [ 80 443 ];
    })
  ];
}
