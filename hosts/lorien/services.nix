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
        "/docker-volumes/"
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
      version = "v7.16.0-ls296";
    };

    freshrss.enable = true;

    miniflux.enable = true;

    tandoor = {
      enable = true;
      version = "1.5.18";
      postgresVersion = "15-alpine";
    };
  };
}
