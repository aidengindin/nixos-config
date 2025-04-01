{ config, lib, pkgs, ... }:
{
  imports = [
    ../../common
  ];

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "23.11";
}

