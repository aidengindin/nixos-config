{config, pkgs, ... }:

{
  imports = [ ../../services ];

  age.secrets = {
    restic-password = {
      file = ../../secrets/restic-password.age;
      owner = "root";
      group = "keys";
      mode = "0440";
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
      adsAllowedClients = [ "100.119.136.129" ];
    };

    caddy.enable = true;

    calibre = {
      enable = true;
      version = "v7.21.0-ls310";
    };

    freshrss.enable = true;

    immich = {
      enable = true;
      version = "v1.120.1";
    };

    memos.enable = true;

    tandoor = {
      enable = true;
      version = "1.5.20";
      postgresVersion = "15-alpine";
    };
  };
}
