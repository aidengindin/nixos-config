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

    # https://hub.docker.com/r/linuxserver/calibre
    calibre = {
      enable = true;
      version = "v7.26.0";
    };

    freshrss.enable = true;

    # https://github.com/immich-app/immich/releases
    immich = {
      enable = true;
      version = "v1.126.1";
    };

    # https://hub.docker.com/r/vabene1111/recipes/tags
    tandoor = {
      enable = true;
      version = "1.5.31";
      postgresVersion = "15-alpine";
    };

    # https://github.com/open-webui/open-webui/releases
    openwebui = {
      enable = true;
      tag = "git-6fedd72";
    };
  };
}
