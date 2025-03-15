{ config, pkgs, ... }:

{
  imports = [ ../../services ];

  # create users needed for services
  users = {
    users = {
      aiden-withings-sync = {
        isSystemUser = true;
        home = "/var/lib/withings-sync/aiden";
        createHome = true;
      };
    };
    groups = {
      aiden-withings-sync = {};
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
          garminCredentials = {
            username = "aiden@thegindins.com";
            passwordFile = config.age.secrets.aiden-garmin-password.path;
          };
          user = "aiden-withings-sync";
          group = "aiden-withings-sync";
        };
      };
    };
  };
}
