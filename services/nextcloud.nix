{ config, lib, pkgs, ...}:
let
  cfg = config.agindin.services.nextcloud;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.nextcloud = {
    enable = mkEnableOption "nextcloud";
    host = mkOption {
      type = types.str;
      default = "nextcloud.gindin.xyz";
    };
    interface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "Host network interface to use for NAT";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.nextcloud30;
      description = "Nextcloud package to use";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      "nextcloud-admin-pass.file" = ../secrets/nextcloud-admin-pass.age;
    };

    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-nextcloud" ];
      externalInterface = cfg.interface;
    };

    networking.firewall.extraCommands = ''
      iptables -t nat -A POSTROUTING -s 192.168.103.0/24 -o ${cfg.interface} -j MASQUERADE
      iptables -A FORWARD -i ${cfg.interface} -o ve-nextcloud -m state --state RELATED,ESTABLISHED -j ACCEPT
      iptables -A FORWARD -i ve-nextcloud -o ${cfg.interface} -j ACCEPT
    '';

    containers.nextcloud = {
      autoStart = true;
      ephemeral = true;

      privateNetwork = true;
      hostAddress = "192.168.103.10";
      localAddress = "192.168.103.11";

      bindMounts = {
        "/var/lib/nextcloud" = {
          hostPath = "/var/lib/nextcloud";
          isReadOnly = false;
        };
        "/run/secrets/nextcloud-admin-pass" = {
          hostPath = "${config.age.secrets.nextcloud-admin-pass.path}";
        };
      };

      config = { config, lib, pkgs, ... }: {
        services.timesyncd.enable = true;
        system.stateVersion = "24.05";

        nextcloud = {
          enable = true;
          hostName = cfg.host;
          package = cfg.package;

          # let nixos install & configure stuff automatically
          database.createLocally = true;
          configureRedis = true;

          maxUploadSize = "16G";
          https = true;  # TODO: should this actually be true behind a reverse proxy?
          enableBrokenCiphersforSSE = false;

          autoUpdateApps.enable = true;
          extraAppsEnable = true;
          extraApps = with config.services.nextcloud.package.packages.apps; {
            inherit calendar contacts deck mail notes onlyoffice tasks;
          };

          config = {
            overwriteProtocol = "https";
            dbType = "pgsql";
            adminuser = "aidengindin";
            adminpassFile = "/run/secrets/nextcloud-admin-pass";
          };
        };

        # TODO: enable onlyoffice
      };
    };
  };
}