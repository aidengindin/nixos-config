{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  users.users.agindin.home = "/Users/agindin";

  # agindin.alacritty.enable = true;
  agindin.emacs.enable = true;
  agindin.eza.enable = true;
  agindin.kitty.enable = true;
  agindin.latex.enable = true;
}
