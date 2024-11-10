{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  users.users.agindin.home = "/Users/agindin";

  agindin.latex.enable = true;

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "23.11";
}
