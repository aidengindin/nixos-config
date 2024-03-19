{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services = {
    restic = {
      enable = true;
      paths = [
        "/docker-volumes/"
      ];
      passwordPath = ../../secrets/restic-password.age;
    };
    blocky = {
      enable = true;
      adsAllowedClients = [ "100.119.136.129" ];
    };
  };
}
