{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.netalertx;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.netalertx = {
    enable = mkEnableOption "netalertx";
    domain = mkOption {
      type = types.str;
      default = "netalertx.gindin.xyz";
    };
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/netalertx";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.netalertx = {
      image = "jokobsk/netalertx:latest";
      volumes = [
        "${cfg.dataDir}:/data"
      ];
      environment = {
        TZ = config.time.timeZone;
        PORT = toString globalVars.ports.netalertx;
        GRAPHQL_PORT = toString globalVars.ports.netalertxMetrics;
        BACKEND_API_URL = "https://${cfg.domain}";
      };
      # NetAlertX requires host networking for ARP scanning to work effectively
      extraOptions = [
        "--network=host"
        "--read-only"
        "--tmpfs=/tmp"
        "--cap-drop=ALL"
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
        "--cap-add=NET_BIND_SERVICE"
        "--cap-add=CHOWN"
        "--cap-add=SETUID"
        "--cap-add=SETGID"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      cfg.dataDir
    ];

    # Manual Caddy configuration to handle split routing between frontend and backend
    services.caddy.extraConfig = mkIf config.agindin.services.caddy.enable ''
      ${cfg.domain} {
        # Backend API endpoints (no .php extension)
        @api {
          not path *.php
          path /graphql* /messaging/* /metrics* /sse/* /api/* /device/* /devices/* /sessions/* /events/*
        }
        handle @api {
          reverse_proxy 127.0.0.1:${toString globalVars.ports.netalertxMetrics}
        }

        # Frontend (PHP/Nginx) - everything else including .php files
        handle {
          reverse_proxy 127.0.0.1:${toString globalVars.ports.netalertx}
        }

        tls {
          dns cloudflare {env.CLOUDFLARE_API_KEY}
        }
      }
    '';

    # Ensure BACKEND_API_URL is set in app.conf
    systemd.services.docker-netalertx.preStart = lib.mkAfter ''
      CONF_FILE="${cfg.dataDir}/config/app.conf"
      if [ -f "$CONF_FILE" ]; then
        if grep -q "^BACKEND_API_URL=" "$CONF_FILE"; then
          sed -i "s|^BACKEND_API_URL=.*|BACKEND_API_URL='https://${cfg.domain}'|" "$CONF_FILE"
        else
          echo "BACKEND_API_URL='https://${cfg.domain}'" >> "$CONF_FILE"
        fi
      fi
    '';
  };
}
