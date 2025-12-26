{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.services.caddy;
  inherit (lib) mkIf mkEnableOption mkOption types mkMerge;

  overlay = final: prev: {
    caddy-cloudflare = unstablePkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.2"
      ];
      hash = "sha256-ea8PC/+SlPRdEVVF/I3c1CBprlVp1nrumKM5cMwJJ3U=";
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
    proxyHosts = mkOption {
      description = "Hosts to proxy.";
      default = [];
      type = types.listOf (types.submodule {
        options = {
          domain = mkOption { type = types.str; };
          host = mkOption { type = types.str; default = "127.0.0.1"; };
          port = mkOption { type = types.port; };
          extraConfig = mkOption { type = types.str; default = ""; };
        };
      });
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
        in lib.strings.concatMapStringsSep "\n" (host: ''
          ${host.domain} {
            reverse_proxy ${host.host}:${toString host.port} ${if (host.extraConfig != "") then "{\n${host.extraConfig}\n}" else ""}
            ${tlsSetup}
          }
        '') cfg.proxyHosts;
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
