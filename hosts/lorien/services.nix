{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services.watchyourlan = {
    enable = true;
    interface = "enp1s0";
  };
}
