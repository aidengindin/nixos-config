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
    port = mkOption {
      type = types.int;
      default = 10200;
      description = "Port on which FreshRSS will be accessible on the host";
    };
  };

  config = mkIf cfg.enable {
    containers.freshrss = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.100.10";
      localAddress = "192.168.100.11";

      bindMounts = {
        "/var/lib/freshrss" = {
          hostPath = "/var/lib/freshrss";
          isReadOnly = false;
        };
      };

      # TODO: resource limits & healthcheck

      forwardPorts = [
        {
          hostPort = cfg.port;
          containerPort = 80;
          protocol = "tcp";
        }
      ];

      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        environment.systemPackages = with pkgs; [
          php
        ];

        services.freshrss = {
          enable = true;
          defaultUser = "admin";
          baseUrl = "http://nix.freshrss.box";
          authType = "none";
        };

        networking.firewall.allowedTCPPorts = [ 80 ];

        # auto-export subscriptions as opml weekly
        systemd = {
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
  
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
