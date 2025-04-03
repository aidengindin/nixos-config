{ config, pkgs, ... }:

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
      owner = "root";
      group = "keys";
      mode = "0440";
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
  };

  agindin.services = {
    restic = {
      enable = true;
      paths = [
        "/docker-volumes/calibre"
        "/docker-volumes/tandoor"
        "/var/lib/freshrss"
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
      adsAllowedClients = [ "100.106.161.106" "fd7a:115c:a1e0::4e01:a16b" ];
    };

    caddy.enable = true;

    calibre.enable = true;
    freshrss.enable = true;
    immich.enable = true;
    openwebui.enable = true;
    searxng.enable = true;
    tandoor.enable = true;

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
  };
}
