{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services = {
    ryot = {
      enable = true;
      mountPath = "/docker-volumes/ryot/db";
    };
    rustic = {
      enable = true;
    };
    wallabag = {
      enable = true;
      mountPath = "/docker-volumes/wallabag";
    };
    blocky = {
      enable = true;
      adsAllowedClients = [ "100.119.136.129" ];
    };
  };
}
