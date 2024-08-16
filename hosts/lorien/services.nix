{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services = {
    restic = {
      enable = true;
      paths = [
        "/docker-volumes/"
      ];
      localBackup = {
        enable = true;
        repositoryFile = /mnt/usbhdd/restic;
      };
      passwordPath = ../../secrets/restic-password.age;
    };

    blocky = {
      enable = true;
      adsAllowedClients = [ "100.119.136.129" ];
    };

    calibre = {
      enable = true;
      version = "v7.16.0-ls296";
    };

    tandoor = {
      enable = true;
      version = "1.5.18";
      postgresVersion = "15-alpine";
    };
  };
}
