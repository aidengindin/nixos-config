{ config, lib, pkgs, ... }:
{
  imports = [
    ../../common
  ];

  agindin = {
    kitty.enable = true;
    latex.enable = true;
    librewolf.enable = true;
    mpv.enable = true;
    spotify.enable = true;
  };

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "25.05";
}

