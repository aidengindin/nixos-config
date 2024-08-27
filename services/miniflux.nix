{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.miniflux;
  inherit (lib) mkIf mkEnableOption mkOption types;
in {
  options.agindin.services.miniflux = {
    enable = mkEnableOption "Whether to enable Miniflux feed reader";
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
    host = mkOption {
      type = types.str;
      default = "miniflux.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      miniflux-credentials.file = ../secrets/miniflux-credentials.age;
    };

    network.nat = {
      enable = true;
      internalInterfaces = [ "ve-miniflux" ];
      externalInterface = cfg.interface;
    };

    networking.firewall.extraCommands = ''
      iptables -t nat -A POSTROUTING -s 192.168.102.0/24 -o ${cfg.interface} -j MASQUERADE
      iptables -A FORWARD -i ${cfg.interface} -o ve-miniflux -m state --state RELATED,ESTABLISHED -j ACCEPT
      iptables -A FORWARD -i ve-miniflux -o ${cfg.interface} -j ACCEPT
    '';

    containers.miniflux = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.102.10";
      localAddress = "192.168.102.11";

      bindMounts = {
        "/var/miniflux-credentials.txt" = {
          hostPath = "${config.age.secrets.miniflux-credentials.path}";
          isReadOnly = true;
        };
      };

      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        services.miniflux = {
          enable = true;
          createDatabaseLocally = true;
          adminCredentialsFile = /var/miniflux-credentials.txt;
          config = {
            LISTEN_ADDR = "localhost:8080";
            BASE_URL = "https://${cfg.host}";
          };
        };
      };
    };
  };
}
