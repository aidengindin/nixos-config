{
  config,
  lib,
  pkgs,
  customPkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.caddy;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    mkMerge
    ;

  overlay = _final: _prev: {
    caddy-cloudflare = customPkgs.caddy-cloudflare;
  };
in
{
  options.agindin.services.caddy = {
    enable = mkEnableOption "Enable Caddy reverse proxy";
    cloudflareApiKeyFile = mkOption {
      type = types.path;
      default = ../secrets/lorien-caddy-cloudflare-api-key.age;
      description = "Path to age-encrypted file containing Cloudflare API token";
    };
    proxyHosts = mkOption {
      description = "Hosts to proxy.";
      default = [ ];
      type = types.listOf (
        types.submodule {
          options = {
            domain = mkOption { type = types.str; };
            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
            };
            port = mkOption { type = types.port; };
            extraConfig = mkOption {
              type = types.str;
              default = "";
              description = "Extra config inside the reverse_proxy block (e.g. header_up directives)";
            };
            siteConfig = mkOption {
              type = types.str;
              default = "";
              description = "Extra config at the site level, before reverse_proxy (e.g. rate_limit)";
            };
          };
        }
      );
    };
    extraSites = mkOption {
      description = ''
        Sites that aren't reverse proxies, so `proxyHosts` can't express them.
        Firefly III is the motivating case: it's PHP-FPM, so Caddy has to serve
        a document root out of the Nix store and speak FastCGI over a Unix
        socket rather than forwarding to a listening port.

        The TLS block is appended automatically, so these get the same
        ACME/Cloudflare handling as `proxyHosts`.
      '';
      default = [ ];
      type = types.listOf (
        types.submodule {
          options = {
            domain = mkOption { type = types.str; };
            config = mkOption {
              type = types.lines;
              description = "Caddyfile body for this site, minus the TLS block.";
            };
          };
        }
      );
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
        openssh.authorizedKeys.keys = [ ];
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
          metrics
        '';
        extraConfig =
          let
            tlsSetup = ''
              tls {
                dns cloudflare {env.CLOUDFLARE_API_KEY}
              }
            '';
          in
          lib.strings.concatMapStringsSep "\n" (host: ''
            ${host.domain} {
              ${host.siteConfig}
              reverse_proxy ${host.host}:${toString host.port} ${
                if (host.extraConfig != "") then "{\n${host.extraConfig}\n}" else ""
              }
              ${tlsSetup}
            }
          '') cfg.proxyHosts
          + lib.strings.concatMapStringsSep "\n" (site: ''
            ${site.domain} {
              ${site.config}
              ${tlsSetup}
            }
          '') cfg.extraSites
          + ''
            :${toString globalVars.ports.caddyMetrics} {
              metrics /metrics
            }
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

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        80
        443
        globalVars.ports.caddyMetrics
      ];

      # Open udp/443 for http/3
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [ 443 ];

      # Also allow on local interface for scraping
      networking.firewall.interfaces.lo.allowedTCPPorts = [ globalVars.ports.caddyMetrics ];
    })
  ];
}
