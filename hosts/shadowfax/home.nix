{ config, lib, pkgs, ... }:
{
  imports = [
    ../../common
  ];

  agindin.latex.enable = true;
  agindin.kitty.enable = true;
  agindin.mpv.enable = true;
  agindin.yabai.enable = true;
  agindin.zellij.enable = true;

  # this line should not be edited even when upgrading NixOS versions
  home-manager.users.agindin.home.stateVersion = "23.11";
}
