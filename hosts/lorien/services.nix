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
      adsAllowedClients = [ "100.106.161.106" "fd7a:115c:a1e0::4e01:a16b" ];
    };

    caddy.enable = true;

    calibre = {
      enable = true;
      version = "v7.23.0-ls314";
    };

    freshrss.enable = true;

    immich = {
      enable = true;
      version = "v1.123.0";
    };

    memos.enable = true;

    tandoor = {
      enable = true;
      version = "1.5.24";
      postgresVersion = "15-alpine";
    };

    openwebui = {
      enable = true;
      tag = "git-4269df0";
    };
  };
}
