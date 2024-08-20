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
      # based on https://noah.masu.rs/posts/caddy-cloudflare-dns/
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

            vendorHash = "sha256-0Lw291cGHj4qXkfgp9wqNC6ZOHNRbKrkWfv3lCzwMv8=";

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
              mainProgram = "caddy";
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
      owner = "root";
      group = "keys";
      mode = "0440";
    };

    services.caddy = {
      enable = true;
      package = pkgs.caddy-cloudflare;
      email = "aiden+letsencrypt@aidengindin.com";
      globalConfig = ''
        acme_dns cloudflare {env.CLOUDFLARE_API_KEY}
        acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
      '';
      extraConfig = let
        tlsSetup = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_KEY}
          }
        '';
      in ''
        ${mkStrIf enableFreshrss ''
        freshrss.gindin.xyz {
          reverse_proxy 192.168.100.11:80
          ${tlsSetup}
        }
        ''}

        ${mkStrIf enableTandoor ''
        tandoor.gindin.xyz {
          reverse_proxy 127.0.0.1:8300
          ${tlsSetup}
        }
        ''}

        ${mkStrIf enableCalibre ''
        calibre.gindin.xyz {
          reverse_proxy 127.0.0.1:8200
          ${tlsSetup}
        }
        server.calibre.gindin.xyz {
          reverse_proxy 127.0.0.1:8201
          ${tlsSetup}
        }
        ''}
      '';
    };

    systemd = {
      services.caddy = {
        # environment = {
        #   CLOUDFLARE_API_KEY = builtins.readFile config.age.secrets.cloudflare-api-key.path;
        # };
        serviceConfig = {
          LoadCredential = [
            "cloudflare-api-key:${config.age.secrets.cloudflare-api-key.path}"
          ];
          EnvironmentFile = "/tmp/caddy.env";
          ExecStartPre = [
            "${pkgs.bash}/bin/bash -c '${pkgs.caddy-cloudflare}/bin/caddy list-modules -s >> /tmp/caddy_modules.log'"
            "${pkgs.bash}/bin/bash -c 'echo \"API Token file contents: $(cat $CREDENTIALS_DIRECTORY/cloudflare-api-key)\" >> /tmp/caddy_debug.log'"
            "${pkgs.bash}/bin/bash -c 'cp -rf $CREDENTIALS_DIRECTORY/cloudflare-api-key /tmp/caddy.env'"
          ];
          ExecStartPost = [
            "${pkgs.bash}/bin/bash -c 'echo \"caddy env file contents: $(cat /tmp/caddy.env)\" >> /tmp/caddy_debug.log'"
            "${pkgs.bash}/bin/bash -c 'env >> /tmp/caddy_env_dump.log'"
          ];
          AmbientCapabilities = "cap_net_bind_service";
          CapabilityBoundingSet = "cap_net_bind_service";
          NoNewPrivileges = true;
        };
      };
      sockets.caddy = {
        description = "Caddy web server sockets";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = [
            "0.0.0.0:80"
            "[::]:80"
            "0.0.0.0:443"
            "[::]:443"
          ];
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
