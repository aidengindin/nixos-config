{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  users.users.agindin.home = "/Users/agindin";

  agindin.emacs.enable = true;
  agindin.kitty.enable = true;
  agindin.latex.enable = true;
}
