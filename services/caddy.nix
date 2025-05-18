{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.caddy;
  inherit (lib) mkIf mkEnableOption mkOption types optionalString;

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

  config = mkIf cfg.enable {

    # we need to compile a custom build of caddy to include cloudflare dns support
    # based on https://noah.masu.rs/posts/caddy-cloudflare-dns/
    nixpkgs.overlays = [
      (final: prev: {
        caddy-cloudflare = prev.caddy.override {
          vendorOverrides = {
            "github.com/caddy-dns/cloudflare" = {
              type = "lockfile";
              url = "https://github.com/caddy-dns/cloudflare/archive/refs/tags/v0.2.1.tar.gz";
              sha256 = "sha256-hH8fWCwldBxPOsvwXA7ZdgAnRr8F+yeue57q9tG8eHU=";
            };
          };

          postBuild = ''
            cd cmd/caddy
            go build -trimpath -mod=vendor -o $out/bin/caddy
          '';

          meta = oldAttrs.meta // {
            description = oldAttrs.meta.description + " (with Cloudflare DNS plugin)";
          };
        };
      });
        # let
        #   plugins = [ "github.com/caddy-dns/cloudflare" ];
        #   goImports =
        #     prev.lib.flip prev.lib.concatMapStrings plugins
        #     (pkg: "   _ \"${pkg}\"\n");
        #   goGets = prev.lib.flip prev.lib.concatMapStrings plugins
        #     (pkg: "go get ${pkg}\n      ");
        #   main = ''
        #     package main
        #     import (
        #     	caddycmd "github.com/caddyserver/caddy/v2/cmd"
        #     	_ "github.com/caddyserver/caddy/v2/modules/standard"
        #     ${goImports}
        #     )
        #     func main() {
        #     	caddycmd.Main()
        #     }
        #   '';

        # in {
        #   caddy-cloudflare = prev.buildGoModule {
        #     pname = "caddy-cloudflare";
        #     version = prev.caddy.version;
        #     runVend = true;

        #     subPackages = [ "cmd/caddy" ];

        #     src = prev.caddy.src;

        #     vendorHash = "sha256-u5vqVsP3Vg/4hHWyWdSkkYoLMJoRTdVYVj2994lcAeQ=";

        #     overrideModAttrs = (_: {
        #       preBuild = ''
        #         echo '${main}' > cmd/caddy/main.go
        #         ${goGets}
        #       '';
        #       postInstall = "cp go.sum go.mod $out/ && ls $out/";
        #     });

        #     postPatch = ''
        #       echo '${main}' > cmd/caddy/main.go
        #       cat cmd/caddy/main.go
        #     '';

        #     postConfigure = ''
        #       cp vendor/go.sum ./
        #       cp vendor/go.mod ./
        #     '';

        #     meta = with prev.lib; {
        #       mainProgram = "caddy";
        #       homepage = "https://caddyserver.com";
        #       description =
        #         "Fast, cross-platform HTTP/2 web server with automatic HTTPS";
        #       license = licenses.asl20;
        #       maintainers = with maintainers; [ Br1ght0ne techknowlogick ];
        #     };
        #   };
        # }
    ];

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
          reverse_proxy 192.168.102.11:80
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
  };
}
