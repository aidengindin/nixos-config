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
  };
}
