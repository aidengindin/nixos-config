{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  users.users.agindin.home = "/Users/agindin";

  agindin.emacs.enable = true;

  home-manager.users.agindin = { pkgs, ... }: {
    home.packages = with pkgs; [
      thefuck
    ];
  };
}
