{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.freshrss;
  inherit (lib) mkIf mkEnableOption mkOption types;
  
  # script to export subscriptions using freshrss cli
  exportOpmlScript = pkgs.writeScript "export-freshrss-opml.sh" ''
    #!/bin/sh
    /var/www/FreshRSS/cli/export-opml-for-user.php --user admin --filename /var/lib/freshrss/export.opml
  '';
in
{
  options.agindin.services.freshrss = {
    enable = mkEnableOption "freshrss";
    host = mkOption {
      type = types.str;
      default = "freshrss.gindin.xyz";
    };
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
    oidcProviderMetadataUrl = mkOption {
      type = types.str;
      default = "https://auth.gindin.xyz/.well-known/openid-configuration";
      description = "The OIDC provider metadata URL";
    };
  };

  config = mkIf cfg.enable {

    age.secrets = {
      client-id.file = ../secrets/authelia-freshrss-client-id.age;
      client-secret.file = ../secrets/authelia-freshrss-client-secret.age;
      client-crypto-key.file = ../secrets/freshrss-client-crypto-key.age;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/freshrss 0755 root root -"
    ];

    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-freshrss" ];
      externalInterface = cfg.interface;
    };

    networking.firewall.extraCommands = ''
      iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o ${cfg.interface} -j MASQUERADE
      iptables -A FORWARD -i ${cfg.interface} -o ve-freshrss -m state --state RELATED,ESTABLISHED -j ACCEPT
      iptables -A FORWARD -i ve-freshrss -o ${cfg.interface} -j ACCEPT
    '';

    containers.freshrss = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.100.10";
      localAddress = "192.168.100.11";

      bindMounts = let
        bindSecret = name: secretPath: {
          "/run/secrets/${name}.txt" = {
            hostPath = "${secretPath}";
            isReadOnly = true;
          };
        };
      in with config.age.secrets; {
        "/var/lib/freshrss" = {
          hostPath = "/var/lib/freshrss";
          isReadOnly = false;
        };
      }
      // bindSecret "client-id" client-id.path
      // bindSecret "client-secret" client-secret.path
      // bindSecret "client-crypto-key" client-crypto-key.path;

      # TODO: resource limits & healthcheck
      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        environment.systemPackages = with pkgs; [
          php
        ];

        services.freshrss = {
          enable = true;
          defaultUser = "aidengindin";
          baseUrl = "https://${cfg.host}";
          authType = "http_auth";
        };

        networking.firewall.allowedTCPPorts = [ 80 ];
        networking.nameservers = [ "1.1.1.1" ];

        systemd = {
          services.freshrss = {
            serviceConfig = {
              # LoadCredential = [
              #   "client-id:/run/secrets/client-id.txt"
              #   "client-secret:/run/secrets/client-secret.txt"
              #   "client-crypto-key:/run/secrets/client-crypto-secret.txt"
              # ];
              ExecStartPre = [
                "${pkgs.bash}/bin/bash -c 'echo \"OIDC_CLIENT_ID=$(cat /run/secrets/client-id.txt)\" > /run/freshrss-secrets'"
                "${pkgs.bash}/bin/bash -c 'echo \"OIDC_CLIENT_SECRET=$(cat /run/secrets/client-secret.txt)\" >> /run/freshrss-secrets'"
                "${pkgs.bash}/bin/bash -c 'echo \"OIDC_CLIENT_CRYPTO_KEY=$(cat /run/secrets/client-crypto-key.txt)\" >> /run/freshrss-secrets'"
                "${pkgs.bash}/bin/bash -c 'chmod 600 /run/freshrss-secrets'"
              ];
              EnvironmentFile = "/run/freshrss-secrets";
              Environment = [
                "OIDC_ENABLED=1"
                "OIDC_PROVIDER_METADATA_URL=${cfg.oidcProviderMetadataUrl}"
                # "OIDC_CLIENT_ID=${builtins.readFile /run/secrets/client-id.txt}"
                # "OIDC_CLIENT_SECRET=${builtins.readFile /run/secrets/client-secret.txt}"
                # "OIDC_CLIENT_CRYPTO_KEY=${builtins.readFile /run/secrets/client-crypto-key.txt}"
                "OIDC_REMOTE_USER_CLAIM=preferred_username"
                "OIDC_SCOPES=openid profile"
                "OIDC_X_FORWARDED_HEADERS=X-Forwarded-Host X-Forwarded-Port X-Forwarded-Proto"
              ];
            };
          };

          # auto-export subscriptions as opml weekly
          services.freshrss-opml-export = {
            description = "Export FreshRSS subscriptions to OPML for backup";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${exportOpmlScript}";
              User = "freshrss";
              ReadOnlyPaths = "/";
              ReadWritePaths = [ "/var/lib/freshrss" ];
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              NoNewPrivileges = true;
            };
            after = [ "freshrss.service" ];
            requires = [ "freshrss.service" ];
          };
          timers.freshrss-opml-export = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "weekly";
              Persistent = true;
            };
          };
        };
      };
    };
  };
}
