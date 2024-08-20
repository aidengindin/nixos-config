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
    nixpkgs.overlays = [
      (final: prev:
        let
          plugins = [ "github.com/caddy-dns/cloudflare" ];
          goImports =
            prev.lib.flip prev.lib.concatMapStrings plugins
            (pkg: "   _ \"${pkg}\"\n");
          goGets = prev.lib.flip prev.lib.concatMapStrings plugins
            (pkg: "go get ${pkg}\n      ");
          main = ''
            package main
            import (
            	caddycmd "github.com/caddyserver/caddy/v2/cmd"
            	_ "github.com/caddyserver/caddy/v2/modules/standard"
            ${goImports}
            )
            func main() {
            	caddycmd.Main()
            }
          '';

        in {
          caddy-cloudflare = prev.buildGo121Module {
            pname = "caddy-cloudflare";
            version = prev.caddy.version;
            runVend = true;

            subPackages = [ "cmd/caddy" ];

            src = prev.caddy.src;

            vendorSha256 = "sha256:mwIsWJYKuEZpOU38qZOG1LEh4QpK4EO0/8l4UGsroU8=";

            overrideModAttrs = (_: {
              preBuild = ''
                echo '${main}' > cmd/caddy/main.go
                ${goGets}
              '';
              postInstall = "cp go.sum go.mod $out/ && ls $out/";
            });

            postPatch = ''
              echo '${main}' > cmd/caddy/main.go
              cat cmd/caddy/main.go
            '';

            postConfigure = ''
              cp vendor/go.sum ./
              cp vendor/go.mod ./
            '';

            meta = with prev.lib; {
              homepage = "https://caddyserver.com";
              description =
                "Fast, cross-platform HTTP/2 web server with automatic HTTPS";
              license = licenses.asl20;
              maintainers = with maintainers; [ Br1ght0ne techknowlogick ];
            };
          };
        }
      )
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
      file = ../secrets/lorien-caddy-cloudflare-api-key.age;  # TODO: make this configurable
      owner = "caddy";
    };

    services.caddy = {
      enable = true;
      package = pkgs.caddy-cloudflare;
      email = "aiden+letsencrypt@aidengindin.com";
      globalConfig = ''
        acme_dns cloudflare {env.CLOUDFLARE_API_KEY}
      '';
      extraConfig = ''
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
        ''}
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
