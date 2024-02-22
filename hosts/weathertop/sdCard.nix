# stolen from https://github.com/seanybaggins/nix-home/blob/main/flake.nix

{ config, lib, pkgs, ... }:

{
  config = {
    # create a new user called deck to get the correct mount path
    users.users.deck = {
      isNormalUser = true;
      home = "/home/deck";
    };
    home-manager.users.deck = {
      services.udiskie = {
        enable = true;
        tray = "never";
      };
    };
  };
}

