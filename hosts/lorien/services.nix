{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services = {
    restic = {
      enable = true;
    };
    blocky = {
      enable = true;
      adsAllowedClients = [ "100.119.136.129" ];
    };
  };
}
