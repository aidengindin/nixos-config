{ config, ... }:

{
  imports = [ ../../services ];

  # create users needed for services
  users = {
    users = {
      aiden-withings-sync = {
        isSystemUser = true;
        group = "aiden-withings-sync";
        home = "/var/lib/withings-sync/aiden";
        createHome = true;
      };
      ally-withings-sync = {
        isSystemUser = true;
        group = "ally-withings-sync";
        home = "/var/lib/withings-sync/ally";
        createHome = true;
      };
    };
    groups = {
      aiden-withings-sync = {};
      ally-withings-sync = {};
    };
  };

  age.secrets = {
    restic-password = {
      file = ../../secrets/restic-password.age;
      owner = "restic";
      group = "restic";
      mode = "0400";
    };

    aiden-garmin-password = {
      file = ../../secrets/aiden-garmin-password.age;
      owner = "aiden-withings-sync";
      group = "aiden-withings-sync";
      mode = "0400";
    };

    ally-garmin-password = {
      file = ../../secrets/ally-garmin-password.age;
      owner = "ally-withings-sync";
      group = "ally-withings-sync";
      mode = "0400";
    };

    miniflux-client-id = {
      file = ../../secrets/miniflux-client-id.age;
      owner = "root";
      mode = "0400";
    };

    miniflux-client-secret = {
      file = ../../secrets/miniflux-client-secret.age;
      owner = "root";
      mode = "0400";
    };
  };

  agindin.services = {
    restic = {
      enable = true;
      paths = [
        "/docker-volumes/calibre"
        "/var/lib/immich"
        "/srv/immich"
      ];
      localBackup = {
        enable = true;
        repository = "/mnt/usbhdd/restic";
        repositoryMountUnitName = "mnt-usbhdd.mount";
      };
      passwordPath = config.age.secrets.restic-password.path;
    };

    blocky = {
      enable = true;
      adsAllowedClients = [
        "100.126.51.78"
        "fd7a:115c:a1e0::a701:3353"
      ];
    };

    caddy.enable = true;

    postgres.enable = true;

    audiobookshelf.enable = true;
    calibre.enable = true;
    immich.enable = true;
    openwebui.enable = true;
    tandoor.enable = true;
    pocket-id.enable = true;

    miniflux = {
      enable = true;
      oauth2ClientIdFile = config.age.secrets.miniflux-client-id.path;
      oauth2ClientSecretFile = config.age.secrets.miniflux-client-secret.path;
    };

    withings-sync = {
      enable = true;
      users = {
        aiden = {
          enable = true;
          garminCredentials = {
            username = "aiden@aidengindin.com";
            passwordFile = config.age.secrets.aiden-garmin-password.path;
          };
          user = "aiden-withings-sync";
          group = "aiden-withings-sync";
        };
        ally = {
          enable = true;
          garminCredentials = {
            username = "allybgindin@gmail.com";
            passwordFile = config.age.secrets.ally-garmin-password.path;
          };
          user = "ally-withings-sync";
          group = "ally-withings-sync";
        };
      };
    };

    prometheusExporter.enable = true;
    promtail.enable = true;

    grafana = {
      enable = true;
      prometheusScrapeTargets = [
        {
          name = "lorien";
          host = "127.0.0.1";
          port = config.agindin.services.prometheusExporter.port;
        }
      ];
    };
  };
}
