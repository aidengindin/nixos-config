{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  agindin = {
    firefox.enable = true;
  };
}
